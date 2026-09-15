"use client";

import { useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  CheckCircle,
  Sparkle,
  ListChecks,
  Target,
  WarningCircle,
  MapPin,
  Clock,
  Camera,
  PawPrint,
  ChartLineUp,
  Trash,
  ArrowRight,
  CaretDown,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { Card, SectionLabel, Pill, StatCard, EmptyState } from "@/components/ui";
import { useNavigation } from "@/lib/navigation-context";
import { api, type Stats, type GalleryIndividual, type GISStation } from "@/lib/api";
import { buildAttentionQueue, type AttentionItem, type UrgencyLevel } from "@/lib/attention";
import { useLanguage } from "@/lib/i18n/LanguageContext";

/**
 * Captures — merges what used to be three separate top-level pages
 * (Attention Queue, Station Health, and the "go look at the trash page"
 * link) into one screen: the review queue and the camera network are two
 * lenses on the same capture pipeline, not two destinations a ranger has
 * to remember to check separately. Station chips filter the review list
 * by camera; the network rollup (uptime, most-active stations) is a
 * disclosure below it rather than its own nav item.
 */

const URGENCY_STYLE: Record<UrgencyLevel, { labelKey: string; bg: string; border: string; tone: "danger" | "caution" | "neutral" }> = {
  CRITICAL: { labelKey: "attention.urgencyCritical", bg: "bg-danger-soft", border: "border-danger/40", tone: "danger" },
  CAUTION: { labelKey: "attention.urgencyCaution", bg: "bg-caution-soft", border: "border-caution/40", tone: "caution" },
  ROUTINE: { labelKey: "attention.urgencyRoutine", bg: "bg-surface-sunken", border: "border-border", tone: "neutral" },
};

function formatTime(iso: string | undefined, unknownLabel: string) {
  if (!iso) return unknownLabel;
  try {
    return new Date(iso).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
  } catch {
    return iso;
  }
}

export function CapturesView({
  stats,
  onResolved,
}: {
  stats: Stats | null;
  onResolved: () => void;
}) {
  const { navigate } = useNavigation();
  const { t } = useLanguage();

  const [items, setItems] = useState<AttentionItem[] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [resolving, setResolving] = useState<string | null>(null);

  const [stations, setStations] = useState<GISStation[] | null>(null);
  const [individuals, setIndividuals] = useState<GalleryIndividual[] | null>(null);
  const [activeStation, setActiveStation] = useState<string | null>(null);
  const [networkOpen, setNetworkOpen] = useState(false);

  const load = async () => {
    const [alertsRes, queueRes] = await Promise.all([
      api.alerts(undefined, 100),
      api.reviewQueue(),
    ]);
    const merged = buildAttentionQueue(alertsRes.alerts, queueRes.items);
    setItems(merged);
    setSelectedId((prev) => prev ?? (merged.length > 0 ? merged[0].id : null));
  };

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
    api.stations().then((res) => setStations(res.stations)).catch(() => {});
    api.gallery().then((res) => setIndividuals(res.individuals)).catch(() => {});
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

  const visibleItems = useMemo(
    () => (activeStation ? (items ?? []).filter((i) => i.station_id === activeStation) : items ?? []),
    [items, activeStation]
  );
  const selectedItem = visibleItems.find((i) => i.id === selectedId) ?? visibleItems[0] ?? null;

  const criticalCount = visibleItems.filter((i) => i.urgency === "CRITICAL").length;
  const cautionCount = visibleItems.filter((i) => i.urgency === "CAUTION").length;

  const offline = useMemo(() => (stations ?? []).filter((s) => s.operational_status !== "OPERATIONAL"), [stations]);
  const totalStations = stats?.total_stations ?? stations?.length;
  const operational = stats?.active_stations ?? (stations ? stations.length - offline.length : undefined);
  const uptimePct =
    totalStations && operational !== undefined && totalStations > 0
      ? ((operational / totalStations) * 100).toFixed(1)
      : null;

  const stationCounts = useMemo(() => {
    if (!stations || !individuals) return null;
    return stations
      .map((s) => ({ station: s, individuals: individuals.filter((i) => (i.stations ?? []).includes(s.camera_id)).length }))
      .sort((a, b) => b.individuals - a.individuals)
      .slice(0, 8);
  }, [stations, individuals]);

  return (
    <div>
      <TopBar
        title={t("nav.captures")}
        subtitle={t("captures.subtitle")}
        alertCount={items?.length ?? stats?.pending_review ?? 0}
      />

      <div className="px-5 py-6 sm:px-8">
        {/* station strip — click a camera to filter the review queue to it */}
        {stations && stations.length > 0 && (
          <div className="mb-5">
            <SectionLabel icon={<Camera size={12} />} className="mb-2">
              {t("captures.networkHeading")}
              {activeStation && (
                <button
                  onClick={() => setActiveStation(null)}
                  className="ml-auto normal-case tracking-normal text-accent hover:underline"
                >
                  {t("captures.clearStationFilter")} ✕
                </button>
              )}
            </SectionLabel>
            <div className="flex gap-2 overflow-x-auto pb-1">
              {stations.map((s) => {
                const active = activeStation === s.camera_id;
                const ok = s.operational_status === "OPERATIONAL";
                return (
                  <button
                    key={s.camera_id}
                    onClick={() => setActiveStation(active ? null : s.camera_id)}
                    className={`flex shrink-0 items-center gap-2 rounded-full border px-3 py-1.5 text-left transition-colors ${
                      active ? "border-accent-strong bg-accent text-accent-foreground" : "border-border bg-surface hover:border-border-strong"
                    }`}
                  >
                    <span className={`h-2 w-2 shrink-0 rounded-full ${ok ? "bg-positive" : "bg-danger"}`} />
                    <span className={`font-mono text-xs font-medium ${active ? "text-accent-foreground" : "text-foreground"}`}>
                      {s.camera_id}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {offline.length > 0 && (
          <div className="mb-5 rounded-xl border border-caution/30 bg-caution-soft p-4">
            <div className="mb-2 flex items-center gap-2 text-caution">
              <WarningCircle size={16} weight="fill" />
              <span className="text-sm font-medium">
                {t("stations.stationsNotReporting", { count: offline.length, plural: offline.length > 1 ? "s" : "" })}
              </span>
            </div>
            <div className="flex flex-wrap gap-1.5">
              {offline.map((s) => (
                <button
                  key={s.camera_id}
                  onClick={() => setActiveStation(s.camera_id)}
                  className="rounded-full bg-surface px-2.5 py-1 font-mono text-xs text-foreground ring-1 ring-caution/15 hover:ring-caution/40"
                >
                  {s.camera_id}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="mb-6 flex items-center gap-6">
          <PriorityCount label={t("attention.urgencyCritical")} count={criticalCount} color="text-danger" />
          <PriorityCount label={t("attention.urgencyCaution")} count={cautionCount} color="text-caution" />
          <PriorityCount label={t("attention.priorityTotalPending")} count={visibleItems.length} color="text-foreground" />
        </div>

        <div className="grid grid-cols-1 gap-0 lg:grid-cols-[1fr_420px]">
          <div className="border-border pr-0 lg:border-r lg:pr-8">
            {items && visibleItems.length === 0 && (
              <EmptyState
                tone="positive"
                icon={<ListChecks size={22} weight="fill" />}
                title={t("attention.queueClear")}
                subtitle={t("attention.queueClearSub")}
              />
            )}

            <div className="space-y-3">
              {visibleItems.map((item, i) => (
                <QueueCard
                  key={item.id}
                  item={item}
                  index={i}
                  active={selectedItem?.id === item.id}
                  onClick={() => setSelectedId(item.id)}
                />
              ))}
            </div>
          </div>

          <div className="px-0 pt-6 lg:px-6 lg:pt-0">
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
                <EmptyState icon={<Target size={22} />} title={t("attention.selectItem")} />
              )}
            </AnimatePresence>
          </div>
        </div>

        {/* camera network rollup — a disclosure, not a destination */}
        <div className="mt-8 border-t border-border pt-5">
          <button
            onClick={() => setNetworkOpen((v) => !v)}
            className="flex w-full items-center justify-between gap-3 text-left"
          >
            <div className="flex items-center gap-3">
              <ChartLineUp size={16} className="text-muted" />
              <span className="text-sm font-medium text-foreground">
                {networkOpen ? t("captures.hideNetwork") : t("captures.showNetwork")}
              </span>
              {totalStations !== undefined && (
                <span className="font-mono text-xs text-muted">
                  {operational}/{totalStations} {t("stations.operational").toLowerCase()}
                  {uptimePct !== null ? ` · ${uptimePct}%` : ""}
                </span>
              )}
            </div>
            <CaretDown size={14} weight="bold" className={`text-muted transition-transform ${networkOpen ? "rotate-180" : ""}`} />
          </button>

          {networkOpen && (
            <div className="mt-4 space-y-5">
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                <StatCard label={t("stations.totalStations")} value={totalStations} />
                <StatCard
                  label={t("stations.operational")}
                  value={operational}
                  hint={uptimePct !== null ? t("stations.ofNetwork", { pct: uptimePct! }) : undefined}
                />
                <StatCard
                  label={t("stations.offlineDegraded")}
                  value={offline.length}
                  tone={offline.length > 0 ? "caution" : undefined}
                  hint={offline.length > 0 ? t("stations.needsService") : undefined}
                />
                <StatCard label={t("stations.trapNights")} value={stats?.trap_nights_simulated} />
              </div>

              <div>
                <SectionLabel className="mb-3">{t("stations.mostActive")}</SectionLabel>
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                  {stationCounts ? (
                    stationCounts.map((s, i) => (
                      <motion.div
                        key={s.station.camera_id}
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.35, delay: i * 0.03 }}
                      >
                        <Card padding="lg">
                          <div className="flex items-center justify-between">
                            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-accent-soft text-accent">
                              <Camera size={17} />
                            </div>
                            <Pill tone={s.station.operational_status === "OPERATIONAL" ? "positive" : "danger"}>
                              {s.station.operational_status === "OPERATIONAL" ? t("common.online") : t("common.offline")}
                            </Pill>
                          </div>
                          <div className="mt-3 font-mono text-base font-semibold text-foreground">{s.station.camera_id}</div>
                          <div className="mt-1 text-xs text-muted">
                            {s.station.zone} — {s.station.sub_region || t("common.unknownRange")}
                          </div>
                          <div className="mt-2 flex items-center gap-1.5 text-sm text-muted">
                            <PawPrint size={13} />
                            {t("stations.individualsSeen", { count: s.individuals })}
                          </div>
                        </Card>
                      </motion.div>
                    ))
                  ) : (
                    <div className="col-span-full text-sm text-muted">{t("stations.loadingStations")}</div>
                  )}
                </div>
              </div>

              <button onClick={() => navigate("trash")} className="block w-full text-left">
                <Card padding="lg" interactive className="flex items-center justify-between gap-4 hover:bg-surface-sunken">
                  <div className="flex items-center gap-3">
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-danger-soft text-danger">
                      <Trash size={17} />
                    </div>
                    <div>
                      <div className="text-sm font-medium text-foreground">{t("stations.blankFrameTrash")}</div>
                      <p className="mt-0.5 text-xs text-muted">{t("stations.blankFrameTrashDesc")}</p>
                    </div>
                  </div>
                  <ArrowRight size={16} className="shrink-0 text-muted" />
                </Card>
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function PriorityCount({ label, count, color }: { label: string; count: number; color: string }) {
  return (
    <div className="flex items-baseline gap-2">
      <span className={`font-serif text-3xl font-medium ${color}`}>{count}</span>
      <span className="font-mono text-2xs uppercase tracking-wide text-muted">{label}</span>
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
  const { t } = useLanguage();
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
          <Pill tone={style.tone}>{t(style.labelKey)}</Pill>
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
  const { t } = useLanguage();
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
        <Pill tone={style.tone} className="px-2.5 py-1">
          {t(style.labelKey)}
        </Pill>
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
            <span>{formatTime(item.timestamp, t("common.unknownTime"))}</span>
          </div>
        </div>

        {item.kind === "identification" && item.reviewItem && (
          <>
            <SectionLabel className="mt-5 mb-2">{t("attention.closestCandidates")}</SectionLabel>
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
              {t("attention.enrollNew")}
            </button>
          </>
        )}

        {item.kind === "conflict" && (
          <>
            <div className="mt-5 rounded-xl border border-border bg-surface-sunken p-3 text-xs text-muted">
              {t("attention.conflictExplainer")}
            </div>

            <button
              disabled={resolving}
              onClick={onAcknowledge}
              className="mt-5 flex w-full items-center justify-center gap-2 rounded-full bg-accent px-4 py-2.5 text-sm font-medium text-accent-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              <CheckCircle size={14} weight="fill" />
              {t("attention.markHandled")}
            </button>
          </>
        )}
      </div>
    </motion.div>
  );
}
