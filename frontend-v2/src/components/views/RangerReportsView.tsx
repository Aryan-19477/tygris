"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  Binoculars,
  MapPin,
  WarningCircle,
  CheckCircle,
  Question,
  ArrowsClockwise,
  Radio,
  Footprints,
  Car,
  Compass,
  Clock,
  ShieldCheck,
  Check,
  CaretDown,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import { api, type RangerObservation, type TerritoryCheck, type RangerPatrol, type Stats } from "@/lib/api";
import { supabase, isSupabaseConfigured } from "@/lib/supabaseClient";

const WILDLIFE_OBS_TYPES = new Set([
  "wildlifeSighting",
  "wildlifeSign",
  "wildlife_sighting",
  "wildlife_sign",
]);

function isWildlifeObservation(obsType: string): boolean {
  return WILDLIFE_OBS_TYPES.has(obsType);
}

type TabKey = "all" | "observations" | "patrols";

type ReportItem =
  | { kind: "observation"; data: RangerObservation; timestamp: number }
  | { kind: "patrol"; data: RangerPatrol; timestamp: number };

export function RangerReportsView({ stats }: { stats: Stats | null }) {
  const { t } = useLanguage();
  const [observations, setObservations] = useState<RangerObservation[] | null>(null);
  const [patrols, setPatrols] = useState<RangerPatrol[] | null>(null);
  const [checksByObservation, setChecksByObservation] = useState<Record<string, TerritoryCheck>>({});
  const [runningIds, setRunningIds] = useState<Set<string>>(new Set());
  const [errorIds, setErrorIds] = useState<Set<string>>(new Set());
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [activeTab, setActiveTab] = useState<TabKey>("all");

  const loadData = useCallback(async () => {
    if (!isSupabaseConfigured) return;
    setIsRefreshing(true);
    try {
      const [obsRes, checksRes, patrolsRes] = await Promise.allSettled([
        supabase.from("observations").select("*").order("created_at", { ascending: false }).limit(100),
        supabase.from("territory_checks").select("*").order("computed_at", { ascending: false }).limit(200),
        supabase.from("patrols").select("*").order("created_at", { ascending: false }).limit(100),
      ]);

      if (obsRes.status === "fulfilled" && !obsRes.value.error && obsRes.value.data) {
        setObservations(obsRes.value.data as RangerObservation[]);
      }

      if (patrolsRes.status === "fulfilled" && !patrolsRes.value.error && patrolsRes.value.data) {
        setPatrols(patrolsRes.value.data as RangerPatrol[]);
      }

      if (checksRes.status === "fulfilled" && !checksRes.value.error && checksRes.value.data) {
        const byObs: Record<string, TerritoryCheck> = {};
        for (const row of checksRes.value.data as TerritoryCheck[]) {
          if (!byObs[row.observation_id]) byObs[row.observation_id] = row;
        }
        setChecksByObservation(byObs);
      }
      setLoadError(null);
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Failed to load field reports.");
    } finally {
      setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    if (!isSupabaseConfigured) return;
    loadData();

    // 2-second polling interval ensures near-instant real-time updates
    const pollInterval = setInterval(() => {
      loadData();
    }, 2000);

    const channel = supabase
      .channel("ranger-reports-live")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "observations" },
        () => loadData()
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "territory_checks" },
        () => loadData()
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "patrols" },
        () => loadData()
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "camera_inspections" },
        () => loadData()
      )
      .subscribe();

    return () => {
      clearInterval(pollInterval);
      supabase.removeChannel(channel);
    };
  }, [loadData]);

  const runCheck = useCallback(
    async (observationId: string) => {
      setRunningIds((prev) => new Set(prev).add(observationId));
      setErrorIds((prev) => {
        const next = new Set(prev);
        next.delete(observationId);
        return next;
      });
      try {
        await api.runTerritoryCheck(observationId);
        await loadData();
      } catch {
        setErrorIds((prev) => new Set(prev).add(observationId));
      } finally {
        setRunningIds((prev) => {
          const next = new Set(prev);
          next.delete(observationId);
          return next;
        });
      }
    },
    [loadData]
  );

  const combinedItems = useMemo<ReportItem[] | null>(() => {
    if (observations === null && patrols === null) return null;
    const items: ReportItem[] = [];

    if (observations) {
      for (const obs of observations) {
        const time = new Date(obs.timestamp ?? obs.created_at ?? 0).getTime();
        items.push({ kind: "observation", data: obs, timestamp: isNaN(time) ? 0 : time });
      }
    }

    if (patrols) {
      for (const p of patrols) {
        const time = new Date(p.start_time ?? p.created_at ?? 0).getTime();
        items.push({ kind: "patrol", data: p, timestamp: isNaN(time) ? 0 : time });
      }
    }

    items.sort((a, b) => b.timestamp - a.timestamp);
    return items;
  }, [observations, patrols]);

  const filteredItems = useMemo(() => {
    if (!combinedItems) return null;
    if (activeTab === "observations") {
      return combinedItems.filter((i) => i.kind === "observation");
    }
    if (activeTab === "patrols") {
      return combinedItems.filter((i) => i.kind === "patrol");
    }
    return combinedItems;
  }, [combinedItems, activeTab]);

  const observationsByPatrol = useMemo(() => {
    const map: Record<string, RangerObservation[]> = {};
    if (observations) {
      for (const obs of observations) {
        if (obs.patrol_id) {
          if (!map[obs.patrol_id]) map[obs.patrol_id] = [];
          map[obs.patrol_id].push(obs);
        }
      }
    }
    return map;
  }, [observations]);

  if (!isSupabaseConfigured) {
    return (
      <div>
        <TopBar title={t("rangerReports.title")} subtitle={t("rangerReports.subtitle")} alertCount={stats?.pending_review ?? 0} />
        <div className="px-8 py-6">
          <div className="flex flex-col items-center gap-3 rounded-2xl border border-border bg-surface px-6 py-16 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-sunken text-muted">
              <Binoculars size={22} />
            </div>
            <div className="text-sm font-medium text-foreground">{t("rangerReports.notConfigured")}</div>
            <p className="max-w-md text-xs text-muted">{t("rangerReports.notConfiguredDesc")}</p>
          </div>
        </div>
      </div>
    );
  }

  const obsCount = observations?.length ?? 0;
  const patrolCount = patrols?.length ?? 0;
  const totalCount = obsCount + patrolCount;

  return (
    <div>
      <TopBar
        title={t("rangerReports.title")}
        subtitle={t("rangerReports.subtitle")}
        alertCount={stats?.pending_review ?? 0}
        right={
          <div className="flex items-center gap-2">
            <button
              onClick={() => loadData()}
              disabled={isRefreshing}
              className="flex items-center gap-1.5 rounded-full border border-border bg-surface px-3 py-1 text-xs font-medium text-muted transition-colors hover:text-foreground hover:bg-surface-sunken disabled:opacity-50"
            >
              <ArrowsClockwise size={13} className={isRefreshing ? "animate-spin text-accent" : ""} />
              {t("rangerReports.refresh")}
            </button>
            <span className="flex items-center gap-1.5 rounded-full border border-positive/30 bg-positive-soft px-2.5 py-1 font-mono text-[10px] font-medium uppercase tracking-wide text-positive">
              <Radio size={12} weight="fill" className="animate-pulse" />
              {t("rangerReports.live")}
            </span>
          </div>
        }
      />
      <div className="px-8 py-6 space-y-5">
        {loadError && (
          <div className="rounded-xl border border-danger/30 bg-danger-soft px-4 py-3 text-sm text-danger">
            {loadError}
          </div>
        )}

        {/* Filter Tabs */}
        <div className="flex items-center gap-2 border-b border-border pb-3">
          <button
            onClick={() => setActiveTab("all")}
            className={`flex items-center gap-2 rounded-xl px-3.5 py-2 text-xs font-semibold transition-colors ${
              activeTab === "all"
                ? "bg-foreground text-background"
                : "bg-surface text-muted hover:text-foreground hover:bg-surface-sunken border border-border"
            }`}
          >
            <span>{t("rangerReports.tabAll")}</span>
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-mono ${
                activeTab === "all" ? "bg-background/20 text-background" : "bg-surface-sunken text-muted"
              }`}
            >
              {totalCount}
            </span>
          </button>

          <button
            onClick={() => setActiveTab("observations")}
            className={`flex items-center gap-2 rounded-xl px-3.5 py-2 text-xs font-semibold transition-colors ${
              activeTab === "observations"
                ? "bg-foreground text-background"
                : "bg-surface text-muted hover:text-foreground hover:bg-surface-sunken border border-border"
            }`}
          >
            <span>{t("rangerReports.tabObservations")}</span>
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-mono ${
                activeTab === "observations" ? "bg-background/20 text-background" : "bg-surface-sunken text-muted"
              }`}
            >
              {obsCount}
            </span>
          </button>

          <button
            onClick={() => setActiveTab("patrols")}
            className={`flex items-center gap-2 rounded-xl px-3.5 py-2 text-xs font-semibold transition-colors ${
              activeTab === "patrols"
                ? "bg-foreground text-background"
                : "bg-surface text-muted hover:text-foreground hover:bg-surface-sunken border border-border"
            }`}
          >
            <span>{t("rangerReports.tabPatrols")}</span>
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-mono ${
                activeTab === "patrols" ? "bg-background/20 text-background" : "bg-surface-sunken text-muted"
              }`}
            >
              {patrolCount}
            </span>
          </button>
        </div>

        {!filteredItems && !loadError && (
          <div className="text-sm text-muted">{t("rangerReports.loading")}</div>
        )}

        {filteredItems && filteredItems.length === 0 && (
          <div className="rounded-2xl border border-border bg-surface px-6 py-16 text-center text-sm text-muted">
            {t("rangerReports.empty")}
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          {filteredItems?.map((item, i) =>
            item.kind === "observation" ? (
              <ObservationCard
                key={item.data.observation_id}
                obs={item.data}
                check={checksByObservation[item.data.observation_id]}
                index={i}
                running={runningIds.has(item.data.observation_id)}
                errored={errorIds.has(item.data.observation_id)}
                onRunCheck={() => runCheck(item.data.observation_id)}
              />
            ) : (
              <PatrolCard
                key={item.data.patrol_id}
                patrol={item.data}
                observations={observationsByPatrol[item.data.patrol_id] || []}
                checksByObservation={checksByObservation}
                runningIds={runningIds}
                errorIds={errorIds}
                onRunCheck={runCheck}
                index={i}
              />
            )
          )}
        </div>
      </div>
    </div>
  );
}

function statusTone(status: TerritoryCheck["status"] | undefined, t: (k: string) => string) {
  switch (status) {
    case "confirmed_present":
      return { label: t("rangerReports.statusConfirmed"), className: "bg-positive-soft text-positive", icon: CheckCircle };
    case "possible_move":
      return { label: t("rangerReports.statusPossibleMove"), className: "bg-caution-soft text-caution", icon: WarningCircle };
    case "no_location":
      return { label: t("rangerReports.statusNoLocation"), className: "bg-surface-sunken text-muted", icon: Question };
    case "no_recent_data":
    default:
      return { label: t("rangerReports.statusNoRecentData"), className: "bg-surface-sunken text-muted", icon: Question };
  }
}

function formatDuration(seconds: number | null | undefined): string {
  if (!seconds || seconds <= 0) return "—";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function PatrolCard({
  patrol,
  observations = [],
  checksByObservation = {},
  runningIds = new Set(),
  errorIds = new Set(),
  onRunCheck = () => {},
  index,
}: {
  patrol: RangerPatrol;
  observations?: RangerObservation[];
  checksByObservation?: Record<string, TerritoryCheck>;
  runningIds?: Set<string>;
  errorIds?: Set<string>;
  onRunCheck?: (obsId: string) => void;
  index: number;
}) {
  const { t } = useLanguage();
  const [isExpanded, setIsExpanded] = useState(false);
  const isVehicle = patrol.patrol_type?.toLowerCase() === "vehicle";
  const isCompleted = patrol.status?.toLowerCase() === "completed";
  const obsCount = observations.length;

  let when = t("common.unknownTime");
  try {
    if (patrol.start_time) when = new Date(patrol.start_time).toLocaleString();
    else if (patrol.created_at) when = new Date(patrol.created_at).toLocaleString();
  } catch {
    // keep fallback
  }

  const hasStart = patrol.start_lat !== null && patrol.start_lon !== null && patrol.start_lat !== undefined && patrol.start_lon !== undefined;
  const hasEnd = patrol.end_lat !== null && patrol.end_lon !== null && patrol.end_lat !== undefined && patrol.end_lon !== undefined;

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.02, 0.3) }}
      className="rounded-2xl border border-border bg-surface p-5 hover:border-accent/40 transition-all shadow-sm flex flex-col justify-between"
    >
      <div>
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-accent border border-accent/20">
              {isVehicle ? <Car size={20} weight="duotone" /> : <Footprints size={20} weight="duotone" />}
            </div>
            <div>
              <div className="font-mono text-[11px] uppercase tracking-wide text-muted">
                {t("rangerReports.reportedBy", { rangerId: patrol.ranger_id })}
              </div>
              <div className="mt-0.5 font-serif text-lg font-medium text-foreground capitalize">
                {patrol.patrol_type || "Foot"} {t("rangerReports.patrolLabel")}
              </div>
              <div className="mt-0.5 text-xs text-muted flex items-center gap-1.5">
                <Clock size={12} />
                {when}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {/* Quick Observations Count Pill */}
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                setIsExpanded((prev) => !prev);
              }}
              className={`flex items-center gap-1.5 rounded-full px-2.5 py-1 font-mono text-[10px] font-semibold transition-all cursor-pointer ${
                obsCount > 0
                  ? isExpanded
                    ? "bg-accent text-white shadow-xs"
                    : "bg-accent-soft text-accent border border-accent/30 hover:bg-accent-soft/80"
                  : "bg-surface-sunken text-muted border border-border hover:text-foreground"
              }`}
            >
              <Binoculars size={12} weight={obsCount > 0 ? "duotone" : "regular"} />
              <span>{obsCount} Obs</span>
              <CaretDown
                size={11}
                className={`transition-transform duration-200 ${isExpanded ? "rotate-180" : ""}`}
              />
            </button>

            <span
              className={`rounded-full px-2.5 py-1 font-mono text-[10px] font-semibold uppercase tracking-wider flex items-center gap-1 ${
                isCompleted
                  ? "border border-positive/30 bg-positive-soft text-positive"
                  : "border border-caution/30 bg-caution-soft text-caution"
              }`}
            >
              {isCompleted && <Check size={10} weight="bold" />}
              {patrol.status || "Active"}
            </span>
          </div>
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2 rounded-xl bg-surface-sunken p-3">
          <div>
            <div className="text-[10px] font-mono uppercase text-muted tracking-wide">{t("rangerReports.distance")}</div>
            <div className="text-sm font-semibold text-foreground font-mono">
              {patrol.distance_km != null ? `${patrol.distance_km.toFixed(2)} km` : "0.00 km"}
            </div>
          </div>
          <div>
            <div className="text-[10px] font-mono uppercase text-muted tracking-wide">{t("rangerReports.duration")}</div>
            <div className="text-sm font-semibold text-foreground font-mono">
              {formatDuration(patrol.duration_seconds)}
            </div>
          </div>
        </div>

        {(hasStart || hasEnd) && (
          <div className="mt-3 flex flex-wrap items-center gap-3 text-xs text-muted">
            {hasStart && (
              <div className="flex items-center gap-1">
                <MapPin size={13} className="text-accent" />
                <span className="font-mono text-[11px]">
                  {t("rangerReports.startCoords")}: {patrol.start_lat!.toFixed(4)}, {patrol.start_lon!.toFixed(4)}
                </span>
              </div>
            )}
            {hasEnd && (
              <div className="flex items-center gap-1">
                <Compass size={13} className="text-muted" />
                <span className="font-mono text-[11px]">
                  {t("rangerReports.endCoords")}: {patrol.end_lat!.toFixed(4)}, {patrol.end_lon!.toFixed(4)}
                </span>
              </div>
            )}
          </div>
        )}

        {patrol.notes && (
          <p className="mt-3 text-sm text-foreground bg-surface-raised p-2.5 rounded-lg border border-border">
            {patrol.notes}
          </p>
        )}
      </div>

      {/* Expandable Observations Section */}
      <div className="mt-4 border-t border-border pt-3">
        <button
          type="button"
          onClick={() => setIsExpanded((prev) => !prev)}
          className="w-full flex items-center justify-between py-2 px-3 rounded-xl bg-surface-sunken hover:bg-surface-raised transition-colors text-xs font-medium text-foreground cursor-pointer group"
        >
          <div className="flex items-center gap-2">
            <Binoculars size={14} className="text-accent" />
            <span className="font-medium">
              {obsCount > 0
                ? `${obsCount} observation${obsCount > 1 ? "s" : ""} logged in this patrol`
                : t("rangerReports.noPatrolObservations")}
            </span>
          </div>
          <div className="flex items-center gap-1 text-muted group-hover:text-foreground">
            <span className="text-[11px]">
              {isExpanded ? t("rangerReports.hideObservations") : t("rangerReports.viewObservations")}
            </span>
            <CaretDown
              size={13}
              className={`transition-transform duration-200 ${isExpanded ? "rotate-180" : ""}`}
            />
          </div>
        </button>

        <AnimatePresence>
          {isExpanded && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              transition={{ duration: 0.22 }}
              className="overflow-hidden mt-3 space-y-2.5"
            >
              {obsCount === 0 ? (
                <div className="p-4 text-center text-xs text-muted rounded-xl bg-surface-sunken/70 border border-dashed border-border">
                  {t("rangerReports.noPatrolObservations")}
                </div>
              ) : (
                observations.map((obs) => {
                  const check = checksByObservation[obs.observation_id];
                  const tone = check ? statusTone(check.status, t) : null;
                  const ToneIcon = tone?.icon;
                  const hasCoords = obs.lat !== null && obs.lon !== null;
                  const wildlife = isWildlifeObservation(obs.obs_type);
                  const isRunning = runningIds.has(obs.observation_id);
                  const isErrored = errorIds.has(obs.observation_id);

                  let obsTime = "";
                  try {
                    if (obs.timestamp) obsTime = new Date(obs.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
                    else if (obs.created_at) obsTime = new Date(obs.created_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
                  } catch {}

                  return (
                    <div
                      key={obs.observation_id}
                      className="p-3.5 rounded-xl border border-border bg-surface-raised space-y-2 text-xs shadow-xs"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <div className="font-serif text-sm font-semibold text-foreground">
                            {obs.species_category || obs.obs_type}
                          </div>
                          <div className="mt-0.5 text-[11px] text-muted flex items-center gap-1">
                            <Clock size={11} />
                            <span>{obsTime}</span>
                            {hasCoords && (
                              <>
                                <span className="text-muted/40">•</span>
                                <span className="font-mono text-[10px]">
                                  {obs.lat!.toFixed(4)}, {obs.lon!.toFixed(4)}
                                </span>
                              </>
                            )}
                          </div>
                        </div>

                        <span className="rounded-full bg-surface-sunken border border-border px-2 py-0.5 font-mono text-[9px] uppercase tracking-wider text-muted">
                          {obs.obs_type}
                        </span>
                      </div>

                      {obs.remarks && (
                        <p className="text-xs text-foreground/90 bg-surface-sunken/60 p-2 rounded-lg border border-border/50">
                          {obs.remarks}
                        </p>
                      )}

                      {wildlife && (
                        <div className="pt-1.5 flex items-center justify-between gap-2 border-t border-border/50">
                          {check ? (
                            <div className="flex items-center gap-1.5">
                              {ToneIcon && <ToneIcon size={12} weight="fill" className={tone!.className.split(" ")[1]} />}
                              <span className={`rounded-full px-2 py-0.5 font-mono text-[9px] font-semibold ${tone!.className}`}>
                                {tone!.label}
                              </span>
                              {check.resident_tiger_id && (
                                <span className="text-[10px] text-muted font-mono">
                                  {check.resident_tiger_id}
                                </span>
                              )}
                            </div>
                          ) : hasCoords ? (
                            <div className="flex items-center justify-between w-full">
                              <span className="text-[11px] text-muted">{t("rangerReports.checkPending")}</span>
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onRunCheck(obs.observation_id);
                                }}
                                disabled={isRunning}
                                className="flex items-center gap-1 rounded-full border border-accent/30 bg-accent-soft px-2.5 py-1 text-[10px] font-medium text-accent hover:bg-accent-soft/70 disabled:opacity-60"
                              >
                                <ArrowsClockwise size={11} className={isRunning ? "animate-spin" : ""} />
                                {isRunning ? t("rangerReports.running") : t("rangerReports.runCheck")}
                              </button>
                            </div>
                          ) : null}
                          {isErrored && (
                            <p className="text-[10px] text-danger">{t("rangerReports.checkFailed")}</p>
                          )}
                        </div>
                      )}
                    </div>
                  );
                })
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}

function ObservationCard({
  obs,
  check,
  index,
  running,
  errored,
  onRunCheck,
}: {
  obs: RangerObservation;
  check: TerritoryCheck | undefined;
  index: number;
  running: boolean;
  errored: boolean;
  onRunCheck: () => void;
}) {
  const { t } = useLanguage();
  const wildlife = isWildlifeObservation(obs.obs_type);
  const hasCoords = obs.lat !== null && obs.lon !== null;
  const tone = check ? statusTone(check.status, t) : null;
  const ToneIcon = tone?.icon;

  let when = t("common.unknownTime");
  try {
    if (obs.timestamp) when = new Date(obs.timestamp).toLocaleString();
    else if (obs.created_at) when = new Date(obs.created_at).toLocaleString();
  } catch {
    // keep fallback
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.02, 0.3) }}
      className="rounded-2xl border border-border bg-surface p-5 hover:border-accent/30 transition-all shadow-sm"
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="font-mono text-[11px] uppercase tracking-wide text-muted">
            {t("rangerReports.reportedBy", { rangerId: obs.ranger_id })}
          </div>
          <div className="mt-1 font-serif text-lg font-medium text-foreground">
            {obs.species_category || obs.obs_type}
          </div>
          <div className="mt-0.5 text-xs text-muted flex items-center gap-1.5">
            <Clock size={12} />
            {when}
          </div>
        </div>
        <span className="rounded-full bg-surface-sunken px-2.5 py-1 font-mono text-[10px] font-semibold text-muted">
          {obs.obs_type}
        </span>
      </div>

      <div className="mt-3 flex items-center gap-1.5 text-xs text-muted">
        <MapPin size={13} className="text-accent" />
        {hasCoords ? `${obs.lat!.toFixed(5)}, ${obs.lon!.toFixed(5)}` : t("rangerReports.noCoordinates")}
      </div>

      {obs.remarks && <p className="mt-2 text-sm text-foreground">{obs.remarks}</p>}

      {wildlife && (
        <div className="mt-4 border-t border-border pt-3">
          {check ? (
            <div>
              <div className="flex items-center gap-2">
                {ToneIcon && <ToneIcon size={14} weight="fill" className={tone!.className.split(" ")[1]} />}
                <span className={`rounded-full px-2.5 py-0.5 font-mono text-[10px] font-semibold ${tone!.className}`}>
                  {tone!.label}
                </span>
                {check.resident_tiger_id && (
                  <span className="text-[11px] text-muted">
                    {t("rangerReports.residentTiger", { tigerId: check.resident_tiger_id })}
                  </span>
                )}
              </div>
              <p className="mt-2 text-sm text-foreground">{check.summary}</p>
            </div>
          ) : hasCoords ? (
            <div className="flex items-center justify-between gap-3">
              <span className="text-xs text-muted">{t("rangerReports.checkPending")}</span>
              <button
                onClick={onRunCheck}
                disabled={running}
                className="flex items-center gap-1.5 rounded-full border border-accent/30 bg-accent-soft px-3 py-1.5 text-xs font-medium text-accent transition-colors hover:bg-accent-soft/70 disabled:opacity-60"
              >
                <ArrowsClockwise size={13} className={running ? "animate-spin" : ""} />
                {running ? t("rangerReports.running") : t("rangerReports.runCheck")}
              </button>
            </div>
          ) : (
            <span className="text-xs text-muted">{t("rangerReports.noCoordinates")}</span>
          )}
          {errored && <p className="mt-1.5 text-xs text-danger">{t("rangerReports.checkFailed")}</p>}
        </div>
      )}
    </motion.div>
  );
}
