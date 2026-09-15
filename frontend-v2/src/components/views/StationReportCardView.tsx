"use client";

import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  ArrowLeft,
  Camera,
  PawPrint,
  MapPin,
  WarningCircle,
  Drop,
  House,
  Clock,
  Eye,
  ShieldCheck,
  Fire,
  CheckCircle,
  TrendUp,
  ArrowsOut,
} from "@phosphor-icons/react";
import { api, type StationDetailResponse, type StationSightingEvent, type StationTigerSeen } from "@/lib/api";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? "http://127.0.0.1:8420";

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtDate(ts: string | null) {
  if (!ts) return "—";
  try {
    const d = new Date(ts);
    return d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: true });
  } catch { return ts; }
}

function fmtShort(ts: string | null) {
  if (!ts) return "—";
  try {
    const d = new Date(ts);
    return d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "2-digit" });
  } catch { return ts; }
}

function relativeTime(ts: string | null): string {
  if (!ts) return "unknown";
  const diff = Date.now() - new Date(ts).getTime();
  const days = Math.floor(diff / 86400000);
  if (days === 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 7) return `${days} days ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  if (days < 365) return `${Math.floor(days / 30)}mo ago`;
  return `${Math.floor(days / 365)}y ago`;
}

function activityLevel(total: number): { label: string; color: string; bg: string; dot: string } {
  if (total >= 40) return { label: "Very High Activity", color: "text-rose-400", bg: "bg-rose-500/10", dot: "bg-rose-400" };
  if (total >= 20) return { label: "High Activity", color: "text-orange-400", bg: "bg-orange-500/10", dot: "bg-orange-400" };
  if (total >= 8)  return { label: "Moderate Activity", color: "text-amber-400", bg: "bg-amber-500/10", dot: "bg-amber-400" };
  if (total >= 1)  return { label: "Low Activity", color: "text-emerald-400", bg: "bg-emerald-500/10", dot: "bg-emerald-400" };
  return { label: "No Activity", color: "text-muted", bg: "bg-surface-sunken", dot: "bg-muted" };
}

function sexColor(sex: string | null) { return sex === "M" ? "text-sky-400" : sex === "F" ? "text-rose-400" : "text-muted"; }
function sexLabel(sex: string | null) { return sex === "M" ? "♂ Male" : sex === "F" ? "♀ Female" : "Unknown"; }

// ── Station mini-map ──────────────────────────────────────────────────────────

function StationMap({ lat, lon, stationId, tigers }: {
  lat: number; lon: number; stationId: string;
  tigers: StationTigerSeen[];
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);

  useEffect(() => {
    if (typeof window === "undefined" || !containerRef.current) return;
    let mounted = true;

    import("leaflet").then((mod) => {
      if (!mounted || !containerRef.current || mapRef.current) return;
      const L = mod.default || mod;

      const map = L.map(containerRef.current, {
        center: [lat, lon],
        zoom: 14,
        zoomControl: false,
        attributionControl: false,
        scrollWheelZoom: false,
      });

      L.control.zoom({ position: "topright" }).addTo(map);

      // Satellite basemap
      L.tileLayer("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", {
        maxZoom: 19,
        attribution: "© Esri",
      }).addTo(map);

      // Tiger home range circles
      tigers.forEach((t) => {
        if (t.core_centroid_lat == null || t.core_centroid_lon == null) return;
        const radius = t.mcp_area_km2 ? Math.sqrt(t.mcp_area_km2 / Math.PI) * 1000 : 1500;
        const isMale = t.sex === "M";
        L.circle([t.core_centroid_lat, t.core_centroid_lon], {
          radius,
          color: isMale ? "#38bdf8" : "#fb7185",
          weight: 1.5,
          dashArray: "5 6",
          fillColor: isMale ? "#38bdf8" : "#fb7185",
          fillOpacity: 0.07,
        }).bindTooltip(
          `<span style="font-family:monospace;font-size:11px"><b>${t.tiger_id}</b> home range · ${t.mcp_area_km2?.toFixed(1)} km²</span>`,
          { sticky: true }
        ).addTo(map);
      });

      // Station pin — prominent amber camera icon
      const stationIcon = L.divIcon({
        className: "",
        html: `<div style="
          width:32px;height:32px;border-radius:50%;
          background:#f59e0b;border:3px solid #fff;
          display:flex;align-items:center;justify-content:center;
          box-shadow:0 2px 10px rgba(245,158,11,0.6);
          font-size:14px;
        ">📷</div>`,
        iconSize: [32, 32],
        iconAnchor: [16, 16],
      });
      L.marker([lat, lon], { icon: stationIcon })
        .bindPopup(`<b style="font-family:monospace">${stationId}</b><br>${lat.toFixed(5)}°N, ${lon.toFixed(5)}°E`)
        .addTo(map);

      mapRef.current = map;
    });

    return () => {
      mounted = false;
      if (mapRef.current) { mapRef.current.remove(); mapRef.current = null; }
    };
  }, [lat, lon, stationId]);

  return (
    <div className="relative overflow-hidden rounded-2xl border border-border bg-zinc-950" style={{ height: 280 }}>
      <div ref={containerRef} className="h-full w-full" />
      <div className="pointer-events-none absolute bottom-2 left-2 rounded-md bg-black/60 px-2 py-1 backdrop-blur-sm">
        <span className="font-mono text-[10px] text-white/70">Satellite · {lat.toFixed(4)}°N {lon.toFixed(4)}°E</span>
      </div>
    </div>
  );
}

