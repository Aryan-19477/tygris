"use client";

import { useMemo, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  Trash,
  ArrowCounterClockwise,
  ImageBroken,
  Clock,
  HardDrive,
  WarningCircle,
  CheckSquare,
  Square,
  FunnelSimple,
  ShieldCheck,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import {
  MOCK_FRAMES,
  DEFAULT_CONFIDENCE_THRESHOLD,
  estimateProcessingSeconds,
  formatBytes,
  formatDuration,
  type BlankFrame,
} from "@/lib/blankFrames";
import type { Stats } from "@/lib/api";
import { useLanguage } from "@/lib/i18n/LanguageContext";

type FrameStatus = "quarantined" | "kept" | "purged";

export function BlankFrameTrashView({ stats }: { stats: Stats | null }) {
  const { t } = useLanguage();
  const [frames] = useState<BlankFrame[]>(MOCK_FRAMES);
  const [statusById, setStatusById] = useState<Record<string, FrameStatus>>({});
  const [threshold, setThreshold] = useState(DEFAULT_CONFIDENCE_THRESHOLD);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [showPurged, setShowPurged] = useState(false);
  const [confirmPurge, setConfirmPurge] = useState<"selected" | "all" | null>(null);

  const statusOf = (id: string): FrameStatus => statusById[id] ?? "quarantined";

  const visible = useMemo(
    () =>
      frames.filter((f) => {
        const s = statusById[f.frame_id] ?? "quarantined";
        return (showPurged ? true : s !== "purged") && f.confidence >= threshold;
      }),
    [frames, statusById, threshold, showPurged]
  );

  const quarantined = useMemo(
    () => frames.filter((f) => (statusById[f.frame_id] ?? "quarantined") === "quarantined"),
    [frames, statusById]
  );
  const kept = useMemo(
    () => frames.filter((f) => statusById[f.frame_id] === "kept"),
    [frames, statusById]
  );
  const purged = useMemo(
    () => frames.filter((f) => statusById[f.frame_id] === "purged"),
    [frames, statusById]
  );

  const spaceSavedKb = purged.reduce((sum, f) => sum + f.file_size_kb, 0);
  const timeSavedSec = estimateProcessingSeconds(quarantined.length + purged.length);

  const toggleSelect = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const selectAllVisible = () => {
    const quarantinedVisible = visible.filter((f) => statusOf(f.frame_id) === "quarantined");
    setSelected((prev) => {
      const allSelected = quarantinedVisible.every((f) => prev.has(f.frame_id));
      if (allSelected) return new Set();
      return new Set(quarantinedVisible.map((f) => f.frame_id));
    });
  };

  const setStatusForIds = (ids: string[], status: FrameStatus) => {
    setStatusById((prev) => {
      const next = { ...prev };
      ids.forEach((id) => {
        next[id] = status;
      });
      return next;
    });
    setSelected((prev) => {
      const next = new Set(prev);
      ids.forEach((id) => next.delete(id));
      return next;
    });
  };

  const restoreOne = (id: string) => setStatusForIds([id], "kept");
  const purgeOne = (id: string) => setStatusForIds([id], "purged");

  const restoreSelected = () => setStatusForIds(Array.from(selected), "kept");
  const requestPurgeSelected = () => setConfirmPurge("selected");
  const requestPurgeAllQuarantined = () => setConfirmPurge("all");

  const confirmPurgeAction = () => {
    if (confirmPurge === "selected") {
      setStatusForIds(Array.from(selected), "purged");
    } else if (confirmPurge === "all") {
      setStatusForIds(quarantined.map((f) => f.frame_id), "purged");
    }
    setConfirmPurge(null);
  };

  const selectedQuarantinedCount = Array.from(selected).filter(
    (id) => statusOf(id) === "quarantined"
  ).length;

  return (
    <div>
      <TopBar
        title={t("trash.title")}
        subtitle={t("trash.subtitle")}
        alertCount={stats?.pending_review ?? 0}
      />

      <div className="px-8 py-6 space-y-6">
        {/* Summary stats */}
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          <StatBlock
            icon={<ImageBroken size={16} />}
            label={t("trash.framesRemoved")}
            value={String(purged.length + quarantined.length)}
          />
          <StatBlock
            icon={<HardDrive size={16} />}
            label={t("trash.spaceSaved")}
            value={spaceSavedKb > 0 ? formatBytes(spaceSavedKb) : "—"}
          />
          <StatBlock
            icon={<Clock size={16} />}
            label={t("trash.reviewTimeSaved")}
            value={formatDuration(timeSavedSec)}
          />
          <StatBlock
            icon={<ArrowCounterClockwise size={16} />}
            label={t("trash.restoredToDataset")}
            value={String(kept.length)}
          />
          <StatBlock
            icon={<ShieldCheck size={16} />}
            label={t("trash.inQuarantine")}
            value={String(quarantined.length)}
            tone={quarantined.length > 0 ? "caution" : undefined}
          />
        </div>

        {/* Explainer */}
        <div className="flex items-start gap-2.5 rounded-xl border border-border bg-surface-sunken p-3.5 text-xs text-muted">
          <WarningCircle size={15} className="mt-0.5 shrink-0" />
          <span>{t("trash.explainer")}</span>
        </div>

        {/* Controls */}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border bg-surface p-4">
          <div className="flex flex-wrap items-center gap-4">
            <button
              onClick={selectAllVisible}
              className="flex items-center gap-2 rounded-full border border-border-strong px-3 py-1.5 text-sm font-medium text-foreground hover:bg-surface-sunken"
            >
              {visible.filter((f) => statusOf(f.frame_id) === "quarantined").length > 0 &&
              visible
                .filter((f) => statusOf(f.frame_id) === "quarantined")
                .every((f) => selected.has(f.frame_id)) ? (
                <CheckSquare size={15} className="text-accent" weight="fill" />
              ) : (
                <Square size={15} />
              )}
              {t("trash.selectAllQuarantined")}
            </button>

            <div className="flex items-center gap-2">
              <FunnelSimple size={14} className="text-muted" />
              <label className="font-mono text-[11px] uppercase tracking-wide text-muted">
                {t("trash.confidenceLabel", { pct: (threshold * 100).toFixed(0) })}
              </label>
              <input
                type="range"
                min={0.5}
                max={0.99}
                step={0.01}
                value={threshold}
                onChange={(e) => setThreshold(Number(e.target.value))}
                className="range-slider-thumb w-32 accent-[var(--accent)]"
              />
            </div>

            <label className="flex items-center gap-2 text-xs text-muted">
              <input
                type="checkbox"
                checked={showPurged}
                onChange={(e) => setShowPurged(e.target.checked)}
                className="h-3.5 w-3.5 accent-[var(--accent)]"
              />
              {t("trash.showPurgedFrames")}
            </label>
          </div>

          <div className="flex items-center gap-2">
            {selected.size > 0 && (
              <>
                <button
                  onClick={restoreSelected}
                  className="flex items-center gap-1.5 rounded-full border border-positive/30 bg-positive-soft px-3 py-1.5 text-sm font-medium text-positive hover:bg-positive-soft/80"
                >
                  <ArrowCounterClockwise size={14} />
                  {t("trash.restoreCount", { count: selectedQuarantinedCount || selected.size })}
                </button>
                <button
                  onClick={requestPurgeSelected}
                  className="flex items-center gap-1.5 rounded-full border border-danger/30 bg-danger-soft px-3 py-1.5 text-sm font-medium text-danger hover:bg-danger-soft/80"
                >
                  <Trash size={14} />
                  {t("trash.purgeSelected")}
                </button>
              </>
            )}
            {quarantined.length > 0 && (
              <button
                onClick={requestPurgeAllQuarantined}
                className="flex items-center gap-1.5 rounded-full border border-border-strong px-3 py-1.5 text-sm font-medium text-muted hover:bg-surface-sunken hover:text-danger"
              >
                <Trash size={14} />
                {t("trash.emptyTrash", { count: quarantined.length })}
              </button>
            )}
          </div>
        </div>

        {/* Grid */}
        {visible.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-border-strong py-16 text-center">
            <ImageBroken size={28} className="text-muted" />
            <p className="text-sm font-medium text-foreground">{t("trash.noFramesMatch")}</p>
            <p className="text-xs text-muted">{t("trash.lowerThreshold")}</p>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
            <AnimatePresence mode="popLayout">
              {visible.map((frame) => (
                <FrameCard
                  key={frame.frame_id}
                  frame={frame}
                  status={statusOf(frame.frame_id)}
                  selected={selected.has(frame.frame_id)}
                  onToggleSelect={() => toggleSelect(frame.frame_id)}
                  onRestore={() => restoreOne(frame.frame_id)}
                  onPurge={() => purgeOne(frame.frame_id)}
                />
              ))}
            </AnimatePresence>
          </div>
        )}
      </div>

      {confirmPurge && (
        <PurgeConfirmDialog
          count={confirmPurge === "selected" ? selectedQuarantinedCount || selected.size : quarantined.length}
          onCancel={() => setConfirmPurge(null)}
          onConfirm={confirmPurgeAction}
        />
      )}
    </div>
  );
}

