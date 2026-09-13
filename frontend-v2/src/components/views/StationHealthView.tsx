"use client";

import { useEffect, useMemo, useState } from "react";
import { motion } from "motion/react";
import { Camera, PawPrint, ChartLineUp, WarningCircle, Trash, ArrowRight } from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { useNavigation } from "@/lib/navigation-context";
import { api, type Stats, type GalleryIndividual, type GISStation } from "@/lib/api";

export function StationHealthView({ stats }: { stats: Stats | null }) {
  const { navigate } = useNavigation();
  const [individuals, setIndividuals] = useState<GalleryIndividual[] | null>(null);
  const [stations, setStations] = useState<GISStation[] | null>(null);

  useEffect(() => {
    api.gallery().then((res) => setIndividuals(res.individuals)).catch(() => {});
    api.stations().then((res) => setStations(res.stations)).catch(() => {});
  }, []);

  const offline = useMemo(
    () => (stations ?? []).filter((s) => s.operational_status !== "OPERATIONAL"),
    [stations]
  );

  const stationCounts = useMemo(() => {
    if (!stations || !individuals) return null;
    return stations
      .map((s) => ({
        station: s,
        individuals: individuals.filter((i) => (i.stations ?? []).includes(s.camera_id)).length,
      }))
      .sort((a, b) => b.individuals - a.individuals)
      .slice(0, 16);
  }, [stations, individuals]);

  const totalStations = stats?.total_stations ?? stations?.length;
  const operational = stats?.active_stations ?? (stations ? stations.length - offline.length : undefined);
  const uptimePct =
    totalStations && operational !== undefined && totalStations > 0
      ? ((operational / totalStations) * 100).toFixed(1)
      : null;

  const [showAllOffline, setShowAllOffline] = useState(false);
  const visibleOffline = showAllOffline ? offline : offline.slice(0, 20);

  return (
    <div>
      <TopBar
        title="Station Health"
        subtitle="Camera network uptime and monitoring coverage across the reserve"
        alertCount={stats?.pending_review ?? 0}
      />
      <div className="px-8 py-6 space-y-6">
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatBlock label="Total stations" value={totalStations} />
          <StatBlock
            label="Operational"
            value={operational}
            hint={uptimePct !== null ? `${uptimePct}% of network` : undefined}
          />
          <StatBlock
            label="Offline / degraded"
            value={offline.length}
            tone={offline.length > 0 ? "caution" : undefined}
            hint={offline.length > 0 ? "Needs field service" : undefined}
          />
          <StatBlock label="Trap-nights logged" value={stats?.trap_nights_simulated} />
        </div>

        {offline.length > 0 && (
          <div className="rounded-xl border border-caution/30 bg-caution-soft p-4">
            <div className="mb-2 flex items-center gap-2 text-caution">
              <WarningCircle size={16} weight="fill" />
              <span className="text-sm font-medium">
                {offline.length} station{offline.length > 1 ? "s" : ""} not reporting
              </span>
            </div>
            <div className="flex flex-wrap gap-1.5">
              {visibleOffline.map((s) => (
                <span
                  key={s.camera_id}
                  title={`${s.zone} — ${s.sub_region || "Unknown range"}`}
                  className="rounded-full bg-surface px-2.5 py-1 font-mono text-xs text-foreground ring-1 ring-caution/15"
                >
                  {s.camera_id}
                </span>
              ))}
              {offline.length > 20 && (
                <button
                  onClick={() => setShowAllOffline((v) => !v)}
                  className="rounded-full bg-surface px-2.5 py-1 font-mono text-xs text-muted transition-colors hover:text-caution focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-caution"
                >
                  {showAllOffline ? "show fewer" : `+${offline.length - 20} more`}
                </button>
              )}
            </div>
          </div>
        )}

        <div>
          <div className="mb-3 flex items-center gap-2">
            <ChartLineUp size={16} className="text-muted" />
            <span className="font-mono text-[11px] uppercase tracking-wide text-muted">
              Most active stations
            </span>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {stationCounts ? (
              stationCounts.map((s, i) => (
                <motion.div
                  key={s.station.camera_id}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.35, delay: i * 0.03 }}
                  className="rounded-2xl border border-border bg-surface p-5"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex h-10 w-10 items-center justify-center rounded-full bg-accent-soft text-accent">
                      <Camera size={17} />
                    </div>
                    <span
                      className={`rounded-full px-2 py-0.5 font-mono text-[10px] font-semibold ${
                        s.station.operational_status === "OPERATIONAL"
                          ? "bg-positive-soft text-positive"
                          : "bg-danger-soft text-danger"
                      }`}
                    >
                      {s.station.operational_status === "OPERATIONAL" ? "ONLINE" : "OFFLINE"}
                    </span>
                  </div>
                  <div className="mt-3 font-mono text-base font-semibold text-foreground">{s.station.camera_id}</div>
                  <div className="mt-1 text-xs text-muted">{s.station.zone} — {s.station.sub_region || "Unknown range"}</div>
                  <div className="mt-2 flex items-center gap-1.5 text-sm text-muted">
                    <PawPrint size={13} />
                    {s.individuals} individuals seen
                  </div>
                </motion.div>
              ))
            ) : (
              <div className="col-span-full text-sm text-muted">Loading stations...</div>
            )}
          </div>
        </div>

        <div className="rounded-2xl border border-border bg-surface p-5">
          <div className="mb-2 font-mono text-[11px] uppercase tracking-wide text-muted">
            Current survey run
          </div>
          <div className="text-sm text-foreground">
            Simulated at {stats?.trap_nights_simulated ?? "—"} trap-nights across {stats?.total_stations ?? "—"} stations.
          </div>
          <p className="mt-2 text-xs text-muted">
            Full batch ingestion run history will appear here once a real field-footage processing
            pipeline is wired in.
          </p>
        </div>

        <button
          onClick={() => navigate("trash")}
          className="flex w-full items-center justify-between gap-4 rounded-2xl border border-border bg-surface p-5 text-left transition-colors hover:border-border-strong hover:bg-surface-sunken"
        >
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-danger-soft text-danger">
              <Trash size={17} />
            </div>
            <div>
              <div className="text-sm font-medium text-foreground">Blank Frame Trash</div>
              <p className="mt-0.5 text-xs text-muted">
                Review frames auto-classified as blank during ingestion, restore misclassified ones, or purge them for good.
              </p>
            </div>
          </div>
          <ArrowRight size={16} className="shrink-0 text-muted" />
        </button>
      </div>
    </div>
  );
}

function StatBlock({
  label,
  value,
  tone,
  hint,
}: {
  label: string;
  value: number | undefined;
  tone?: "caution";
  hint?: string;
}) {
  const isCaution = tone === "caution" && (value ?? 0) > 0;
  return (
    <div
      className={`relative overflow-hidden rounded-xl border p-4 ${
        isCaution ? "border-caution/40 bg-caution-soft" : "border-border bg-surface"
      }`}
    >
      {isCaution && <span aria-hidden className="absolute inset-y-0 left-0 w-0.5 bg-caution" />}
      <div className="font-mono text-[11px] uppercase tracking-wide text-muted">{label}</div>
      <div
        className={`mt-1.5 font-serif text-3xl font-medium tabular-nums tracking-tight ${
          isCaution ? "text-caution" : "text-foreground"
        }`}
      >
        {value ?? "—"}
      </div>
      {hint && <div className="mt-0.5 text-[11px] text-muted">{hint}</div>}
    </div>
  );
}