// ── Main Component ────────────────────────────────────────────────────────────

interface Props {
  stationId: string;
  onBack: () => void;
  onOpenTiger?: (tigerId: string) => void;
}

export function StationReportCardView({ stationId, onBack, onOpenTiger }: Props) {
  const [data, setData] = useState<StationDetailResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<"overview" | "tigers" | "sightings">("overview");

  useEffect(() => {
    setLoading(true);
    setError(null);
    api.stationDetail(stationId)
      .then(setData)
      .catch((e) => setError(e.message || "Failed to load station data"))
      .finally(() => setLoading(false));
  }, [stationId]);

  if (loading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <div className="flex flex-col items-center gap-3 text-muted">
          <div className="h-6 w-6 animate-spin rounded-full border-2 border-accent border-t-transparent" />
          <span className="text-sm">Loading station report…</span>
        </div>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="flex h-64 flex-col items-center justify-center gap-3 text-muted">
        <WarningCircle size={32} className="text-caution" />
        <span className="text-sm">{error || "Station not found"}</span>
        <button onClick={onBack} className="text-xs text-accent hover:underline">← Back to stations</button>
      </div>
    );
  }

  const { station, stats, tigers_seen, recent_sightings } = data;
  const isOnline = station.operational_status === "OPERATIONAL";
  const activity = activityLevel(stats.total_sightings);
  const dangerCount = stats.alert_counts.DANGER;
  const hasDanger = dangerCount > 0;
  const dominantTiger = tigers_seen[0] ?? null;
  const lastSeen = relativeTime(stats.last_seen);
  const qualityPct = stats.avg_image_quality != null ? Math.round(stats.avg_image_quality * 100) : null;

  return (
    <div className="min-h-screen bg-background">

      {/* ── Sticky header ── */}
      <div className="sticky top-0 z-20 border-b border-border bg-background/95 backdrop-blur-md">
        <div className="flex items-center gap-3 px-6 py-3.5">
          <button
            onClick={onBack}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-border text-muted transition-colors hover:border-border-strong hover:text-foreground"
          >
            <ArrowLeft size={15} />
          </button>
          <div className="flex min-w-0 flex-1 items-center gap-3">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-accent-soft text-accent">
              <Camera size={17} />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <h1 className="font-mono text-base font-bold text-foreground">{station.camera_id}</h1>
                <span className={`rounded-full px-2 py-0.5 font-mono text-[10px] font-semibold ${isOnline ? "bg-positive-soft text-positive" : "bg-danger-soft text-danger"}`}>
                  {isOnline ? "ONLINE" : "OFFLINE"}
                </span>
                {hasDanger && (
                  <span className="flex items-center gap-1 rounded-full bg-danger-soft px-2 py-0.5 font-mono text-[10px] font-semibold text-danger">
                    <Fire size={10} weight="fill" /> {dangerCount} Alert{dangerCount > 1 ? "s" : ""}
                  </span>
                )}
              </div>
              <div className="truncate text-xs text-muted">
                {station.zone} Zone · {station.sub_region || "Unknown Range"} · Grid {station.grid_id ?? "—"}
              </div>
            </div>
          </div>
        </div>

        {/* Tab bar */}
        <div className="flex border-t border-border px-6">
          {(["overview", "tigers", "sightings"] as const).map((t) => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-4 py-2.5 font-mono text-[11px] uppercase tracking-wide transition-colors ${
                tab === t ? "border-b-2 border-accent text-accent" : "border-b-2 border-transparent text-muted hover:text-foreground"
              }`}
            >
              {t === "overview" ? "Overview" : t === "tigers" ? `Tigers (${stats.unique_tigers})` : `Log (${Math.min(50, stats.total_sightings)})`}
            </button>
          ))}
        </div>
      </div>

      {/* ── Body ── */}
      <div className="px-6 py-6">
        <AnimatePresence mode="wait">

          {/* ─── OVERVIEW ─────────────────────────────────────────────── */}
          {tab === "overview" && (
            <motion.div key="ov" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}
              className="space-y-5"
            >
              {/* Insight hero card */}
              <div className={`rounded-2xl border border-border ${activity.bg} p-5`}>
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className={`h-2 w-2 rounded-full ${activity.dot} animate-pulse`} />
                      <span className={`font-mono text-xs font-semibold uppercase tracking-wide ${activity.color}`}>{activity.label}</span>
                    </div>
                    <p className="mt-2 text-2xl font-bold text-foreground">
                      {stats.total_sightings} <span className="text-base font-normal text-muted">captures</span>
                    </p>
                    <p className="mt-1 text-sm text-muted">
                      {stats.unique_tigers} unique tiger{stats.unique_tigers !== 1 ? "s" : ""} recorded · Last active <span className="text-foreground font-medium">{lastSeen}</span>
                    </p>
                  </div>
                  {dominantTiger && (
                    <div className="shrink-0 text-right">
                      <div className="font-mono text-[10px] uppercase tracking-wide text-muted">Most frequent</div>
                      <button onClick={() => onOpenTiger?.(dominantTiger.tiger_id)}
                        className={`mt-1 font-mono text-sm font-bold hover:underline ${sexColor(dominantTiger.sex)}`}
                      >
                        {dominantTiger.tiger_id}
                      </button>
                      <div className="text-xs text-muted">{dominantTiger.num_captures_here} visits</div>
                    </div>
                  )}
                </div>

                {/* Alert bar */}
                {stats.total_sightings > 0 && (
                  <div className="mt-4">
                    <div className="mb-1.5 flex items-center justify-between text-[10px] text-muted">
                      <span>Alert distribution</span>
                      <span>{stats.alert_counts.SAFE} safe · {stats.alert_counts.CAUTION} caution · {stats.alert_counts.DANGER} danger</span>
                    </div>
                    <div className="h-1.5 w-full overflow-hidden rounded-full bg-black/20">
                      <div className="flex h-full">
                        {stats.alert_counts.SAFE > 0 && <div className="bg-emerald-500" style={{ width: `${(stats.alert_counts.SAFE / stats.total_sightings) * 100}%` }} />}
                        {stats.alert_counts.CAUTION > 0 && <div className="bg-amber-400" style={{ width: `${(stats.alert_counts.CAUTION / stats.total_sightings) * 100}%` }} />}
                        {stats.alert_counts.DANGER > 0 && <div className="bg-rose-500" style={{ width: `${(stats.alert_counts.DANGER / stats.total_sightings) * 100}%` }} />}
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* Satellite map */}
              <StationMap lat={station.latitude} lon={station.longitude} stationId={station.camera_id} tigers={tigers_seen} />

              {/* Quick insight pills */}
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <InsightPill
                  icon={<TrendUp size={14} />}
                  label="Avg Confidence"
                  value={qualityPct != null ? `${qualityPct}%` : "—"}
                  sub="image quality"
                />
                <InsightPill
                  icon={<PawPrint size={14} />}
                  label="Prey Density"
                  value={stats.avg_prey_density != null ? stats.avg_prey_density.toFixed(1) : "—"}
                  sub="avg at station"
                />
                <InsightPill
                  icon={<Clock size={14} />}
                  label="Active Since"
                  value={fmtShort(stats.first_seen)}
                  sub="first capture"
                />
                <InsightPill
                  icon={<Eye size={14} />}
                  label="Last Seen"
                  value={fmtShort(stats.last_seen)}
                  sub={lastSeen}
                />
              </div>

              {/* Danger alert callout */}
              {hasDanger && (
                <div className="flex items-start gap-3 rounded-xl border border-danger/30 bg-danger-soft p-4">
                  <Fire size={20} weight="fill" className="mt-0.5 shrink-0 text-danger" />
                  <div>
                    <div className="font-medium text-danger">Threat events recorded</div>
                    <p className="mt-0.5 text-xs text-danger/80">
                      {dangerCount} danger-level sighting{dangerCount > 1 ? "s" : ""} at this station. Review the sighting log for details.
                    </p>
                  </div>
                </div>
              )}

              {/* Station location context */}
              <div className="rounded-2xl border border-border bg-surface p-5">
                <h2 className="mb-4 flex items-center gap-2 font-mono text-[11px] uppercase tracking-wide text-muted">
                  <MapPin size={13} /> Location Context
                </h2>
                <div className="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-3">
                  <ContextRow label="Zone" value={station.zone} highlight={station.zone === "CORE"} />
                  <ContextRow label="Range / Sub-region" value={station.sub_region || "—"} />
                  <ContextRow label="Habitat" value={station.habitat || "—"} />
                  <ContextRow label="Trail type" value={station.trail_type || "—"} />
                  <ContextRow label="Nearest water" value={station.nearest_water_km != null ? `${station.nearest_water_km.toFixed(1)} km` : "—"} icon={<Drop size={11} />} />
                  <ContextRow label="Nearest village" value={station.nearest_village_km != null ? `${station.nearest_village_km.toFixed(1)} km` : "—"} icon={<House size={11} />} />
                  <ContextRow label="Elevation" value={station.elevation_m != null ? `${station.elevation_m} m` : "—"} />
                  <ContextRow label="Status" value={station.operational_status} icon={<ShieldCheck size={11} />} highlight={isOnline} />
                  <ContextRow label="Coordinates" value={`${station.latitude.toFixed(5)}, ${station.longitude.toFixed(5)}`} mono />
                </div>
                <a
                  href={`https://www.google.com/maps?q=${station.latitude},${station.longitude}`}
                  target="_blank" rel="noopener noreferrer"
                  className="mt-4 inline-flex items-center gap-1.5 text-xs text-accent hover:underline"
                >
                  <ArrowsOut size={12} /> Open in Google Maps
                </a>
              </div>
            </motion.div>
          )}

          {/* ─── TIGERS ───────────────────────────────────────────────── */}
          {tab === "tigers" && (
            <motion.div key="tig" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
              {tigers_seen.length === 0 ? (
                <div className="flex h-48 items-center justify-center text-sm text-muted">No tiger sightings recorded.</div>
              ) : (
                <div className="space-y-3">
                  <p className="text-xs text-muted">{tigers_seen.length} individual{tigers_seen.length !== 1 ? "s" : ""} recorded at this station, ranked by visit frequency.</p>
                  <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    {tigers_seen.map((tiger, i) => (
                      <TigerCard key={tiger.tiger_id} tiger={tiger} rank={i + 1} onOpenTiger={onOpenTiger} />
                    ))}
                  </div>
                </div>
              )}
            </motion.div>
          )}

          {/* ─── SIGHTINGS LOG ────────────────────────────────────────── */}
          {tab === "sightings" && (
            <motion.div key="log" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
              {recent_sightings.length === 0 ? (
                <div className="flex h-48 items-center justify-center text-sm text-muted">No sightings logged.</div>
              ) : (
                <div className="space-y-3">
                  <p className="text-xs text-muted">
                    {recent_sightings.length} most recent events{stats.total_sightings > 50 ? ` of ${stats.total_sightings} total` : ""} · newest first
                  </p>
                  <div className="space-y-2">
                    {recent_sightings.map((s, i) => (
                      <SightingCard key={s.event_id || i} sighting={s} onOpenTiger={onOpenTiger} />
                    ))}
                  </div>
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// ── Sub-components ────────────────────────────────────────────────────────────

function InsightPill({ icon, label, value, sub }: { icon: React.ReactNode; label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-xl border border-border bg-surface p-3.5">
      <div className="flex items-center gap-1.5 text-muted mb-1">{icon}<span className="font-mono text-[9px] uppercase tracking-wide">{label}</span></div>
      <div className="font-mono text-base font-bold text-foreground">{value}</div>
      {sub && <div className="mt-0.5 text-[10px] text-muted">{sub}</div>}
    </div>
  );
}

function ContextRow({ label, value, icon, highlight, mono }: { label: string; value: string; icon?: React.ReactNode; highlight?: boolean; mono?: boolean }) {
  return (
    <div>
      <div className="flex items-center gap-1 font-mono text-[9px] uppercase tracking-wide text-muted">{icon}{label}</div>
      <div className={`mt-0.5 text-sm font-medium ${highlight ? "text-positive" : "text-foreground"} ${mono ? "font-mono text-xs" : ""}`}>{value}</div>
    </div>
  );
}

function TigerCard({ tiger, rank, onOpenTiger }: { tiger: StationTigerSeen; rank: number; onOpenTiger?: (id: string) => void }) {
  const imgUrl = tiger.thumbnail ? `${API_BASE}${tiger.thumbnail}` : null;
  const hasDanger = tiger.alert_levels.includes("DANGER");

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, delay: rank * 0.04 }}
      className="rounded-2xl border border-border bg-surface p-5"
    >
      <div className="flex items-center gap-3">
        {/* Rank + avatar */}
        <div className="relative shrink-0">
          <div className="flex h-11 w-11 items-center justify-center overflow-hidden rounded-full bg-surface-sunken ring-1 ring-border">
            {imgUrl ? (
              <img src={imgUrl} alt={tiger.tiger_id} className="h-full w-full object-cover"
                onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }} />
            ) : (
              <PawPrint size={18} className="text-muted" />
            )}
          </div>
          <span className="absolute -bottom-1 -right-1 flex h-4 w-4 items-center justify-center rounded-full bg-accent text-[9px] font-bold text-white">
            {rank}
          </span>
        </div>

        <div className="min-w-0 flex-1">
          <button onClick={() => onOpenTiger?.(tiger.tiger_id)}
            className={`font-mono text-sm font-bold hover:underline ${sexColor(tiger.sex)}`}
          >
            {tiger.tiger_id}
          </button>
          <div className="text-xs text-muted">{sexLabel(tiger.sex)}{tiger.life_stage ? ` · ${tiger.life_stage}` : ""}</div>
        </div>

        <div className="text-right shrink-0">
          <div className="font-mono text-lg font-bold text-foreground">{tiger.num_captures_here}</div>
          <div className="text-[10px] text-muted">visits</div>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3 border-t border-border pt-3">
        <div>
          <div className="font-mono text-[9px] uppercase tracking-wide text-muted">Last seen here</div>
          <div className="mt-0.5 text-xs font-medium text-foreground">{fmtShort(tiger.last_seen_here)}</div>
        </div>
        <div>
          <div className="font-mono text-[9px] uppercase tracking-wide text-muted">Home range</div>
          <div className="mt-0.5 text-xs font-medium text-foreground">{tiger.mcp_area_km2 != null ? `${tiger.mcp_area_km2.toFixed(1)} km²` : "—"}</div>
        </div>
        <div>
          <div className="font-mono text-[9px] uppercase tracking-wide text-muted">Flanks captured</div>
          <div className="mt-0.5 text-xs font-medium text-foreground">{tiger.flanks_seen.length > 0 ? tiger.flanks_seen.join(" + ") : "—"}</div>
        </div>
        <div>
          <div className="font-mono text-[9px] uppercase tracking-wide text-muted">Territory</div>
          <div className="mt-0.5 text-xs font-medium text-foreground">{tiger.territorial_status || "—"}</div>
        </div>
      </div>

      {hasDanger && (
        <div className="mt-3 flex items-center gap-1.5 rounded-lg bg-danger-soft px-2.5 py-1.5 text-xs font-medium text-danger">
          <Fire size={12} weight="fill" /> Danger-level event at this station
        </div>
      )}
    </motion.div>
  );
}

