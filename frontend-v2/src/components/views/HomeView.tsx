"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import dynamic from "next/dynamic";
import { motion } from "motion/react";
import {
  PawPrint,
  Camera,
  WarningCircle,
  Clock,
  Radio,
  MapPin,
  MagnifyingGlass,
  ArrowRight,
  ArrowUpRight,
  CheckSquare,
  Square,
  ShieldCheck,
  ChartLineUp,
  TrendUp,
  TrendDown,
} from "@phosphor-icons/react";
import type { MapLayerToggles } from "@/components/LeafletSatelliteMap";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import {
  api,
  type Stats,
  type GISMapBundle,
  type GalleryIndividual,
  type GISStation,
} from "@/lib/api";

const LeafletSatelliteMap = dynamic(
  () => import("@/components/LeafletSatelliteMap").then((mod) => mod.LeafletSatelliteMap),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full w-full items-center justify-center bg-zinc-950 font-mono text-xs text-zinc-400">
        Loading Pench GIS Map...
      </div>
    ),
  }
);

type LayerKey = keyof MapLayerToggles;

const LAYER_CONFIG: { key: LayerKey; label: string }[] = [
  { key: "lastSeen", label: "Tigers last seen" },
  { key: "territories", label: "Territories" },
  { key: "stations", label: "Cameras" },
  { key: "core", label: "Core forest" },
  { key: "buffer", label: "Buffer zone" },
  { key: "villages", label: "Villages" },
];

/* Zone palette derived from the theme: forest accent for core, a lighter
   sage for buffer, and the ochre caution hue for corridors — used by both
   the zone donut and the trend chart so a zone keeps one colour everywhere. */
const ZONE_COLORS = {
  core: "#2F5233",
  buffer: "#8AAB7E",
  corridor: "#C08A3E",
} as const;

const ZONES = [
  { key: "core", label: "Core Reserve", note: "Prime breeding territories", count: 38 },
  { key: "buffer", label: "Buffer Zone", note: "Fringe shared habitats", count: 16 },
  { key: "corridor", label: "Corridors", note: "Kanha–Pench movement trail", count: 8 },
] as const;

const DETECTIONS_2H = [3, 5, 8, 4, 9, 7, 11, 5, 10, 7, 12, 8];

const WEEK_DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const WEEKLY_SERIES = [
  { key: "core", label: "Core", values: [3, 4, 3, 5, 5, 4, 5] },
  { key: "buffer", label: "Buffer", values: [2, 2, 2, 3, 2, 2, 2] },
  { key: "corridor", label: "Corridors", values: [0, 1, 0, 1, 1, 0, 1] },
] as const;

function DashCard({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <section
      className={`rounded-2xl border border-border bg-surface p-4 shadow-[0_1px_2px_rgba(31,36,32,0.04)] transition-colors hover:border-border-strong ${className}`}
    >
      {children}
    </section>
  );
}

function CardHeader({
  icon,
  title,
  aside,
}: {
  icon: ReactNode;
  title: string;
  aside?: ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-2">
      <div className="flex min-w-0 items-center gap-2">
        <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-lg bg-accent-soft text-accent">
          {icon}
        </span>
        <h2 className="truncate text-[13px] font-semibold text-foreground">{title}</h2>
      </div>
      {aside ?? (
        <button
          type="button"
          aria-label={`Open ${title}`}
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-border text-muted transition-colors hover:border-accent/40 hover:bg-accent-soft hover:text-accent"
        >
          <ArrowUpRight size={11} weight="bold" />
        </button>
      )}
    </div>
  );
}

function LiveDot() {
  return (
    <span className="relative mr-1 inline-flex h-1.5 w-1.5 align-middle">
      <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-positive opacity-50" />
      <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-positive" />
    </span>
  );
}

