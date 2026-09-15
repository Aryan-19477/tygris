"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { motion } from "motion/react";
import {
  Binoculars,
  MapPin,
  WarningCircle,
  CheckCircle,
  Question,
  ArrowsClockwise,
  Radio,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { Card, SectionLabel, Pill, EmptyState } from "@/components/ui";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import { api, type RangerObservation, type TerritoryCheck, type Stats } from "@/lib/api";
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

export function RangerReportsView({ stats }: { stats: Stats | null }) {
  const { t } = useLanguage();
  const [observations, setObservations] = useState<RangerObservation[] | null>(null);
  const [checksByObservation, setChecksByObservation] = useState<Record<string, TerritoryCheck>>({});
  const [runningIds, setRunningIds] = useState<Set<string>>(new Set());
  const [errorIds, setErrorIds] = useState<Set<string>>(new Set());
  const [loadError, setLoadError] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    if (!isSupabaseConfigured) return;
    try {
      const [obsRes, checksRes] = await Promise.all([
        supabase.from("observations").select("*").order("created_at", { ascending: false }).limit(100),
        supabase.from("territory_checks").select("*").order("computed_at", { ascending: false }).limit(200),
      ]);
      if (obsRes.error) throw obsRes.error;
      setObservations((obsRes.data as RangerObservation[]) ?? []);
      setLoadError(null);

      if (!checksRes.error && checksRes.data) {
        const byObs: Record<string, TerritoryCheck> = {};
        for (const row of checksRes.data as TerritoryCheck[]) {
          // Most recent first (already ordered), keep the first one seen per observation.
          if (!byObs[row.observation_id]) byObs[row.observation_id] = row;
        }
        setChecksByObservation(byObs);
      }
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Failed to load field reports.");
    }
  }, []);

  useEffect(() => {
    if (!isSupabaseConfigured) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();

    const channel = supabase
      .channel("ranger-reports-live")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "observations" },
        () => loadData()
      )
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "territory_checks" },
        () => loadData()
      )
      .subscribe();

    return () => {
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

  const sorted = useMemo(() => {
    if (!observations) return null;
    return [...observations].sort(
      (a, b) => new Date(b.timestamp ?? b.created_at ?? 0).getTime() - new Date(a.timestamp ?? a.created_at ?? 0).getTime()
    );
  }, [observations]);

  if (!isSupabaseConfigured) {
    return (
      <div>
        <TopBar title={t("rangerReports.title")} subtitle={t("rangerReports.subtitle")} alertCount={stats?.pending_review ?? 0} />
        <div className="px-8 py-6">
          <EmptyState
            icon={<Binoculars size={22} />}
            title={t("rangerReports.notConfigured")}
            subtitle={t("rangerReports.notConfiguredDesc")}
          />
        </div>
      </div>
    );
  }

  return (
    <div>
      <TopBar
        title={t("rangerReports.title")}
        subtitle={t("rangerReports.subtitle")}
        alertCount={stats?.pending_review ?? 0}
        right={
          <Pill tone="positive" className="flex items-center gap-1.5 border border-positive/30 px-2.5 py-1">
            <Radio size={12} weight="fill" />
            {t("rangerReports.live")}
          </Pill>
        }
      />
      <div className="px-8 py-6 space-y-4">
        {loadError && (
          <div className="rounded-xl border border-danger/30 bg-danger-soft px-4 py-3 text-sm text-danger">
            {loadError}
          </div>
        )}

        {!sorted && !loadError && (
          <div className="text-sm text-muted">{t("rangerReports.loading")}</div>
        )}

        {sorted && sorted.length === 0 && <EmptyState title={t("rangerReports.empty")} />}

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          {sorted?.map((obs, i) => (
            <ObservationCard
              key={obs.observation_id}
              obs={obs}
              check={checksByObservation[obs.observation_id]}
              index={i}
              running={runningIds.has(obs.observation_id)}
              errored={errorIds.has(obs.observation_id)}
              onRunCheck={() => runCheck(obs.observation_id)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

const TONE_TEXT_CLASS: Record<"positive" | "caution" | "neutral", string> = {
  positive: "text-positive",
  caution: "text-caution",
  neutral: "text-muted",
};

function statusTone(status: TerritoryCheck["status"] | undefined, t: (k: string) => string) {
  switch (status) {
    case "confirmed_present":
      return { label: t("rangerReports.statusConfirmed"), tone: "positive" as const, icon: CheckCircle };
    case "possible_move":
      return { label: t("rangerReports.statusPossibleMove"), tone: "caution" as const, icon: WarningCircle };
    case "no_location":
      return { label: t("rangerReports.statusNoLocation"), tone: "neutral" as const, icon: Question };
    case "no_recent_data":
    default:
      return { label: t("rangerReports.statusNoRecentData"), tone: "neutral" as const, icon: Question };
  }
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
  } catch {
    // keep fallback
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.02, 0.3) }}
    >
      <Card padding="lg">
        <div className="flex items-start justify-between gap-3">
          <div>
            <SectionLabel>{t("rangerReports.reportedBy", { rangerId: obs.ranger_id })}</SectionLabel>
            <div className="mt-1 font-serif text-lg font-medium text-foreground">
              {obs.species_category || obs.obs_type}
            </div>
            <div className="mt-0.5 text-xs text-muted">{when}</div>
          </div>
          <Pill tone="neutral" className="px-2.5 py-1">
            {obs.obs_type}
          </Pill>
        </div>

        <div className="mt-3 flex items-center gap-1.5 text-xs text-muted">
          <MapPin size={13} />
          {hasCoords ? `${obs.lat!.toFixed(5)}, ${obs.lon!.toFixed(5)}` : t("rangerReports.noCoordinates")}
        </div>

        {obs.remarks && <p className="mt-2 text-sm text-foreground">{obs.remarks}</p>}

        {wildlife && (
          <div className="mt-4 border-t border-border pt-3">
            {check ? (
              <div>
                <div className="flex items-center gap-2">
                  {ToneIcon && <ToneIcon size={14} weight="fill" className={TONE_TEXT_CLASS[tone!.tone]} />}
                  <Pill tone={tone!.tone} className="px-2.5 py-0.5">
                    {tone!.label}
                  </Pill>
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
                <span className="text-xs text-muted">{t("rangerReports.statusNoRecentData")}</span>
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
      </Card>
    </motion.div>
  );
}