function SightingCard({ sighting, onOpenTiger }: { sighting: StationSightingEvent; onOpenTiger?: (id: string) => void }) {
  const level = (sighting.alert_level || "SAFE").toUpperCase();
  const levelStyle =
    level === "DANGER" ? "border-danger/20 bg-danger-soft" :
    level === "CAUTION" ? "border-caution/20 bg-caution-soft" :
    "border-border bg-surface";
  const dotColor = level === "DANGER" ? "bg-danger" : level === "CAUTION" ? "bg-caution" : "bg-positive";

  return (
    <div className={`flex items-center gap-3 rounded-xl border px-4 py-3 ${levelStyle}`}>
      <span className={`h-2 w-2 shrink-0 rounded-full ${dotColor}`} />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
          <button onClick={() => onOpenTiger?.(sighting.tiger_id)}
            className={`font-mono text-sm font-semibold hover:underline ${sexColor(sighting.sex)}`}
          >
            {sighting.tiger_id}
          </button>
          {sighting.flank_side && <span className="font-mono text-[10px] text-muted">{sighting.flank_side} flank</span>}
          {sighting.habitat_type && <span className="text-[10px] text-muted">· {sighting.habitat_type}</span>}
          {sighting.threat_reason && <span className="text-[10px] font-medium text-danger">{sighting.threat_reason}</span>}
        </div>
        <div className="mt-0.5 text-xs text-muted">{fmtDate(sighting.timestamp)}</div>
      </div>
      <div className="shrink-0 text-right">
        {sighting.reid_confidence != null && (
          <div className="font-mono text-xs text-muted">{(sighting.reid_confidence * 100).toFixed(0)}%</div>
        )}
        {sighting.prey_density != null && (
          <div className="font-mono text-[10px] text-muted">prey: {sighting.prey_density.toFixed(0)}</div>
        )}
      </div>
    </div>
  );
}
