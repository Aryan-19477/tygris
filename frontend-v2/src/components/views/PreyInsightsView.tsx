"use client";

import { useEffect, useState, useMemo } from "react";
import {
  ChartBar,
  MapPin,
  Clock,
  Drop,
  Warning,
  ArrowsClockwise,
  Binoculars,
  Sparkle,
  TrendUp,
  ShieldCheck,
  Tree
} from "@phosphor-icons/react";
import { api, type PreyInsightsResponse } from "@/lib/api";

export function PreyInsightsView() {
  const [data, setData] = useState<PreyInsightsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"rai" | "spatial" | "diel" | "waterhole" | "anomalies">("rai");

  const loadInsights = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await api.prey.getInsights();
      setData(res);
    } catch (err: any) {
      setError(err?.message || "Failed to load ecological insights.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadInsights();
  }, []);

  if (loading && !data) {
    return (
      <div className="flex h-full min-h-[500px] items-center justify-center p-6 text-foreground">
        <div className="flex flex-col items-center gap-3">
          <ArrowsClockwise size={32} className="animate-spin text-primary" />
          <p className="text-sm text-muted">Calculating dynamic Pench ecological intelligence...</p>
        </div>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="p-6 text-foreground">
        <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-6 text-center">
          <p className="text-sm font-semibold text-red-400">{error || "No data available."}</p>
          <button
            onClick={loadInsights}
            className="mt-3 inline-flex items-center gap-2 rounded-xl bg-surface px-4 py-2 text-xs font-semibold text-foreground hover:bg-surface-hover"
          >
            <ArrowsClockwise size={14} /> Retry
          </button>
        </div>
      </div>
    );
  }

  const { summary, relative_abundance, spatial_association, temporal_association, waterhole_intelligence, behaviour_and_anomalies } = data;

  return (
    <div className="min-h-full bg-background p-6 space-y-6 text-foreground">
      {/* Header */}
      <div className="flex flex-col gap-2 border-b border-border/40 pb-5 md:flex-row md:items-center md:justify-between">
        <div>
          <div className="inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary border border-primary/20">
            <Sparkle size={14} />
            Pench Ecological Intelligence Engine
          </div>
          <h1 className="mt-2 text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
            Prey Insights & Tiger–Prey Intelligence
          </h1>
          <p className="text-sm text-muted">
            Real-time population dynamics, Relative Abundance Index (RAI), tiger-prey co-occurrence, and waterhole telemetry.
          </p>
        </div>

        <button
          onClick={loadInsights}
          className="inline-flex items-center gap-2 rounded-xl border border-border bg-surface px-3 py-2 text-xs font-semibold text-foreground hover:bg-surface-hover shadow-sm transition-all"
        >
          <ArrowsClockwise size={14} className={loading ? "animate-spin" : ""} />
          Refresh Metrics
        </button>
      </div>

      {/* Headline KPI Cards */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
        <div className="rounded-2xl border border-border/50 bg-surface p-4">
          <span className="text-[11px] font-semibold uppercase tracking-wider text-muted">Prey Observations</span>
          <p className="mt-1 text-2xl font-bold text-foreground">{summary.total_observations.toLocaleString()}</p>
          <span className="text-[10px] text-emerald-400 font-medium">Recorded in DB</span>
        </div>

        <div className="rounded-2xl border border-border/50 bg-surface p-4">
          <span className="text-[11px] font-semibold uppercase tracking-wider text-muted">Total Animals</span>
          <p className="mt-1 text-2xl font-bold text-foreground">{summary.total_individuals.toLocaleString()}</p>
          <span className="text-[10px] text-muted">Counted in frames</span>
        </div>

        <div className="rounded-2xl border border-border/50 bg-surface p-4">
          <span className="text-[11px] font-semibold uppercase tracking-wider text-muted">Species Richness</span>
          <p className="mt-1 text-2xl font-bold text-foreground">{summary.species_richness}</p>
          <span className="text-[10px] text-muted">Taxa confirmed</span>
        </div>

        <div className="rounded-2xl border border-border/50 bg-surface p-4">
          <span className="text-[11px] font-semibold uppercase tracking-wider text-muted">Active Stations</span>
          <p className="mt-1 text-2xl font-bold text-foreground">{summary.active_stations}</p>
          <span className="text-[10px] text-muted">Camera traps</span>
        </div>

        <div className="rounded-2xl border border-border/50 bg-surface p-4">
          <span className="text-[11px] font-semibold uppercase tracking-wider text-muted">Auto Accept Rate</span>
          <p className="mt-1 text-2xl font-bold text-emerald-400">{summary.auto_acceptance_rate}%</p>
          <span className="text-[10px] text-muted">≥85% confidence</span>
        </div>

        <div className="rounded-2xl border border-border/50 bg-surface p-4">
          <span className="text-[11px] font-semibold uppercase tracking-wider text-muted">Dominant Prey</span>
          <p className="mt-1 text-xl font-bold text-foreground truncate">{summary.dominant_prey}</p>
          <span className="text-[10px] text-muted">Highest biomass</span>
        </div>
      </div>

      {/* Tabs Navigation */}
      <div className="flex flex-wrap items-center gap-2 border-b border-border/40 pb-2">
        <button
          onClick={() => setActiveTab("rai")}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-semibold transition-all ${
            activeTab === "rai"
              ? "bg-primary text-primary-foreground shadow-sm"
              : "bg-surface text-muted hover:bg-surface-hover hover:text-foreground"
          }`}
        >
          <ChartBar size={16} />
          Prey Availability & RAI (Insight 1)
        </button>

        <button
          onClick={() => setActiveTab("spatial")}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-semibold transition-all ${
            activeTab === "spatial"
              ? "bg-primary text-primary-foreground shadow-sm"
              : "bg-surface text-muted hover:bg-surface-hover hover:text-foreground"
          }`}
        >
          <MapPin size={16} />
          Tiger–Prey Spatial Overlap (Insight 2)
        </button>

        <button
          onClick={() => setActiveTab("diel")}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-semibold transition-all ${
            activeTab === "diel"
              ? "bg-primary text-primary-foreground shadow-sm"
              : "bg-surface text-muted hover:bg-surface-hover hover:text-foreground"
          }`}
        >
          <Clock size={16} />
          Diel Activity Patterns (Insight 3)
        </button>

        <button
          onClick={() => setActiveTab("waterhole")}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-semibold transition-all ${
            activeTab === "waterhole"
              ? "bg-primary text-primary-foreground shadow-sm"
              : "bg-surface text-muted hover:bg-surface-hover hover:text-foreground"
          }`}
        >
          <Drop size={16} />
          Waterhole Intelligence (Insight 7)
        </button>

        <button
          onClick={() => setActiveTab("anomalies")}
          className={`inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-semibold transition-all ${
            activeTab === "anomalies"
              ? "bg-primary text-primary-foreground shadow-sm"
              : "bg-surface text-muted hover:bg-surface-hover hover:text-foreground"
          }`}
        >
          <Warning size={16} />
          Ecological Anomalies (Insight 8)
        </button>
      </div>

      {/* Tab 1: Relative Abundance Index */}
      {activeTab === "rai" && (
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
          <div className="rounded-2xl border border-border/50 bg-surface p-5 space-y-4 lg:col-span-6">
            <h3 className="text-base font-bold text-foreground">Relative Abundance Index (RAI) by Species</h3>
            <p className="text-xs text-muted">
              Estimated detections per 100 camera-trap days across all Pench monitoring sectors.
            </p>

            <div className="space-y-4 pt-2">
              {relative_abundance.species_abundance.map((sp, idx) => {
                const maxRai = Math.max(...relative_abundance.species_abundance.map((s) => s.rai), 1);
                const pct = Math.round((sp.rai / maxRai) * 100);
                return (
                  <div key={idx} className="space-y-1.5">
                    <div className="flex justify-between text-xs">
                      <span className="font-semibold text-foreground">{sp.label}</span>
                      <div className="flex items-center gap-3 font-mono text-xs">
                        <span className="text-muted">{sp.total_animals} animals</span>
                        <span className="font-bold text-primary">RAI: {sp.rai}</span>
                      </div>
                    </div>
                    <div className="h-2.5 w-full rounded-full bg-background overflow-hidden">
                      <div
                        className="h-full rounded-full bg-primary transition-all duration-500"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          <div className="rounded-2xl border border-border/50 bg-surface p-5 space-y-4 lg:col-span-6">
            <h3 className="text-base font-bold text-foreground">Top Camera Stations by Prey Activity</h3>
            <p className="text-xs text-muted">Highest density stations in Pench Tiger Reserve.</p>

            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead>
                  <tr className="border-b border-border/40 text-muted">
                    <th className="pb-2 font-medium">Station</th>
                    <th className="pb-2 font-medium">Habitat</th>
                    <th className="pb-2 font-medium">Zone</th>
                    <th className="pb-2 font-medium text-right">Prey Count</th>
                    <th className="pb-2 font-medium text-right">Station RAI</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border/20">
                  {relative_abundance.top_stations_rai.slice(0, 8).map((st, idx) => (
                    <tr key={idx} className="hover:bg-surface-hover/50 transition-colors">
                      <td className="py-2.5 font-semibold text-foreground font-mono">{st.camera_id}</td>
                      <td className="py-2.5 text-muted capitalize">{st.habitat || "Mixed Deciduous"}</td>
                      <td className="py-2.5">
                        <span className="rounded bg-primary/10 px-2 py-0.5 text-[10px] font-semibold text-primary">
                          {st.zone || "CORE"}
                        </span>
                      </td>
                      <td className="py-2.5 text-right font-mono text-foreground font-semibold">{st.total_animals}</td>
                      <td className="py-2.5 text-right font-mono font-bold text-primary">{st.station_rai}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Tiger–Prey Spatial Overlap */}
      {activeTab === "spatial" && (
        <div className="rounded-2xl border border-border/50 bg-surface p-5 space-y-4">
          <div>
            <h3 className="text-base font-bold text-foreground">Tiger–Prey Spatial Co-occurrence Hotspots</h3>
            <p className="text-xs text-muted">
              Correlating tiger sightings with prey presence across the 295 Pench camera stations to identify foraging hotspots.
            </p>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead>
                <tr className="border-b border-border/40 text-muted">
                  <th className="pb-3 font-medium">Camera Station</th>
                  <th className="pb-3 font-medium">Zone</th>
                  <th className="pb-3 font-medium">Habitat</th>
                  <th className="pb-3 font-medium text-center">Tiger Sightings</th>
                  <th className="pb-3 font-medium text-center">Prey Sightings</th>
                  <th className="pb-3 font-medium text-center">Prey Biomass</th>
                  <th className="pb-3 font-medium text-right">Co-Occurrence Index</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border/20">
                {spatial_association.hotspot_stations.slice(0, 10).map((st, idx) => (
                  <tr key={idx} className="hover:bg-surface-hover/50 transition-colors">
                    <td className="py-3 font-semibold text-foreground font-mono">{st.camera_id}</td>
                    <td className="py-3 text-muted">{st.zone || "CORE"}</td>
                    <td className="py-3 text-muted capitalize">{st.habitat || "Dense Forest"}</td>
                    <td className="py-3 text-center font-mono font-bold text-amber-400">{st.tiger_sightings}</td>
                    <td className="py-3 text-center font-mono font-bold text-emerald-400">{st.prey_observations}</td>
                    <td className="py-3 text-center font-mono text-muted">{st.prey_individuals} animals</td>
                    <td className="py-3 text-right">
                      <span
                        className={`font-mono text-xs font-bold px-2.5 py-1 rounded-full ${
                          st.co_occurrence_index >= 0.7
                            ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30"
                            : st.co_occurrence_index >= 0.4
                            ? "bg-amber-500/15 text-amber-400 border border-amber-500/30"
                            : "bg-slate-500/15 text-slate-300"
                        }`}
                      >
                        {(st.co_occurrence_index * 100).toFixed(0)}%
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tab 3: Diel Activity Patterns */}
      {activeTab === "diel" && (
        <div className="rounded-2xl border border-border/50 bg-surface p-5 space-y-5">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
            <div>
              <h3 className="text-base font-bold text-foreground">24-Hour Diel Activity Curves (Predator vs Prey)</h3>
              <p className="text-xs text-muted">
                Temporal distribution of animal presence over a 24-hour cycle.
              </p>
            </div>
            <div className="flex items-center gap-4 text-xs">
              <div className="flex items-center gap-1.5">
                <span className="h-3 w-3 rounded-full bg-amber-400" />
                <span className="text-muted">Tiger (Predator)</span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="h-3 w-3 rounded-full bg-emerald-400" />
                <span className="text-muted">Chital (Prey)</span>
              </div>
              <div className="rounded-lg bg-background px-3 py-1 text-xs font-mono font-semibold text-primary border border-border">
                Overlap Δ = {temporal_association.overlap_coefficient_tiger_chital}
              </div>
            </div>
          </div>

          {/* Activity Bar Chart (24 Hours) */}
          <div className="h-56 w-full pt-4 flex items-end gap-1.5">
            {temporal_association.diel_curves.map((curve, idx) => {
              const maxVal = Math.max(
                ...temporal_association.diel_curves.map((c) => Math.max(c.tiger, c.chital)),
                1
              );
              const tigerHeight = Math.round((curve.tiger / maxVal) * 100);
              const chitalHeight = Math.round((curve.chital / maxVal) * 100);

              return (
                <div key={idx} className="flex-1 flex flex-col items-center gap-1 h-full justify-end group">
                  <div className="w-full flex items-end gap-0.5 h-44">
                    {/* Tiger Bar */}
                    <div
                      className="flex-1 bg-amber-400/80 hover:bg-amber-400 rounded-t transition-all"
                      style={{ height: `${tigerHeight}%` }}
                      title={`Hour ${curve.hour}: ${curve.tiger} tiger detections`}
                    />
                    {/* Chital Bar */}
                    <div
                      className="flex-1 bg-emerald-400/80 hover:bg-emerald-400 rounded-t transition-all"
                      style={{ height: `${chitalHeight}%` }}
                      title={`Hour ${curve.hour}: ${curve.chital} chital detections`}
                    />
                  </div>
                  <span className="text-[10px] text-muted font-mono rotate-45 sm:rotate-0 mt-1">
                    {idx % 3 === 0 ? curve.hour.slice(0, 2) : ""}
                  </span>
                </div>
              );
            })}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2 border-t border-border/40 text-xs">
            <div className="p-3 rounded-xl bg-background/50 border border-border/30">
              <span className="font-semibold text-amber-400">Tiger Peak Activity Window:</span>
              <p className="mt-0.5 text-foreground font-mono">{temporal_association.tiger_peak_window}</p>
              <p className="mt-1 text-muted text-[11px]">Primarily crepuscular and nocturnal hunting movements.</p>
            </div>
            <div className="p-3 rounded-xl bg-background/50 border border-border/30">
              <span className="font-semibold text-emerald-400">Chital Peak Activity Window:</span>
              <p className="mt-0.5 text-foreground font-mono">{temporal_association.chital_peak_window}</p>
              <p className="mt-1 text-muted text-[11px]">Bimodal diurnal foraging with sharp dip during midday heat.</p>
            </div>
          </div>
        </div>
      )}

      {/* Tab 4: Waterhole Intelligence */}
      {activeTab === "waterhole" && (
        <div className="rounded-2xl border border-border/50 bg-surface p-5 space-y-4">
          <div>
            <h3 className="text-base font-bold text-foreground">Waterhole Intelligence & Encounter Risk</h3>
            <p className="text-xs text-muted">
              Monitoring camera traps situated within 1.2 km of perennial and seasonal water bodies in Pench.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {waterhole_intelligence.map((wh, idx) => (
              <div key={idx} className="rounded-2xl border border-border/50 bg-background/60 p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="font-mono text-sm font-bold text-foreground">{wh.camera_id}</span>
                  <span
                    className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${
                      wh.encounter_risk === "HIGH"
                        ? "bg-red-500/15 text-red-400 border-red-500/30"
                        : wh.encounter_risk === "MEDIUM"
                        ? "bg-amber-500/15 text-amber-400 border-amber-500/30"
                        : "bg-emerald-500/15 text-emerald-400 border-emerald-500/30"
                    }`}
                  >
                    RISK: {wh.encounter_risk}
                  </span>
                </div>

                <div className="text-xs space-y-1.5 text-muted">
                  <div className="flex justify-between">
                    <span>Distance to Water:</span>
                    <span className="font-mono font-semibold text-foreground">{wh.nearest_water_km} km</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Prey Visits (Drinking):</span>
                    <span className="font-mono font-semibold text-emerald-400">{wh.total_animals_drinking} animals</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Tiger Sightings:</span>
                    <span className="font-mono font-semibold text-amber-400">{wh.tiger_visits} sightings</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Peak Arrival:</span>
                    <span className="font-mono text-foreground">{wh.peak_visitation}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tab 5: Ecological Anomalies */}
      {activeTab === "anomalies" && (
        <div className="space-y-4">
          <div className="rounded-2xl border border-border/50 bg-surface p-5 space-y-4">
            <h3 className="text-base font-bold text-foreground">Real-time Ecological Anomaly Alerts</h3>
            <p className="text-xs text-muted">
              Statistical deviation monitors flagging unexpected prey declines, heightened alert clusters, or sudden shifts in foraging ranges.
            </p>

            <div className="space-y-3">
              {behaviour_and_anomalies.anomalies.map((anom, idx) => (
                <div
                  key={idx}
                  className="flex items-start gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4"
                >
                  <Warning size={20} className="text-amber-400 shrink-0 mt-0.5" />
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-xs font-bold text-amber-300">{anom.station_id}</span>
                      <span className="text-[10px] font-semibold uppercase tracking-wider rounded bg-amber-500/20 px-2 py-0.5 text-amber-200">
                        {anom.type}
                      </span>
                    </div>
                    <p className="text-xs text-amber-100">{anom.detail}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Behaviour Breakdown */}
          <div className="rounded-2xl border border-border/50 bg-surface p-5 space-y-4">
            <h3 className="text-base font-bold text-foreground">Prey Behavioural Distribution (FR-10)</h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 text-center">
              {behaviour_and_anomalies.behaviour_distribution.map((b, idx) => (
                <div key={idx} className="rounded-xl border border-border/40 bg-background/50 p-3">
                  <span className="text-[11px] text-muted capitalize">{b.behaviour}</span>
                  <p className="mt-1 text-lg font-bold text-foreground">{b.total_animals}</p>
                  <span className="text-[10px] text-muted">observations</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
