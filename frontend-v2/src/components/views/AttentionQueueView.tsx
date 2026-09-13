"use client";

import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  CheckCircle,
  Sparkle,
  ListChecks,
  Target,
  WarningCircle,
  MapPin,
  Clock,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { api, type Stats } from "@/lib/api";
import { buildAttentionQueue, type AttentionItem, type UrgencyLevel } from "@/lib/attention";

const URGENCY_STYLE: Record<UrgencyLevel, { label: string; text: string; bg: string; border: string; dot: string }> = {
  CRITICAL: { label: "Critical", text: "text-danger", bg: "bg-danger-soft", border: "border-danger/40", dot: "bg-danger" },
  CAUTION: { label: "Caution", text: "text-caution", bg: "bg-caution-soft", border: "border-caution/40", dot: "bg-caution" },
  ROUTINE: { label: "Routine", text: "text-muted", bg: "bg-surface-sunken", border: "border-border", dot: "bg-muted" },
};

function formatTime(iso: string | undefined) {
  if (!iso) return "Unknown time";
  try {
    return new Date(iso).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
  } catch {
    return iso;
  }
}

export function AttentionQueueView({
  stats,
  onResolved,
}: {
  stats: Stats | null;
  onResolved: () => void;
}) {
  const [items, setItems] = useState<AttentionItem[] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [resolving, setResolving] = useState<string | null>(null);

  const load = async () => {
    const [alertsRes, queueRes] = await Promise.all([
      api.alerts(undefined, 100),
      api.reviewQueue(),
    ]);
    const merged = buildAttentionQueue(alertsRes.alerts, queueRes.items);
    setItems(merged);
    if (merged.length > 0 && !selectedId) {
      setSelectedId(merged[0].id);
    }
  };

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect, react-hooks/exhaustive-deps
    load();
  }, []);

  const dismissItem = (item: AttentionItem) => {
    const remaining = items?.filter((i) => i.id !== item.id) ?? null;
    setItems(remaining);
    setSelectedId(remaining && remaining.length > 0 ? remaining[0].id : null);
    setResolving(null);
    onResolved();
  };

  const resolve = async (item: AttentionItem, tigerId: string | null) => {
    if (item.kind !== "identification" || !item.reviewItem) return;
    setResolving(item.id);
    await api.resolveReview(item.reviewItem.item_id, tigerId);
    dismissItem(item);
  };

  const acknowledge = async (item: AttentionItem) => {
    if (item.kind !== "conflict") return;
    setResolving(item.id);
    await api.acknowledgeAlert(item.id);
    dismissItem(item);
  };

  const selectedItem = items?.find((i) => i.id === selectedId) ?? null;
  const criticalCount = items?.filter((i) => i.urgency === "CRITICAL").length ?? 0;
  const cautionCount = items?.filter((i) => i.urgency === "CAUTION").length ?? 0;

  return (
    <div>
      <TopBar
        title="Attention Queue"
        subtitle="Village-proximity conflicts and ambiguous identifications, ranked by urgency"
        alertCount={items?.length ?? stats?.pending_review ?? 0}
      />

      <div className="grid grid-cols-1 gap-0 lg:grid-cols-[1fr_420px]">
        <div className="border-r border-border px-8 py-6">
          <div className="mb-6 flex items-center gap-6">
            <PriorityCount label="Critical" count={criticalCount} color="text-danger" />
            <PriorityCount label="Caution" count={cautionCount} color="text-caution" />
            <PriorityCount label="Total pending" count={items?.length ?? 0} color="text-foreground" />
          </div>

          {items && items.length === 0 && (
            <div className="flex min-h-75 flex-col items-center justify-center rounded-2xl border border-dashed border-border-strong text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-positive-soft text-positive">
                <ListChecks size={22} weight="fill" />
              </div>
              <p className="mt-3 text-[15px] font-medium text-foreground">Queue is clear</p>
              <p className="mt-1 text-sm text-muted">No conflicts or ambiguous captures right now</p>
            </div>
          )}

          <div className="space-y-3">
            {items?.map((item, i) => (
              <QueueCard
                key={item.id}
                item={item}
                index={i}
                active={selectedId === item.id}
                onClick={() => setSelectedId(item.id)}
              />
            ))}
          </div>
        </div>

        <div className="px-6 py-6">
          <AnimatePresence mode="wait">
            {selectedItem ? (
              <QueueDetail
                key={selectedItem.id}
                item={selectedItem}
                resolving={resolving === selectedItem.id}
                onResolve={(tigerId) => resolve(selectedItem, tigerId)}
                onAcknowledge={() => acknowledge(selectedItem)}
              />
            ) : (
              <div className="flex min-h-75 flex-col items-center justify-center rounded-2xl border border-dashed border-border-strong text-center text-muted">
                <Target size={22} />
                <p className="mt-3 text-sm">Select an item to review</p>
              </div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}

function PriorityCount({ label, count, color }: { label: string; count: number; color: string }) {
  return (
    <div className="flex items-baseline gap-2">
      <span className={`font-serif text-3xl font-medium ${color}`}>{count}</span>
      <span className="font-mono text-[11px] uppercase tracking-wide text-muted">{label}</span>
    </div>
  );
}

function QueueCard({
  item,
  index,
  active,
  onClick,
}: {
  item: AttentionItem;
  index: number;
  active: boolean;
  onClick: () => void;
}) {
  const style = URGENCY_STYLE[item.urgency];
  return (
    <motion.button
      onClick={onClick}
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.03, 0.3) }}
      className={`flex w-full items-center gap-4 rounded-xl border-l-4 bg-surface p-4 text-left transition-colors ${
        active ? `${style.border} ${style.bg}` : "border-l-border-strong hover:border-l-border"
      }`}
    >
      {item.image ? (
        <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-surface-sunken">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={item.image} alt="" className="h-full w-full object-cover" />
        </div>
      ) : (
        <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-lg bg-surface-sunken text-muted">
          <WarningCircle size={20} />
        </div>
      )}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className={`rounded-full px-2 py-0.5 font-mono text-[10px] font-semibold uppercase tracking-wide ${style.bg} ${style.text}`}>
            {style.label}
          </span>
          <span className="truncate text-sm font-medium text-foreground">{item.headline}</span>
        </div>
        <p className="mt-1 truncate text-xs text-muted">{item.detail}</p>
      </div>
    </motion.button>
  );
}