function KpiTile({
  icon,
  title,
  value,
  suffix,
  badge,
  meta,
  parts,
}: {
  icon: ReactNode;
  title: string;
  value: ReactNode;
  suffix?: ReactNode;
  badge?: ReactNode;
  meta: ReactNode;
  parts: { label: string; value: number; color: string }[];
}) {
  const total = parts.reduce((sum, p) => sum + p.value, 0) || 1;
  return (
    <DashCard className="p-3.5">
      <CardHeader icon={icon} title={title} aside={badge} />
      <div className="mt-2.5 flex items-baseline gap-1">
        <span className="font-serif text-3xl font-medium leading-none tabular-nums tracking-tight text-foreground">
          {value}
        </span>
        {suffix && <span className="text-xs text-muted">{suffix}</span>}
      </div>
      <div className="mt-1 truncate text-2xs text-muted">{meta}</div>
      <div className="mt-2.5 flex h-1.5 w-full gap-0.5 overflow-hidden rounded-full bg-surface-sunken">
        {parts.map((p) => (
          <div
            key={p.label}
            className="h-full transition-[width] duration-500"
            style={{ width: `${(p.value / total) * 100}%`, backgroundColor: p.color }}
          />
        ))}
      </div>
      <div className="mt-1.5 flex items-center justify-between gap-2 font-mono text-[10px] text-muted">
        {parts.map((p) => (
          <span key={p.label} className="flex min-w-0 items-center gap-1 truncate">
            <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: p.color }} />
            <span className="font-semibold text-foreground">{p.value}</span> {p.label}
          </span>
        ))}
      </div>
    </DashCard>
  );
}

function DeltaPill({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-positive-soft px-1.5 py-0.5 font-mono text-[10px] font-semibold text-positive">
      <TrendUp size={10} weight="bold" />
      {children}
    </span>
  );
}

/** Smooth path through points using horizontal-tangent cubic segments —
 * never overshoots the data, unlike Catmull-Rom. */
function smoothPath(points: [number, number][]) {
  return points
    .map(([x, y], i) => {
      if (i === 0) return `M ${x} ${y}`;
      const [px, py] = points[i - 1];
      const mx = (px + x) / 2;
      return `C ${mx} ${py}, ${mx} ${y}, ${x} ${y}`;
    })
    .join(" ");
}

function ZoneDonut({ total }: { total: number }) {
  const r = 46;
  const circumference = 2 * Math.PI * r;
  const sum = ZONES.reduce((s, z) => s + z.count, 0);
  const gap = 3;
  let offset = 0;
  return (
    <div className="relative h-[88px] w-[88px] shrink-0">
      <svg viewBox="0 0 120 120" className="h-full w-full -rotate-90" role="img" aria-label="Population by zone">
        <circle cx="60" cy="60" r={r} fill="none" stroke="var(--surface-sunken)" strokeWidth="14" />
        {ZONES.map((z) => {
          const len = (z.count / sum) * circumference;
          const seg = (
            <circle
              key={z.key}
              cx="60"
              cy="60"
              r={r}
              fill="none"
              stroke={ZONE_COLORS[z.key]}
              strokeWidth="14"
              strokeDasharray={`${Math.max(len - gap, 0)} ${circumference}`}
              strokeDashoffset={-offset}
            />
          );
          offset += len;
          return seg;
        })}
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="font-serif text-2xl font-medium leading-none tabular-nums text-foreground">{total}</span>
        <span className="mt-0.5 font-mono text-[9px] uppercase tracking-wider text-muted">Tigers</span>
      </div>
    </div>
  );
}

/** Stretches to whatever height its card leaves it: the plot is a
 * non-uniformly scaled SVG (strokes kept crisp with non-scaling-stroke),
 * while labels and end dots are HTML so they never distort. */
