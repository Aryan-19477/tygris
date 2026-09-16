"use client";

import { useEffect, useMemo, useState } from "react";
import { motion } from "motion/react";
import {
  Camera,
  PawPrint,
  ChartLineUp,
  WarningCircle,
  Trash,
  ArrowRight,
  MagnifyingGlass,
  X,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { useNavigation } from "@/lib/navigation-context";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import { api, type Stats, type GalleryIndividual, type GISStation } from "@/lib/api";
import { StationReportCardView } from "./StationReportCardView";

export function StationHealthView({ stats, onOpenTiger }: { stats: Stats | null; onOpenTiger?: (tigerId: string) => void }) {
  const { navigate } = useNavigation();
  const { t } = useLanguage();
  const [individuals, setIndividuals] = useState<GalleryIndividual[] | null>(null);
  const [stations, setStations] = useState<GISStation[] | null>(null);
  const [selectedStationId, setSelectedStationId] = useState<string | null>(null);
  const [search, setSearch] = useState("");

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
      .sort((a, b) => b.individuals - a.individuals);
  }, [stations, individuals]);

  // Search-filtered list
  const filteredStations = useMemo(() => {
    if (!stationCounts) return null;
    const q = search.trim().toLowerCase();
    if (!q) return stationCounts;
    return stationCounts.filter(
      (s) =>
        s.station.camera_id.toLowerCase().includes(q) ||
        (s.station.zone ?? "").toLowerCase().includes(q) ||
        (s.station.sub_region ?? "").toLowerCase().includes(q) ||
        (s.station.habitat ?? "").toLowerCase().includes(q) ||
        (s.station.grid_id ?? "").toLowerCase().includes(q)
    );
  }, [stationCounts, search]);

  const totalStations = stats?.total_stations ?? stations?.length;
  const operational = stats?.active_stations ?? (stations ? stations.length - offline.length : undefined);
  const uptimePct =
    totalStations && operational !== undefined && totalStations > 0
      ? ((operational / totalStations) * 100).toFixed(1)
      : null;

  const [showAllOffline, setShowAllOffline] = useState(false);
  const visibleOffline = showAllOffline ? offline : offline.slice(0, 20);

  // If a station report card is open, render it
  if (selectedStationId) {
    return (
      <StationReportCardView
        stationId={selectedStationId}
        onBack={() => setSelectedStationId(null)}
        onOpenTiger={onOpenTiger}
      />
    );
  }

  return (
    <div>
      <TopBar
        title={t("stations.title")}
        subtitle={t("stations.subtitle")}
        alertCount={stats?.pending_review ?? 0}
      />
      <div className="px-8 py-6 space-y-6">
        {/* Summary stats */}
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatBlock label={t("stations.totalStations")} value={totalStations} />
          <StatBlock
            label={t("stations.operational")}
            value={operational}
            hint={uptimePct !== null ? t("stations.ofNetwork", { pct: uptimePct! }) : undefined}
          />
          <StatBlock
            label={t("stations.offlineDegraded")}
            value={offline.length}
            tone={offline.length > 0 ? "caution" : undefined}
            hint={offline.length > 0 ? t("stations.needsService") : undefined}
          />
          <StatBlock label={t("stations.trapNights")} value={stats?.trap_nights_simulated} />
        </div>

        {/* Offline warning banner */}
        {offline.length > 0 && (
          <div className="rounded-xl border border-caution/30 bg-caution-soft p-4">
            <div className="mb-2 flex items-center gap-2 text-caution">
              <WarningCircle size={16} weight="fill" />
              <span className="text-sm font-medium">
                {t("stations.stationsNotReporting", { count: offline.length, plural: offline.length > 1 ? "s" : "" })}
              </span>
            </div>
            <div className="flex flex-wrap gap-1.5">
              {visibleOffline.map((s) => (
                <button
                  key={s.camera_id}
                  onClick={() => setSelectedStationId(s.camera_id)}
                  title={`${s.zone} — ${s.sub_region || "Unknown range"}`}
                  className="rounded-full bg-surface px-2.5 py-1 font-mono text-xs text-foreground ring-1 ring-caution/15 transition-colors hover:bg-caution-soft hover:text-caution"
                >
                  {s.camera_id}
                </button>
              ))}
              {offline.length > 20 && (
                <button
                  onClick={() => setShowAllOffline((v) => !v)}
                  className="rounded-full bg-surface px-2.5 py-1 font-mono text-xs text-muted transition-colors hover:text-caution focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-caution"
                >
                  {showAllOffline ? t("stations.showFewer") : t("stations.moreCount", { count: offline.length - 20 })}
                </button>
              )}
            </div>
          </div>
        )}

        {/* Search + station grid */}
        <div>
          <div className="mb-4 flex items-center gap-3">
            <ChartLineUp size={16} className="shrink-0 text-muted" />
            <span className="font-mono text-[11px] uppercase tracking-wide text-muted flex-1">
              {t("stations.mostActive")}
            </span>
            {/* Search bar */}
            <div className="relative flex items-center">
              <MagnifyingGlass size={14} className="pointer-events-none absolute left-2.5 text-muted" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search station, zone, range…"
                className="h-8 w-56 rounded-full border border-border bg-surface pl-8 pr-8 font-mono text-xs text-foreground placeholder:text-muted focus:border-accent focus:outline-none"
              />
              {search && (
                <button
                  onClick={() => setSearch("")}
                  className="absolute right-2.5 text-muted hover:text-foreground"
                >
                  <X size={12} />
                </button>
              )}
            </div>
          </div>

          {filteredStations ? (
            filteredStations.length === 0 ? (
              <div className="py-12 text-center text-sm text-muted">
                No stations match <span className="font-mono text-foreground">&ldquo;{search}&rdquo;</span>
              </div>
            ) : (
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                {filteredStations.map((s, i) => (
                  <motion.button
                    key={s.station.camera_id}
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.35, delay: Math.min(i, 15) * 0.03 }}
                    onClick={() => setSelectedStationId(s.station.camera_id)}
                    className="rounded-2xl border border-border bg-surface p-5 text-left transition-all hover:border-border-strong hover:shadow-sm"
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
                        {s.station.operational_status === "OPERATIONAL" ? t("common.online") : t("common.offline")}
                      </span>
                    </div>
                    <div className="mt-3 font-mono text-base font-semibold text-foreground">{s.station.camera_id}</div>
                    <div className="mt-1 text-xs text-muted">
                      {s.station.zone} — {s.station.sub_region || t("common.unknownRange")}
                    </div>
                    <div className="mt-2 flex items-center justify-between">
                      <div className="flex items-center gap-1.5 text-sm text-muted">
                        <PawPrint size={13} />
                        {t("stations.individualsSeen", { count: s.individuals })}
                      </div>
                      <ArrowRight size={13} className="text-muted opacity-0 transition-opacity group-hover:opacity-100" />
                    </div>
                  </motion.button>
                ))}
              </div>
            )
          ) : (
            <div className="col-span-full text-sm text-muted">{t("stations.loadingStations")}</div>
          )}
        </div>

        {/* Survey run note */}
        <div className="rounded-2xl border border-border bg-surface p-5">
          <div className="mb-2 font-mono text-[11px] uppercase tracking-wide text-muted">
            {t("stations.currentSurveyRun")}
          </div>
          <div className="text-sm text-foreground">
            {t("stations.surveySimulated", {
              nights: stats?.trap_nights_simulated ?? "—",
              stations: stats?.total_stations ?? "—",
            })}
          </div>
          <p className="mt-2 text-xs text-muted">{t("stations.surveyNote")}</p>
        </div>

        {/* Blank frame trash shortcut */}
        <button
          onClick={() => navigate("trash")}
          className="flex w-full items-center justify-between gap-4 rounded-2xl border border-border bg-surface p-5 text-left transition-colors hover:border-border-strong hover:bg-surface-sunken"
        >
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