function QueueDetail({
  item,
  resolving,
  onResolve,
  onAcknowledge,
}: {
  item: AttentionItem;
  resolving: boolean;
  onResolve: (tigerId: string | null) => void;
  onAcknowledge: () => void;
}) {
  const style = URGENCY_STYLE[item.urgency];

  return (
    <motion.div
      initial={{ opacity: 0, x: 12 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: -12 }}
      transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
      className="overflow-hidden rounded-2xl border border-border bg-surface"
    >
      <div className="flex items-center justify-between border-b border-border px-5 py-4">
        <span className={`rounded-full px-2.5 py-1 font-mono text-[11px] font-semibold uppercase tracking-wide ${style.bg} ${style.text}`}>
          {style.label}
        </span>
      </div>

      {item.image && (
        <div className="aspect-video w-full bg-surface-sunken">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={item.image} alt="Capture" className="h-full w-full object-cover" />
        </div>
      )}

      <div className="p-5">
        <h3 className="text-base font-semibold text-foreground">{item.headline}</h3>
        <p className="mt-1 text-sm text-muted">{item.detail}</p>

        <div className="mt-4 flex flex-col gap-2 font-mono text-xs text-muted">
          {item.station_id && (
            <div className="flex items-center gap-2">
              <MapPin size={13} />
              <span>{item.station_id}{item.zone ? ` — ${item.zone}` : ""}</span>
            </div>
          )}
          <div className="flex items-center gap-2">
            <Clock size={13} />
            <span>{formatTime(item.timestamp)}</span>
          </div>
        </div>

        {item.kind === "identification" && item.reviewItem && (
          <>
            <div className="mt-5 mb-2 font-mono text-[11px] uppercase tracking-wide text-muted">
              Closest candidates
            </div>
            <div className="space-y-2">
              {item.reviewItem.candidates.slice(0, 4).map((c) => (
                <button
                  key={c.tiger_id}
                  disabled={resolving}
                  onClick={() => onResolve(c.tiger_id)}
                  className="group flex w-full items-center gap-3 rounded-lg border border-border px-3 py-2.5 text-left transition-colors hover:border-positive/40 hover:bg-positive-soft disabled:opacity-50"
                >
                  <span className="font-mono text-sm font-medium text-foreground">{c.tiger_id}</span>
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-sunken">
                    <div className="h-full rounded-full bg-accent" style={{ width: `${c.similarity * 100}%` }} />
                  </div>
                  <span className="w-10 text-right font-mono text-xs text-muted">
                    {(c.similarity * 100).toFixed(0)}%
                  </span>
                  <CheckCircle size={16} className="text-positive opacity-0 transition-opacity group-hover:opacity-100" />
                </button>
              ))}
            </div>

            <button
              disabled={resolving}
              onClick={() => onResolve(null)}
              className="mt-5 flex w-full items-center justify-center gap-2 rounded-full bg-accent px-4 py-2.5 text-sm font-medium text-accent-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              <Sparkle size={14} weight="fill" />
              None of these, enroll as new individual
            </button>
          </>
        )}

        {item.kind === "conflict" && (
          <>
            <div className="mt-5 rounded-xl border border-border bg-surface-sunken p-3 text-xs text-muted">
              This is a movement alert, not an identification decision — the tiger has already been identified.
              Coordinate a field response if the proximity warrants one.
            </div>

            <button
              disabled={resolving}
              onClick={onAcknowledge}
              className="mt-5 flex w-full items-center justify-center gap-2 rounded-full bg-accent px-4 py-2.5 text-sm font-medium text-accent-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              <CheckCircle size={14} weight="fill" />
              Mark as handled
            </button>
          </>
        )}
      </div>
    </motion.div>
  );
}