function FrameCard({
  frame,
  status,
  selected,
  onToggleSelect,
  onRestore,
  onPurge,
}: {
  frame: BlankFrame;
  status: FrameStatus;
  selected: boolean;
  onToggleSelect: () => void;
  onRestore: () => void;
  onPurge: () => void;
}) {
  const { t } = useLanguage();
  const isPurged = status === "purged";
  const isKept = status === "kept";

  return (
    <motion.div
      layout
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.9 }}
      transition={{ duration: 0.2 }}
      className={`group relative overflow-hidden rounded-xl border bg-surface ${
        selected ? "border-accent ring-2 ring-accent/30" : "border-border"
      } ${isPurged ? "opacity-50" : ""}`}
    >
      <div className="relative aspect-square bg-surface-sunken">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={frame.thumbnail_src} alt="" className="h-full w-full object-cover" />

        {!frame.is_actually_blank && status === "quarantined" && (
          <span className="absolute bottom-2 right-2 flex items-center gap-1 rounded-full bg-caution px-2 py-0.5 font-mono text-[10px] font-medium text-white">
            <WarningCircle size={10} weight="fill" />
            {t("trash.checkThis")}
          </span>
        )}

        {status === "quarantined" && (
          <button
            onClick={onToggleSelect}
            className="absolute left-2 top-2 flex h-6 w-6 items-center justify-center rounded-md bg-black/40 text-white backdrop-blur-sm hover:bg-black/60"
          >
            {selected ? <CheckSquare size={14} weight="fill" /> : <Square size={14} />}
          </button>
        )}

        <span className="absolute right-2 top-2 rounded-full bg-black/50 px-2 py-0.5 font-mono text-[10px] font-medium text-white backdrop-blur-sm">
          {t("trash.blankPct", { pct: (frame.confidence * 100).toFixed(0) })}
        </span>

        {isKept && (
          <span className="absolute bottom-2 left-2 rounded-full bg-positive px-2 py-0.5 font-mono text-[10px] font-medium text-white">
            {t("trash.kept")}
          </span>
        )}
        {isPurged && (
          <span className="absolute bottom-2 left-2 rounded-full bg-danger px-2 py-0.5 font-mono text-[10px] font-medium text-white">
            {t("trash.purged")}
          </span>
        )}
      </div>

      <div className="p-2.5">
        <div className="truncate font-mono text-[11px] text-foreground">{frame.filename}</div>
        <div className="mt-0.5 flex items-center justify-between text-[10px] text-muted">
          <span>{frame.station_id}</span>
          <span>{formatBytes(frame.file_size_kb)}</span>
        </div>

        {status === "quarantined" && (
          <div className="mt-2 flex items-center gap-1.5">
            <button
              onClick={onRestore}
              className="flex flex-1 items-center justify-center gap-1 rounded-lg border border-positive/30 bg-positive-soft py-1 text-[11px] font-medium text-positive hover:bg-positive-soft/80"
            >
              <ArrowCounterClockwise size={11} />
              Restore
            </button>
            <button
              onClick={onPurge}
              className="flex flex-1 items-center justify-center gap-1 rounded-lg border border-danger/30 bg-danger-soft py-1 text-[11px] font-medium text-danger hover:bg-danger-soft/80"
            >
              <Trash size={11} />
              Purge
            </button>
          </div>
        )}
        {isKept && (
          <div className="mt-2 rounded-lg bg-surface-sunken py-1 text-center text-[11px] text-muted">
            Back in working dataset
          </div>
        )}
      </div>
    </motion.div>
  );
}