function WeeklyTrendChart() {
  const yMax = 6;
  const ticks = [6, 3, 0];
  const n = WEEK_DAYS.length;
  const xPct = (i: number) => (i / (n - 1)) * 100;
  const yPct = (v: number) => (1 - v / yMax) * 100;

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex min-h-0 flex-1 gap-2">
        <div className="flex flex-col justify-between py-0 font-mono text-[9px] leading-none text-muted">
          {ticks.map((t) => (
            <span key={t} className="-translate-y-1/2 first:translate-y-0 last:translate-y-0">
              {t}
            </span>
          ))}
        </div>
        <div className="relative min-h-0 flex-1">
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="absolute inset-0 h-full w-full overflow-visible">
            <defs>
              <linearGradient id="core-area" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={ZONE_COLORS.core} stopOpacity="0.16" />
                <stop offset="100%" stopColor={ZONE_COLORS.core} stopOpacity="0" />
              </linearGradient>
            </defs>
            {ticks.map((t) => (
              <line
                key={t}
                x1="0"
                x2="100"
                y1={yPct(t)}
                y2={yPct(t)}
                stroke="var(--border)"
                strokeWidth="1"
                strokeDasharray={t === 0 ? undefined : "2 3"}
                vectorEffect="non-scaling-stroke"
              />
            ))}
            {WEEKLY_SERIES.map((series) => {
              const pts = series.values.map((v, i) => [xPct(i), yPct(v)] as [number, number]);
              const d = smoothPath(pts);
              return (
                <g key={series.key}>
                  {series.key === "core" && <path d={`${d} L 100 100 L 0 100 Z`} fill="url(#core-area)" />}
                  <path
                    d={d}
                    fill="none"
                    stroke={ZONE_COLORS[series.key]}
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    vectorEffect="non-scaling-stroke"
                  />
                </g>
              );
            })}
          </svg>
          {WEEKLY_SERIES.map((series) => (
            <span
              key={series.key}
              className="absolute h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 bg-surface"
              style={{
                left: "100%",
                top: `${yPct(series.values[series.values.length - 1])}%`,
                borderColor: ZONE_COLORS[series.key],
              }}
            />
          ))}
        </div>
      </div>
      <div className="relative ml-4 mt-1.5 h-3 font-mono text-[9px] text-muted">
        {WEEK_DAYS.map((day, i) => (
          <span
            key={day}
            className={`absolute top-0 ${i === 0 ? "" : i === n - 1 ? "-translate-x-full" : "-translate-x-1/2"}`}
            style={{ left: `${xPct(i)}%` }}
          >
            {day}
          </span>
        ))}
      </div>
    </div>
  );
}

function DetectionsChart() {
  const max = Math.max(...DETECTIONS_2H);
  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="grid min-h-0 flex-1 grid-cols-12 items-end gap-1">
        {DETECTIONS_2H.map((v, idx) => (
          <div
            key={idx}
            title={`${String(idx * 2).padStart(2, "0")}:00 · ${v} detections`}
            style={{ height: `${(v / max) * 100}%` }}
            className={`rounded-[3px] transition-colors ${v === max ? "bg-accent" : "bg-accent/25 hover:bg-accent/50"}`}
          />
        ))}
      </div>
      <div className="mt-1.5 grid grid-cols-12 gap-1 font-mono text-[9px] text-muted">
        {DETECTIONS_2H.map((_, idx) => (
          <span key={idx} className="text-center">
            {idx % 3 === 0 ? `${String(idx * 2).padStart(2, "0")}h` : ""}
          </span>
        ))}
      </div>
    </div>
  );
}

