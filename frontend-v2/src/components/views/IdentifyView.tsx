"use client";

import { useEffect, useMemo, useState } from "react";
import { MapPin, MagnifyingGlass, CheckCircle, Camera, Info } from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { IdentifyCapture } from "@/components/IdentifyCapture";
import { api, type Stats, type GISStation } from "@/lib/api";

export function IdentifyView({ stats }: { stats: Stats | null }) {
  const [stations, setStations] = useState<GISStation[]>([]);
  const [station, setStation] = useState<GISStation | null>(null);
  const [query, setQuery] = useState("");

  useEffect(() => {
    api.stations().then((res) => setStations(res.stations)).catch(() => {});
  }, []);

  const filtered = useMemo(() => {
    if (!query.trim()) return stations.slice(0, 40);
    const q = query.toLowerCase();
    return stations
      .filter(
        (s) =>
          s.camera_id.toLowerCase().includes(q) ||
          (s.sub_region || "").toLowerCase().includes(q) ||
          s.zone.toLowerCase().includes(q)
      )
      .slice(0, 40);
  }, [stations, query]);

  return (
    <div>
      <TopBar
        title="Identify"
        subtitle="Upload a camera trap photo for on-the-spot tiger identification"
        alertCount={stats?.pending_review ?? 0}
      />

      <div className="grid grid-cols-1 gap-0 lg:grid-cols-[360px_1fr]">
        <div className="border-r border-border px-6 py-6">
          <div className="mb-3 flex items-center gap-2 font-mono text-[11px] uppercase tracking-wide text-muted">
            <MapPin size={13} />
            <span>Camera station</span>
          </div>

          {station ? (
            <div className="mb-4 flex items-center justify-between rounded-xl border border-accent/40 bg-accent-soft p-3.5">
              <div>
                <div className="font-mono text-sm font-semibold text-foreground">{station.camera_id}</div>
                <div className="text-xs text-muted">{station.zone} — {station.sub_region || "Unknown range"}</div>
              </div>
              <button
                onClick={() => setStation(null)}
                className="rounded-full border border-border-strong bg-surface px-3 py-1 text-xs font-medium text-foreground hover:bg-surface-sunken"
              >
                Change
              </button>
            </div>
          ) : (
            <>
              <div className="relative mb-3">
                <MagnifyingGlass size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search station ID or range..."
                  className="w-full rounded-xl border border-border bg-surface py-2.5 pl-9 pr-3 text-sm text-foreground placeholder:text-muted focus:border-accent focus:outline-none"
                />
              </div>

              <div className="max-h-125 space-y-1.5 overflow-y-auto pr-1">
                {filtered.map((s) => (
                  <button
                    key={s.camera_id}
                    onClick={() => setStation(s)}
                    className="flex w-full items-center justify-between rounded-lg border border-border bg-surface px-3 py-2.5 text-left transition-colors hover:border-accent/40 hover:bg-accent-soft"
                  >
                    <div className="flex items-center gap-2.5">
                      <Camera size={14} className="text-muted" />
                      <div>
                        <div className="font-mono text-xs font-semibold text-foreground">{s.camera_id}</div>
                        <div className="text-[11px] text-muted">{s.sub_region || s.zone}</div>
                      </div>
                    </div>
                    <span
                      className={`rounded-full px-2 py-0.5 font-mono text-[10px] font-semibold ${
                        s.operational_status === "OPERATIONAL" ? "bg-positive-soft text-positive" : "bg-danger-soft text-danger"
                      }`}
                    >
                      {s.operational_status === "OPERATIONAL" ? "ONLINE" : "OFFLINE"}
                    </span>
                  </button>
                ))}
                {filtered.length === 0 && (
                  <div className="rounded-xl border border-dashed border-border-strong p-6 text-center text-xs text-muted">
                    No stations match &quot;{query}&quot;
                  </div>
                )}
              </div>

              <button
                onClick={() => setStation(null)}
                className="mt-3 flex w-full items-center justify-center gap-2 rounded-lg border border-dashed border-border-strong px-3 py-2 text-xs font-medium text-muted hover:border-accent/40 hover:text-foreground"
              >
                Skip — not tied to a specific station
              </button>
            </>
          )}

          <div className="mt-6 flex items-start gap-2 rounded-xl bg-surface-sunken p-3.5 text-xs text-muted">
            <Info size={14} className="mt-0.5 shrink-0" />
            <span>
              Tying a capture to its station records the sighting at that camera&apos;s real coordinates.
              Without one, the sighting is logged without a location.
            </span>
          </div>
        </div>

        <div className="px-6 py-6 sm:px-8">
          {station && (
            <div className="mb-4 flex items-center gap-2 text-xs text-muted">
              <CheckCircle size={14} className="text-positive" />
              <span>
                Uploading for <span className="font-mono font-semibold text-foreground">{station.camera_id}</span>
              </span>
            </div>
          )}
          <div className="rounded-2xl border border-border bg-surface p-5">
            <IdentifyCapture key={station?.camera_id ?? "none"} stationId={station?.camera_id} />
          </div>
        </div>
      </div>
    </div>
  );
}