function PurgeConfirmDialog({
  count,
  onCancel,
  onConfirm,
}: {
  count: number;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-2000 flex items-center justify-center slideover-backdrop"
      onClick={onCancel}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="mx-4 w-full max-w-sm rounded-2xl border border-border bg-surface p-5 shadow-2xl"
      >
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-danger-soft text-danger">
            <Trash size={18} />
          </div>
          <div>
            <div className="text-base font-medium text-foreground">Permanently purge {count} frame{count === 1 ? "" : "s"}?</div>
          </div>
        </div>
        <p className="mt-3 text-sm text-muted">
          This removes the frames from quarantine for good. Nothing selected here has been touched
          in the working dataset — this only affects frames already staged as blank.
        </p>
        <div className="mt-5 flex items-center justify-end gap-2">
          <button
            onClick={onCancel}
            className="rounded-full border border-border-strong px-3.5 py-2 text-sm font-medium text-foreground hover:bg-surface-sunken"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="flex items-center gap-1.5 rounded-full bg-danger px-3.5 py-2 text-sm font-medium text-white hover:bg-danger/90"
          >
            <Trash size={14} />
            Purge permanently
          </button>
        </div>
      </div>
    </div>
  );
}

function StatBlock({
  icon,
  label,
  value,
  tone,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  tone?: "caution";
}) {
  return (
    <div className="rounded-xl border border-border bg-surface p-4">
      <div className="flex items-center gap-1.5 font-mono text-[11px] uppercase tracking-wide text-muted">
        {icon}
        {label}
      </div>
      <div className={`mt-1.5 font-serif text-2xl font-medium tabular-nums ${tone === "caution" ? "text-caution" : "text-foreground"}`}>
        {value}
      </div>
    </div>
  );
}