export function HomeView({
  stats,
  onOpenTiger,
}: {
  stats: Stats | null;
  onOpenTiger: (tigerId: string) => void;
}) {
  const { t } = useLanguage();

  const [bundle, setBundle] = useState<GISMapBundle | null>(null);
  const [individuals, setIndividuals] = useState<GalleryIndividual[] | null>(null);
  const [selectedStation, setSelectedStation] = useState<GISStation | null>(null);
  const [selectedTigerId, setSelectedTigerId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [legendTab, setLegendTab] = useState<"zones" | "territory" | "stations">("zones");

  const [layers, setLayers] = useState<MapLayerToggles>({
    core: true,
    buffer: true,
    stations: true,
    villages: false,
    territories: true,
    subregions: false,
    lastSeen: true,
  });

  const toggleLayer = (key: LayerKey) =>
    setLayers((prev) => ({ ...prev, [key]: !prev[key] }));

  useEffect(() => {
    api.gisBundle().then(setBundle).catch(() => {});
    api.gallery().then((res) => setIndividuals(res.individuals)).catch(() => {});
  }, []);

  const searchResults = useMemo(() => {
    if (!bundle || !searchQuery.trim()) return [];
    const q = searchQuery.toLowerCase();
    return Object.values(bundle.territories || {})
      .filter((t) => t.tiger_id.toLowerCase().includes(q) || (t.name || "").toLowerCase().includes(q))
      .slice(0, 6);
  }, [bundle, searchQuery]);

  const totalTigers = bundle?.metadata.total_tigers ?? 62;
  const totalCameras = bundle?.metadata.total_stations ?? 295;

  const zoneCounts = useMemo(() => {
    const counts: Record<string, number> = { CORE: 0, BUFFER: 0, OTHER: 0 };
    for (const station of bundle?.stations ?? []) {
      const zone = (station.zone || "").toUpperCase();
      if (zone === "CORE" || zone === "BUFFER") counts[zone] += 1;
      else counts.OTHER += 1;
    }
    return counts;
  }, [bundle]);

  const territoryCount = bundle ? Object.keys(bundle.territories).length : 0;
  const totalTerritoryArea = useMemo(() => {
    if (!bundle) return 0;
    return Object.values(bundle.territories).reduce((sum, t) => sum + (t.area_km2 || 0), 0);
  }, [bundle]);

  const stationStatusCounts = useMemo(() => {
    const counts = { operational: 0, offline: 0 };
    for (const station of bundle?.stations ?? []) {
      if ((station.operational_status || "").toUpperCase() === "OPERATIONAL") counts.operational += 1;
      else counts.offline += 1;
    }
    return counts;
  }, [bundle]);

  return (
    <div className="flex h-full w-full flex-col overflow-hidden bg-background">
      {/* Top Bar Header */}
      <div className="flex shrink-0 flex-wrap items-center justify-between gap-4 border-b border-border bg-surface px-6 py-4">
        <div>
          <h1 className="font-serif text-2xl font-medium tracking-tight text-foreground sm:text-3xl">
            Real Time Overview
          </h1>
          <p className="mt-0.5 text-xs text-muted">
            Pench Tiger Reserve · Live telemetry, camera network, and territorial surveillance
          </p>
        </div>

        <div className="flex items-center gap-3">
          <span className="flex items-center gap-1.5 rounded-full border border-accent/25 bg-accent-soft px-3 py-1 font-mono text-xs font-semibold text-accent">
            <Radio size={12} weight="fill" className="animate-pulse" />
            Live Telemetry
          </span>
          <div className="hidden sm:flex items-center gap-2 rounded-xl border border-border bg-surface-sunken px-3 py-1 text-xs font-mono text-muted">
            <ShieldCheck size={14} className="text-accent" />
            <span>295 Camera Stations Online</span>
          </div>
        </div>
      </div>

      {/* Main 2-Column Content Layout */}
      <div className="flex flex-1 overflow-hidden p-4 sm:p-5 gap-5 bg-surface-sunken">
        {/* Left Column: Analytics — sized to fit the viewport without scrolling */}
        <div className="flex w-[400px] xl:w-[440px] shrink-0 flex-col gap-3 min-h-0 overflow-y-auto">
          {/* KPI row */}
          <div className="grid shrink-0 grid-cols-2 gap-3">
            <KpiTile
              icon={<PawPrint size={13} weight="fill" />}
              title="Sightings"
              value={28}
              suffix="today"
              badge={<DeltaPill>14.2%</DeltaPill>}
              meta={<><LiveDot />Last · 12 min ago</>}
              parts={[
                { label: "core", value: 18, color: ZONE_COLORS.core },
                { label: "buffer", value: 10, color: ZONE_COLORS.buffer },
              ]}
            />
            <KpiTile
              icon={<Radio size={13} weight="fill" />}
              title="Active tigers"
              value={22}
              suffix={`/ ${totalTigers}`}
              badge={
                <span className="shrink-0 rounded-full bg-surface-sunken px-1.5 py-0.5 font-mono text-[10px] font-semibold text-muted">
                  {Math.round((22 / totalTigers) * 100)}%
                </span>
              }
              meta={<><LiveDot />Last · 4 min ago</>}
              parts={[
                { label: "active", value: 22, color: ZONE_COLORS.core },
                { label: "unseen", value: Math.max(totalTigers - 22, 0), color: "var(--border-strong)" },
              ]}
            />
          </div>

          {/* Population by Zone */}
          <DashCard className="shrink-0">
            <CardHeader icon={<MapPin size={13} weight="fill" />} title="Population by zone" />
            <div className="mt-3 flex items-center gap-4">
              <ZoneDonut total={totalTigers} />
              <ul className="min-w-0 flex-1 space-y-2">
                {ZONES.map((z) => {
                  const pct = Math.round((z.count / ZONES.reduce((s, zz) => s + zz.count, 0)) * 100);
                  return (
                    <li key={z.key} title={z.note}>
                      <div className="flex items-center justify-between gap-2 text-xs">
                        <span className="flex min-w-0 items-center gap-1.5 font-medium text-foreground">
                          <span className="h-2 w-2 shrink-0 rounded-[2px]" style={{ backgroundColor: ZONE_COLORS[z.key] }} />
                          <span className="truncate">{z.label}</span>
                        </span>
                        <span className="shrink-0 font-semibold tabular-nums text-foreground">
                          {z.count}
                          <span className="ml-1 font-mono text-[10px] font-normal text-muted">{pct}%</span>
                        </span>
                      </div>
                      <div className="mt-1 h-1 w-full overflow-hidden rounded-full bg-surface-sunken">
                        <div className="h-full rounded-full" style={{ width: `${pct}%`, backgroundColor: ZONE_COLORS[z.key] }} />
                      </div>
                    </li>
                  );
                })}
              </ul>
            </div>
          </DashCard>

          {/* Activity: today's detections + weekly trends, filling remaining height */}
          <DashCard className="flex min-h-[260px] flex-1 flex-col">
            <CardHeader
              icon={<ChartLineUp size={13} weight="fill" />}
              title="Surveillance activity"
            />

            <div className="mt-3 grid shrink-0 grid-cols-3 divide-x divide-border rounded-xl bg-surface-sunken/60 py-2">
              {[
                { label: "Week", value: "48", delta: "+9.4%" },
                { label: "Month", value: "184", delta: "+15.2%" },
                { label: "Year", value: "2,207", delta: "+23.6%" },
              ].map((s) => (
                <div key={s.label} className="px-3">
                  <div className="font-mono text-[10px] uppercase tracking-wide text-muted">{s.label}</div>
                  <div className="mt-0.5 flex items-baseline gap-1.5">
                    <span className="font-serif text-lg font-medium leading-none tabular-nums text-foreground">{s.value}</span>
                    <span className="font-mono text-[10px] font-semibold text-positive">{s.delta}</span>
                  </div>
                </div>
              ))}
            </div>

            <div className="mt-3 flex min-h-0 flex-1 flex-col">
              <div className="flex shrink-0 items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-wide text-muted">This week · per day</span>
                <div className="flex items-center gap-2.5 font-mono text-[10px] text-muted">
                  {WEEKLY_SERIES.map((s) => (
                    <span key={s.key} className="flex items-center gap-1">
                      <span className="h-0.5 w-2.5 rounded-full" style={{ backgroundColor: ZONE_COLORS[s.key] }} />
                      {s.label}
                    </span>
                  ))}
                </div>
              </div>
              <div className="mt-2 min-h-[70px] flex-[3] pr-1">
                <WeeklyTrendChart />
              </div>

              <div className="mt-3 flex shrink-0 items-center justify-between border-t border-border pt-2.5">
                <span className="font-mono text-[10px] uppercase tracking-wide text-muted">Detections today · 2h</span>
                <span className="font-mono text-[10px] text-muted">
                  <span className="font-semibold text-foreground">{DETECTIONS_2H.reduce((a, b) => a + b, 0)}</span> total
                </span>
              </div>
              <div className="mt-2 min-h-[48px] flex-[2]">
                <DetectionsChart />
              </div>
            </div>
          </DashCard>
        </div>

        {/* Right Column: Full Interactive Map with Overlay Controls */}
        <div className="relative flex-1 h-full min-h-[600px] overflow-hidden rounded-2xl border border-border bg-zinc-950 shadow-sm">
          <LeafletSatelliteMap
            bundle={bundle}
            selectedStation={selectedStation}
            selectedTigerId={selectedTigerId}
            layers={layers}
            onSelectStation={(st) => {
              setSelectedStation(st);
              setSelectedTigerId(null);
            }}
            onSelectTiger={(tid) => {
              setSelectedTigerId(tid);
              setSelectedStation(null);
            }}
          />

          {/* Floating Toolbar on top of map (Layer Filters + Search) */}
          <div className="pointer-events-auto absolute top-3 left-4 right-20 z-[1000] flex flex-wrap items-center justify-between gap-2.5">
            {/* Layer Filter Pills */}
            <div className="flex flex-wrap items-center gap-1 rounded-xl border border-white/10 bg-zinc-950/85 p-1 backdrop-blur-md shadow-2xl">
              {LAYER_CONFIG.map(({ key, label }) => {
                const active = layers[key];
                return (
                  <button
                    key={key}
                    onClick={() => toggleLayer(key)}
                    className={`flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-mono transition-all ${
                      active
                        ? "bg-emerald-500/20 text-emerald-400 font-medium border border-emerald-500/30 shadow-xs"
                        : "text-zinc-400 hover:text-zinc-200 hover:bg-white/5"
                    }`}
                  >
                    {active ? <CheckSquare size={12} weight="fill" /> : <Square size={12} />}
                    <span>{label}</span>
                  </button>
                );
              })}
            </div>

            {/* Quick Search */}
            <div className="relative">
              <MagnifyingGlass size={13} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-zinc-400" />
              <input
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Find a tiger..."
                className="w-48 rounded-xl border border-white/15 bg-zinc-950/90 py-1.5 pl-8 pr-3 text-xs font-mono text-white placeholder:text-zinc-500 backdrop-blur-md focus:border-emerald-500 focus:outline-none shadow-2xl sm:w-56"
              />
              {searchResults.length > 0 && (
                <div className="absolute right-0 top-10 z-50 w-64 overflow-hidden rounded-xl border border-white/15 bg-zinc-950/95 shadow-2xl backdrop-blur-md">
                  {searchResults.map((res) => (
                    <button
                      key={res.tiger_id}
                      onClick={() => {
                        setSelectedTigerId(res.tiger_id);
                        setSearchQuery("");
                      }}
                      className="flex w-full items-center justify-between px-3.5 py-2 text-left text-xs font-mono text-zinc-200 hover:bg-white/10"
                    >
                      <span>{res.tiger_id}</span>
                      <ArrowRight size={12} className="text-zinc-400" />
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Floating Selected Tiger Card with Open Dossier Button */}
          {selectedTigerId && (
            <div className="pointer-events-auto absolute top-14 left-1/2 z-[1000] -translate-x-1/2 flex items-center gap-3 rounded-2xl border border-white/20 bg-zinc-950/90 px-4 py-2 shadow-2xl backdrop-blur-md animate-in fade-in slide-in-from-top-2 duration-200">
              <div className="flex items-center gap-2.5">
                <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-emerald-500/20 text-emerald-400">
                  <PawPrint size={18} weight="fill" />
                </span>
                <div>
                  <div className="font-mono text-sm font-bold text-white tracking-wide">{selectedTigerId}</div>
                  <div className="text-[11px] text-zinc-400">
                    {bundle?.territories?.[selectedTigerId]?.name
                      ? `${bundle.territories[selectedTigerId].name} · `
                      : ""}
                    Territory Active
                  </div>
                </div>
              </div>
              <div className="h-5 w-px bg-white/15" />
              <div className="flex items-center gap-2">
                <button
                  onClick={() => onOpenTiger(selectedTigerId)}
                  className="flex items-center gap-1.5 rounded-xl bg-emerald-500 hover:bg-emerald-400 px-3.5 py-1.5 text-xs font-semibold text-zinc-950 transition-all shadow-md active:scale-95"
                >
                  <span>Open dossier</span>
                  <ArrowRight size={13} weight="bold" />
                </button>
                <button
                  onClick={() => setSelectedTigerId(null)}
                  className="flex h-7 w-7 items-center justify-center rounded-xl border border-white/15 bg-white/5 text-zinc-300 hover:bg-white/15 hover:text-white transition-all text-xs"
                  title="Close"
                >
                  ✕
                </button>
              </div>
            </div>
          )}

          {/* Floating Camera Station Card */}
          {selectedStation && (
            <div className="pointer-events-auto absolute top-14 left-1/2 z-[1000] -translate-x-1/2 flex items-center gap-3 rounded-2xl border border-white/20 bg-zinc-950/90 px-4 py-2 shadow-2xl backdrop-blur-md animate-in fade-in slide-in-from-top-2 duration-200">
              <div className="flex items-center gap-2.5">
                <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-emerald-500/20 text-emerald-400">
                  <Camera size={18} weight="fill" />
                </span>
                <div>
                  <div className="font-mono text-sm font-bold text-white tracking-wide">{selectedStation.camera_id}</div>
                  <div className="text-[11px] text-zinc-400">
                    {selectedStation.zone} — {selectedStation.sub_region || "Pench Reserve"}
                  </div>
                </div>
              </div>
              <div className="h-5 w-px bg-white/15" />
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setSelectedStation(null)}
                  className="flex h-7 w-7 items-center justify-center rounded-xl border border-white/15 bg-white/5 text-zinc-300 hover:bg-white/15 hover:text-white transition-all text-xs"
                  title="Close"
                >
                  ✕
                </button>
              </div>
            </div>
          )}

          {/* Floating White Legend Card in Bottom-Right (Matches Reference Image) */}
          <div className="pointer-events-auto absolute bottom-4 right-4 z-[1000] w-64 rounded-2xl border border-border bg-surface p-3.5 shadow-xl">
            <div className="text-2xs uppercase font-mono font-semibold tracking-wider text-muted">
              Legend
            </div>

            {/* Tabs */}
            <div className="mt-2 flex rounded-lg bg-surface-sunken p-0.5 text-2xs font-mono">
              {(
                [
                  { key: "zones", label: "Zones" },
                  { key: "territory", label: "Territory" },
                  { key: "stations", label: "Stations" },
                ] as const
              ).map((tab) => (
                <button
                  key={tab.key}
                  onClick={() => setLegendTab(tab.key)}
                  className={`flex-1 rounded-md py-1 transition-colors ${
                    legendTab === tab.key
                      ? "bg-surface font-semibold text-foreground shadow-2xs"
                      : "text-muted hover:text-foreground"
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {legendTab === "zones" && (
              <>
                <div className="mt-2.5">
                  <div className="text-2xs text-muted font-mono">Total Individuals</div>
                  <div className="font-mono text-base font-bold text-foreground">{totalTigers} Identified Tigers</div>
                </div>
                <div className="mt-2.5">
                  <div className="h-1.5 w-full rounded-full bg-gradient-to-r from-emerald-500 via-cyan-400 to-blue-500" />
                  <div className="mt-1 flex items-center justify-between font-mono text-[9px] text-muted">
                    <span>Core ({zoneCounts.CORE})</span>
                    <span>Buffer ({zoneCounts.BUFFER})</span>
                    <span>Other ({zoneCounts.OTHER})</span>
                  </div>
                </div>
              </>
            )}

            {legendTab === "territory" && (
              <div className="mt-2.5">
                <div className="text-2xs text-muted font-mono">Tracked Territories</div>
                <div className="font-mono text-base font-bold text-foreground">{territoryCount} Territories</div>
                <div className="mt-1 font-mono text-[10px] text-muted">
                  {totalTerritoryArea.toFixed(1)} km² mapped
                </div>
              </div>
            )}

            {legendTab === "stations" && (
              <>
                <div className="mt-2.5">
                  <div className="text-2xs text-muted font-mono">Camera Stations</div>
                  <div className="font-mono text-base font-bold text-foreground">{totalCameras} Total</div>
                </div>
                <div className="mt-2.5">
                  <div className="h-1.5 w-full rounded-full bg-gradient-to-r from-emerald-500 to-red-500" />
                  <div className="mt-1 flex items-center justify-between font-mono text-[9px] text-muted">
                    <span>Operational ({stationStatusCounts.operational})</span>
                    <span>Offline ({stationStatusCounts.offline})</span>
                  </div>
                </div>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

