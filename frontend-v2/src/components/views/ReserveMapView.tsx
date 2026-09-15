"use client";

import { useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import {
  Camera,
  PawPrint,
  House,
  MagnifyingGlass,
  ArrowRight,
  WarningCircle,
  CheckSquare,
  Square,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { StationUploadPanel } from "@/components/StationUploadPanel";
import type { MapLayerToggles } from "@/components/LeafletSatelliteMap";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import {
  api,
  type Stats,
  type GISMapBundle,
  type GISStation,
} from "@/lib/api";

const LeafletSatelliteMap = dynamic(
  () => import("@/components/LeafletSatelliteMap").then((mod) => mod.LeafletSatelliteMap),
  {
    ssr: false,
    loading: () => <MapLoadingFallback />,
  }
);

type LayerKey = keyof MapLayerToggles;

const LAYER_CONFIG: { key: LayerKey; labelKey: string }[] = [
  { key: "lastSeen", labelKey: "map.layerLastSeen" },
  { key: "territories", labelKey: "map.layerTerritories" },
  { key: "stations", labelKey: "map.layerStations" },
  { key: "core", labelKey: "map.layerCore" },
  { key: "buffer", labelKey: "map.layerBuffer" },
  { key: "villages", labelKey: "map.layerVillages" },
  { key: "subregions", labelKey: "map.layerSubregions" },
];

export function ReserveMapView({
  onOpenTiger,
  stats,
}: {
  onOpenTiger: (tigerId: string) => void;
  stats: Stats | null;
}) {
  const { t } = useLanguage();
  const [bundle, setBundle] = useState<GISMapBundle | null>(null);
  const [selectedStation, setSelectedStation] = useState<GISStation | null>(null);
  const [uploadStation, setUploadStation] = useState<GISStation | null>(null);
  const [selectedTigerId, setSelectedTigerId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");

  // Tigers Last Seen defaults ON — situational awareness is the whole
  // point of landing here, per the UX plan.
  const [layers, setLayers] = useState<MapLayerToggles>({
    core: true,
    buffer: true,
    stations: true,
    villages: false,
    territories: false,
    subregions: false,
    lastSeen: true,
  });

  useEffect(() => {
    api.gisBundle().then(setBundle).catch((err) => {
      console.error("[ReserveMapView] Error fetching bundle:", err);
    });
  }, []);

  const toggleLayer = (key: LayerKey) =>
    setLayers((prev) => ({ ...prev, [key]: !prev[key] }));

  const criticalTigers = useMemo(() => {
    if (!bundle) return [];
    const seen = new Set<string>();
    const results: { tiger_id: string; reason: string }[] = [];
    for (const s of bundle.recent_sightings || []) {
      if (s.alert_level === "CRITICAL" && !seen.has(s.tiger_id)) {
        seen.add(s.tiger_id);
        results.push({ tiger_id: s.tiger_id, reason: s.threat_reason || t("map.threatReasonDefault") });
      }
    }
    return results;
  }, [bundle, t]);

  const searchResults = useMemo(() => {
    if (!bundle || !searchQuery.trim()) return [];
    const q = searchQuery.toLowerCase();
    return Object.values(bundle.territories || {})
      .filter((t) => t.tiger_id.toLowerCase().includes(q) || (t.name || "").toLowerCase().includes(q))
      .slice(0, 6);
  }, [bundle, searchQuery]);

  return (
    <div className="min-h-full">
      <TopBar
        title={t("map.title")}
        subtitle={t("map.subtitle")}
        alertCount={stats?.pending_review ?? 0}
        center={
          <div className="flex flex-wrap items-center gap-2 sm:gap-2.5">
            <StatChip icon={PawPrint} label={t("map.statTigers")} value={bundle?.metadata.total_tigers ?? 62} />
            <StatChip icon={Camera} label={t("map.statCameras")} value={bundle?.metadata.total_stations ?? 295} />
            <StatChip icon={House} label={t("map.statVillages")} value={bundle?.metadata.total_villages ?? 44} />
            {criticalTigers.length > 0 && (
              <div className="flex items-center gap-1.5 rounded-xl border border-danger/40 bg-danger-soft px-3 py-1.5 text-danger">
                <WarningCircle size={15} weight="fill" className="shrink-0" />
                <span className="text-xs font-semibold">
                  {t("map.criticalBanner", {
                    count: criticalTigers.length,
                    plural: criticalTigers.length > 1 ? "s" : "",
                  })}
                </span>
              </div>
            )}
          </div>
        }
      />

      <div className="px-6 py-4 sm:px-8 sm:py-5">
        <div className="mb-3.5 flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-1.5 rounded-xl border border-border bg-surface p-1.5">
            {LAYER_CONFIG.map(({ key, labelKey }) => {
              const active = layers[key];
              return (
                <button
                  key={key}
                  onClick={() => toggleLayer(key)}
                  className={`flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-medium transition-all ${
                    active
                      ? "bg-accent text-accent-foreground"
                      : "text-muted hover:bg-surface-sunken hover:text-foreground"
                  }`}
                >
                  {active ? <CheckSquare size={13} weight="fill" /> : <Square size={13} />}
                  {t(labelKey)}
                </button>
              );
            })}
          </div>

          <div className="relative">
            <MagnifyingGlass size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("map.searchPlaceholder")}
              className="w-56 rounded-xl border border-border bg-surface py-1.5 pl-9 pr-4 text-xs text-foreground placeholder:text-muted focus:border-accent focus:outline-none sm:w-64"
            />
            {searchResults.length > 0 && (
              <div className="absolute right-0 top-10 z-50 w-64 overflow-hidden rounded-xl border border-border bg-surface shadow-2xl">
                {searchResults.map((res) => (
                  <button
                    key={res.tiger_id}
                    onClick={() => {
                      setSelectedTigerId(res.tiger_id);
                      setSearchQuery("");
                    }}
                    className="flex w-full items-center justify-between px-4 py-2.5 text-left text-sm hover:bg-surface-sunken"
                  >
                    <span className="font-mono text-foreground">{res.tiger_id}</span>
                    <ArrowRight size={13} className="text-muted" />
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        <div className="relative h-[calc(100vh-210px)] min-h-140 w-full">
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

          {selectedTigerId && (
            <div className="pointer-events-auto absolute top-3.5 left-1/2 z-[1000] -translate-x-1/2 flex items-center gap-3 rounded-2xl border border-white/20 bg-zinc-950/90 px-4 py-2 shadow-2xl backdrop-blur-md">
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
                    {t("map.layerTerritories") || "Territory"}
                  </div>
                </div>
              </div>
              <div className="h-5 w-px bg-white/15" />
              <div className="flex items-center gap-2">
                <button
                  onClick={() => onOpenTiger(selectedTigerId)}
                  className="flex items-center gap-1.5 rounded-xl bg-emerald-500 hover:bg-emerald-400 px-3.5 py-1.5 text-xs font-semibold text-zinc-950 transition-all shadow-md active:scale-95"
                >
                  <span>{t("map.openDossier")}</span>
                  <ArrowRight size={13} weight="bold" />
                </button>
                <button
                  onClick={() => setSelectedTigerId(null)}
                  className="flex h-7 w-7 items-center justify-center rounded-xl border border-white/15 bg-white/5 text-zinc-300 hover:bg-white/15 hover:text-white transition-all text-xs"
                  title={t("common.close")}
                >
                  ✕
                </button>
              </div>
            </div>
          )}

          {selectedStation && !uploadStation && (
            <div className="pointer-events-auto absolute top-3.5 left-1/2 z-[1000] -translate-x-1/2 flex items-center gap-3 rounded-2xl border border-white/20 bg-zinc-950/90 px-4 py-2 shadow-2xl backdrop-blur-md">
              <div className="flex items-center gap-2.5">
                <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-emerald-500/20 text-emerald-400">
                  <Camera size={18} weight="fill" />
                </span>
                <div>
                  <div className="font-mono text-sm font-bold text-white tracking-wide">{selectedStation.camera_id}</div>
                  <div className="text-[11px] text-zinc-400">
                    {selectedStation.zone} — {selectedStation.sub_region || t("common.unknownRange")}
                  </div>
                </div>
              </div>
              <div className="h-5 w-px bg-white/15" />
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setUploadStation(selectedStation)}
                  className="flex items-center gap-1.5 rounded-xl bg-emerald-500 hover:bg-emerald-400 px-3.5 py-1.5 text-xs font-semibold text-zinc-950 transition-all shadow-md active:scale-95"
                >
                  <span>{t("map.uploadCaptureHere")}</span>
                </button>
                <button
                  onClick={() => setSelectedStation(null)}
                  className="flex h-7 w-7 items-center justify-center rounded-xl border border-white/15 bg-white/5 text-zinc-300 hover:bg-white/15 hover:text-white transition-all text-xs"
                  title={t("common.close")}
                >
                  ✕
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {uploadStation && (
        <StationUploadPanel station={uploadStation} onClose={() => setUploadStation(null)} />
      )}
    </div>
  );
}

function MapLoadingFallback() {
  const { t } = useLanguage();
  return (
    <div className="flex h-full min-h-140 w-full items-center justify-center rounded-2xl border border-zinc-800 bg-zinc-950 text-muted font-mono text-sm">
      <div className="flex flex-col items-center gap-3">
        <div className="h-7 w-7 animate-spin rounded-full border-2 border-emerald-500 border-t-transparent" />
        <span className="text-zinc-300">{t("map.loadingMap")}</span>
      </div>
    </div>
  );
}

function StatChip({ icon: Icon, label, value }: { icon: typeof PawPrint; label: string; value: number }) {
  return (
    <div className="flex items-center gap-2 rounded-xl border border-border bg-surface px-3 py-1.5 shadow-2xs">
      <Icon size={15} className="text-accent shrink-0" />
      <div className="leading-tight">
        <div className="text-[10px] uppercase font-mono text-muted tracking-wider">{label}</div>
        <div className="text-xs font-bold font-mono text-foreground">{value}</div>
      </div>
    </div>
  );
}
