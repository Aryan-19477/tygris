"use client";

import { useMemo, useState } from "react";
import { Clock, CircleDashed } from "@phosphor-icons/react";

export interface SightingWindowItem {
  timestamp: string | null;
}

const PRESETS: (number | "all")[] = [5, 10, 15, 25, "all"];
const DEFAULT_PRESET = 15;

function formatDate(iso: string | null | undefined) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleDateString(undefined, { dateStyle: "medium" });
  } catch {
    return iso;
  }
}

/**
 * Dual-handle sighting window slider. `items` must already be sorted
 * newest-first; the window always anchors to the most recent end of the list.
 */
export function SightingWindowSlider<T extends SightingWindowItem>({
  items,
  renderItem,
  renderAbove,
}: {
  items: T[];
  renderItem: (item: T, globalIndex: number) => React.ReactNode;
  /** Optional extra content (e.g. a map) rendered between the slider controls
   * and the item list, given the currently visible (windowed) items. */
  renderAbove?: (visibleItems: T[]) => React.ReactNode;
}) {
  const total = items.length;
  const [startIdx, setStartIdx] = useState<number>(Math.max(0, total - Math.min(DEFAULT_PRESET, total)));

  const [lastTotal, setLastTotal] = useState(total);
  if (total !== lastTotal) {
    setLastTotal(total);
    setStartIdx(Math.max(0, total - Math.min(DEFAULT_PRESET, total)));
  }

  const endIdx = total - 1;
  const clampedStart = Math.max(0, Math.min(startIdx, endIdx));
  const visibleCount = endIdx - clampedStart + 1;

  const visibleItems = useMemo(() => items.slice(0, visibleCount), [items, visibleCount]);

  const oldestVisible = visibleItems[visibleItems.length - 1];
  const newestVisible = visibleItems[0];

  const activePreset = PRESETS.find((p) => (p === "all" ? visibleCount === total : visibleCount === p));

  function applyPreset(p: number | "all") {
    const size = p === "all" ? total : Math.min(p, total);
    setStartIdx(Math.max(0, total - size));
  }

  function handleSliderChange(newStart: number) {
    setStartIdx(Math.max(0, Math.min(newStart, endIdx)));
  }

  if (total === 0) return null;

  const fillPct = total > 1 ? ((total - visibleCount) / (total - 1)) * 100 : 0;

  return (
    <div className="space-y-3">
      <div className="rounded-2xl border border-border bg-surface p-4 shadow-sm font-mono">
        <div className="flex items-center justify-between border-b border-border pb-2.5 mb-3">
          <div className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-accent">
            <Clock size={13} />
            <span>Sighting Window</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] text-muted">
              {visibleCount >= total ? "All sightings" : `Last ${visibleCount} sightings`}
            </span>
            <span className="rounded-full border border-border-strong bg-surface-sunken px-2 py-0.5 text-[10px] font-semibold text-foreground">
              {visibleCount} / {total}
            </span>
          </div>
        </div>

        <div className="flex items-center justify-between text-[9.5px] text-muted mb-1.5">
          <span>{formatDate(oldestVisible?.timestamp as string)}</span>
          <span>{formatDate(newestVisible?.timestamp as string)}</span>
        </div>

        <div className="relative h-5 mb-1">
          <div className="absolute top-1/2 left-0 right-0 h-1 -translate-y-1/2 rounded-full bg-border" />
          <div
            className="absolute top-1/2 h-1 -translate-y-1/2 rounded-full bg-accent"
            style={{ left: `${fillPct}%`, width: `${100 - fillPct}%` }}
          />
          <input
            type="range"
            min={0}
            max={endIdx}
            value={clampedStart}
            onChange={(e) => handleSliderChange(parseInt(e.target.value, 10))}
            className="range-slider-thumb absolute top-1/2 left-0 w-full -translate-y-1/2 appearance-none bg-transparent"
            aria-label="Sighting window start"
          />
        </div>

        <div className="flex items-center justify-between gap-1.5 mt-2">
          {PRESETS.map((p) => (
            <button
              key={String(p)}
              onClick={() => applyPreset(p)}
              className={`flex-1 rounded-lg py-1.5 text-[10.5px] font-bold transition-all ${
                activePreset === p
                  ? "bg-accent text-accent-foreground shadow-sm"
                  : "border border-border bg-surface-sunken text-muted hover:text-foreground"
              }`}
            >
              {p === "all" ? "All" : p}
            </button>
          ))}
        </div>
      </div>

      {renderAbove && renderAbove(visibleItems)}

      <div className="space-y-3">
        {visibleItems.map((item, i) => renderItem(item, i))}
      </div>
    </div>
  );
}

export function EmptySightingState() {
  return (
    <div className="flex items-center justify-center gap-2 rounded-xl border border-dashed border-border-strong p-8 text-center text-xs font-mono text-muted">
      <CircleDashed size={14} />
      No sightings recorded for this individual yet.
    </div>
  );
}
