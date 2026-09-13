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
    loading: () => (
      <div className="flex h-full min-h-140 w-full items-center justify-center rounded-2xl border border-zinc-800 bg-zinc-950 text-muted font-mono text-sm">
        <div className="flex flex-col items-center gap-3">
          <div className="h-7 w-7 animate-spin rounded-full border-2 border-emerald-500 border-t-transparent" />
          <span className="text-zinc-300">Loading satellite view...</span>
        </div>
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
  { key: "subregions", label: "Ranges" },
];

export function ReserveMapView({
  onOpenTiger,
  stats,
}: {
  onOpenTiger: (tigerId: string) => void;
  stats: Stats | null;
}) {
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
        results.push({ tiger_id: s.tiger_id, reason: s.threat_reason || "Near a village boundary" });
      }
    }
    return results;
  }, [bundle]);

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
        title="Reserve Map"
        subtitle="Live tiger positions, camera network, and zone status across Pench"
        alertCount={stats?.pending_review ?? 0}
      />

      <div className="px-6 py-5 sm:px-8">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <StatChip icon={PawPrint} label="Tigers" value={bundle?.metadata.total_tigers ?? 44} />
            <StatChip icon={Camera} label="Cameras" value={bundle?.metadata.total_stations ?? 313} />
            <StatChip icon={House} label="Villages" value={bundle?.metadata.total_villages ?? 44} />
            {criticalTigers.length > 0 && (
              <div className="flex items-center gap-2 rounded-xl border border-danger/40 bg-danger-soft px-3.5 py-2 text-danger">
                <WarningCircle size={16} weight="fill" />
                <span className="text-xs font-semibold">
                  {criticalTigers.length} tiger{criticalTigers.length > 1 ? "s" : ""} near village boundary
                </span>
              </div>
            )}
          </div>

          <div className="relative">
            <MagnifyingGlass size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Find a tiger..."
              className="w-56 rounded-full border border-border bg-surface py-2 pl-9 pr-4 text-sm text-foreground placeholder:text-muted focus:border-accent focus:outline-none"
            />
            {searchResults.length > 0 && (
              <div className="absolute right-0 top-11 z-50 w-64 overflow-hidden rounded-xl border border-border bg-surface shadow-2xl">
                {searchResults.map((t) => (
                  <button
                    key={t.tiger_id}
                    onClick={() => {
                      setSelectedTigerId(t.tiger_id);
                      setSearchQuery("");
                    }}
                    className="flex w-full items-center justify-between px-4 py-2.5 text-left text-sm hover:bg-surface-sunken"
                  >
                    <span className="font-mono text-foreground">{t.tiger_id}</span>
                    <ArrowRight size={13} className="text-muted" />
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        <div className="mb-4 flex flex-wrap items-center gap-1.5 rounded-xl border border-border bg-surface p-1.5">
          {LAYER_CONFIG.map(({ key, label }) => {
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
                {label}
              </button>
            );
          })}
        </div>

        <div className="h-140 w-full">
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
        </div>

        {selectedStation && !uploadStation && (
          <div className="mt-4 flex items-center justify-between rounded-xl border border-border bg-surface p-4">
            <div>
              <div className="font-mono text-xs text-muted">{selectedStation.camera_id}</div>
              <div className="text-sm text-foreground">
                {selectedStation.zone} — {selectedStation.sub_region || "Unknown range"} — {selectedStation.operational_status}
              </div>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setUploadStation(selectedStation)}
                className="rounded-full bg-accent px-3.5 py-1.5 text-xs font-medium text-accent-foreground hover:opacity-90"
              >
                Upload capture here
              </button>
              <button
                onClick={() => setSelectedStation(null)}
                className="rounded-full border border-border-strong px-3.5 py-1.5 text-xs font-medium text-foreground hover:bg-surface-sunken"
              >
                Close
              </button>
            </div>
          </div>
        )}

        {selectedTigerId && (
          <div className="mt-4 flex items-center justify-between rounded-xl border border-border bg-surface p-4">
            <div className="font-mono text-sm text-foreground">{selectedTigerId}</div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => onOpenTiger(selectedTigerId)}
                className="flex items-center gap-1.5 rounded-full bg-accent px-3.5 py-1.5 text-xs font-medium text-accent-foreground hover:opacity-90"
              >
                Open dossier
                <ArrowRight size={12} />
              </button>
              <button
                onClick={() => setSelectedTigerId(null)}
                className="rounded-full border border-border-strong px-3.5 py-1.5 text-xs font-medium text-foreground hover:bg-surface-sunken"
              >
                Close
              </button>
            </div>
          </div>
        )}
      </div>

      {uploadStation && (
        <StationUploadPanel station={uploadStation} onClose={() => setUploadStation(null)} />
      )}
    </div>
  );
}

function StatChip({ icon: Icon, label, value }: { icon: typeof PawPrint; label: string; value: number }) {
  return (
    <div className="flex items-center gap-2 rounded-xl border border-border bg-surface px-3.5 py-2">
      <Icon size={16} className="text-accent" />
      <div>
        <div className="text-[10px] uppercase font-mono text-muted">{label}</div>
        <div className="text-xs font-bold text-foreground">{value}</div>
      </div>
    </div>
  );
}
