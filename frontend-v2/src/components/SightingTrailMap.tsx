"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Plus, X, DownloadSimple, Spinner } from "@phosphor-icons/react";
import { api, type GISMapBundle } from "@/lib/api";

export interface TrailPoint {
  latitude?: number;
  longitude?: number;
  timestamp: string | null;
  station?: string | null;
  camera_id?: string | null;
  alert_level?: string;
}

type LeafletMap = import("leaflet").Map;
type LeafletLayerGroup = import("leaflet").LayerGroup;

const ALERT_COLORS: Record<string, string> = {
  SAFE: "#10b981",
  CAUTION: "#f59e0b",
  CRITICAL: "#ef4444",
};

const COMPARE_PALETTE = [
  "#38bdf8", // sky
  "#f472b6", // pink
  "#facc15", // yellow
  "#a78bfa", // violet
  "#fb923c", // orange
  "#4ade80", // green
];

function colorForIndex(i: number) {
  return COMPARE_PALETTE[i % COMPARE_PALETTE.length];
}

function distKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const dlat = (lat2 - lat1) * 111.0;
  const dlon = (lon2 - lon1) * 103.0;
  return Math.sqrt(dlat * dlat + dlon * dlon);
}

// SAT overlap test for two convex polygons (MCP territories are convex
// hulls by definition). Boolean intersection is preserved under any
// consistent coordinate system, so raw [lat, lon] pairs work fine here.
function edgeNormals(poly: [number, number][]): [number, number][] {
  const normals: [number, number][] = [];
  for (let i = 0; i < poly.length; i++) {
    const [x1, y1] = poly[i];
    const [x2, y2] = poly[(i + 1) % poly.length];
    normals.push([-(y2 - y1), x2 - x1]);
  }
  return normals;
}
function projectPolygon(poly: [number, number][], axis: [number, number]): [number, number] {
  let min = Infinity;
  let max = -Infinity;
  for (const [x, y] of poly) {
    const d = x * axis[0] + y * axis[1];
    if (d < min) min = d;
    if (d > max) max = d;
  }
  return [min, max];
}
function convexPolygonsOverlap(a: [number, number][], b: [number, number][]): boolean {
  if (a.length < 3 || b.length < 3) return false;
  for (const axis of [...edgeNormals(a), ...edgeNormals(b)]) {
    const [minA, maxA] = projectPolygon(a, axis);
    const [minB, maxB] = projectPolygon(b, axis);
    if (maxA < minB || maxB < minA) return false;
  }
  return true;
}

interface TigerLayer {
  tigerId: string;
  points: TrailPoint[];
  color: string;
  isPrimary: boolean;
}

interface CircleTerritory {
  tigerId: string;
  color: string;
  center: [number, number];
  radiusKm: number;
}

function computeCircleTerritory(tigerId: string, color: string, points: TrailPoint[]): CircleTerritory | null {
  const valid = points.filter(
    (p): p is TrailPoint & { latitude: number; longitude: number } =>
      typeof p.latitude === "number" && typeof p.longitude === "number"
  );
  if (valid.length === 0) return null;
  const avgLat = valid.reduce((sum, p) => sum + p.latitude, 0) / valid.length;
  const avgLon = valid.reduce((sum, p) => sum + p.longitude, 0) / valid.length;
  const maxDistKm = Math.max(...valid.map((p) => distKm(avgLat, avgLon, p.latitude, p.longitude)), 0);
  const radiusKm = Math.max(1.5, maxDistKm * 1.15);
  return { tigerId, color, center: [avgLat, avgLon], radiusKm };
}

/**
 * Leaflet map for a tiger's sighting trail. Renders the primary tiger's
 * (windowed) trail plus any additional tigers added via "Add Tiger" for
 * side-by-side territory comparison, and supports exporting the rendered
 * map (trails + territory legend) as a PNG.
 */
export function SightingTrailMap({ points, tigerId }: { points: TrailPoint[]; tigerId: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const captureRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const layerRef = useRef<LeafletLayerGroup | null>(null);
  const [mapReady, setMapReady] = useState(false);

  const [compared, setCompared] = useState<{ tigerId: string; points: TrailPoint[] }[]>([]);
  const [loadingTiger, setLoadingTiger] = useState<string | null>(null);
  const [addError, setAddError] = useState<string | null>(null);

  const [pickerOpen, setPickerOpen] = useState(false);
  const [allTigerIds, setAllTigerIds] = useState<string[] | null>(null);
  const [pickerQuery, setPickerQuery] = useState("");
  const pickerRef = useRef<HTMLDivElement>(null);

  const [exporting, setExporting] = useState(false);

  // Real MCP territory polygons (same source as the Reserve Map) — used to
  // draw accurately-positioned, non-inflated territory shapes for compared
  // tigers and to answer "do these territories merge" precisely.
  const [gisBundle, setGisBundle] = useState<GISMapBundle | null>(null);
  useEffect(() => {
    api.gisBundle().then(setGisBundle).catch(() => {});
  }, []);

  useEffect(() => {
    if (typeof window === "undefined" || !containerRef.current) return;
    let isMounted = true;

    import("leaflet").then((leafletModule) => {
      if (!isMounted || !containerRef.current) return;
      const L = leafletModule.default || leafletModule;

      if (!mapRef.current) {
        const map = L.map(containerRef.current, {
          center: [21.65, 79.25],
          zoom: 12,
          zoomControl: false,
          attributionControl: false,
        });
        L.control.zoom({ position: "topright" }).addTo(map);
        L.tileLayer("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", {
          attribution: "Tiles &copy; Esri",
          maxZoom: 19,
          crossOrigin: true,
        }).addTo(map);

        layerRef.current = L.layerGroup().addTo(map);
        mapRef.current = map;
        setMapReady(true);
      }
    });

    return () => {
      isMounted = false;
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        setMapReady(false);
      }
    };
  }, []);

  // Close the picker on outside click.
  useEffect(() => {
    if (!pickerOpen) return;
    function onClick(e: MouseEvent) {
      if (pickerRef.current && !pickerRef.current.contains(e.target as Node)) {
        setPickerOpen(false);
      }
    }
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, [pickerOpen]);

  // Camera stations are fixed, surveyed points already plotted on the
  // Reserve Map — anchor each sighting to its station's coordinates rather
  // than the capture's own (often noisy/defaulted) lat/lon, so tiger
  // movement is plotted against the same real station network.
  const stationCoords = useMemo(() => {
    const map = new Map<string, [number, number]>();
    for (const s of gisBundle?.stations || []) map.set(s.camera_id, [s.latitude, s.longitude]);
    return map;
  }, [gisBundle]);

  const resolvePoints = (pts: TrailPoint[]): TrailPoint[] =>
    pts.map((p) => {
      const camId = p.camera_id || p.station;
      const stationPos = camId ? stationCoords.get(camId) : undefined;
      return stationPos ? { ...p, latitude: stationPos[0], longitude: stationPos[1] } : p;
    });

  const layers: TigerLayer[] = useMemo(() => {
    const result: TigerLayer[] = [{ tigerId, points: resolvePoints(points), color: "#ffffff", isPrimary: true }];
    compared.forEach((c, i) => {
      result.push({ tigerId: c.tigerId, points: resolvePoints(c.points), color: colorForIndex(i), isPrimary: false });
    });
    return result;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tigerId, points, compared, stationCoords]);

  const overlaps = useMemo(() => {
    const pairs: { a: string; b: string; overlapping: boolean }[] = [];
    for (let i = 0; i < layers.length; i++) {
      for (let j = i + 1; j < layers.length; j++) {
        const layerA = layers[i];
        const layerB = layers[j];
        const polyA = gisBundle?.territories?.[layerA.tigerId]?.polygon;
        const polyB = gisBundle?.territories?.[layerB.tigerId]?.polygon;
        let overlapping: boolean;
        if (polyA && polyB) {
          overlapping = convexPolygonsOverlap(polyA, polyB);
        } else {
          const ca = computeCircleTerritory(layerA.tigerId, "", layerA.points);
          const cb = computeCircleTerritory(layerB.tigerId, "", layerB.points);
          overlapping = !!ca && !!cb && distKm(ca.center[0], ca.center[1], cb.center[0], cb.center[1]) < ca.radiusKm + cb.radiusKm;
        }
        pairs.push({ a: layerA.tigerId, b: layerB.tigerId, overlapping });
      }
    }
    return pairs;
  }, [layers, gisBundle]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;

    import("leaflet").then((leafletModule) => {
      const L = leafletModule.default || leafletModule;
      const currentMap = mapRef.current;
      if (!currentMap || !layerRef.current) return;

      layerRef.current.clearLayers();

      const allValidPoints: [number, number][] = [];

      for (const layer of layers) {
        const valid = layer.points.filter(
          (p): p is TrailPoint & { latitude: number; longitude: number } =>
            typeof p.latitude === "number" && typeof p.longitude === "number"
        );
        if (valid.length === 0) continue;
        valid.forEach((p) => allValidPoints.push([p.latitude, p.longitude]));

        // Territory shape: prefer the real MCP polygon (same accurate,
        // fixed boundary the Reserve Map draws) over an approximated
        // circle, which only kicks in when a tiger has no GIS entry.
        const gisTerritory = gisBundle?.territories?.[layer.tigerId];
        if (gisTerritory?.polygon?.length) {
          const poly = L.polygon(gisTerritory.polygon, {
            color: layer.isPrimary ? "#f59e0b" : layer.color,
            weight: layer.isPrimary ? 1.8 : 2,
            dashArray: layer.isPrimary ? "6, 8" : undefined,
            fillColor: layer.isPrimary ? "#f59e0b" : layer.color,
            fillOpacity: layer.isPrimary ? 0.05 : 0.1,
          });
          poly.bindTooltip(
            `<strong>Tiger ${layer.tigerId} Territory</strong><br>100% MCP: ${gisTerritory.area_km2} km²`,
            { sticky: true, className: "gis-map-tooltip" }
          );
          layerRef.current!.addLayer(poly);
        } else {
          const fallback = computeCircleTerritory(layer.tigerId, layer.color, valid);
          if (fallback) {
            const circle = L.circle(fallback.center, {
              radius: fallback.radiusKm * 1000,
              color: layer.isPrimary ? "#f59e0b" : layer.color,
              weight: 1.8,
              dashArray: "6, 8",
              fillColor: layer.isPrimary ? "#f59e0b" : layer.color,
              fillOpacity: 0.05,
            });
            circle.bindTooltip(
              `<strong>Tiger ${layer.tigerId} Territory (est.)</strong><br>~${(Math.PI * fallback.radiusKm * fallback.radiusKm).toFixed(1)} km²`,
              { sticky: true, className: "gis-map-tooltip" }
            );
            layerRef.current!.addLayer(circle);
          }
        }

        const ordered = [...valid].reverse();

        if (ordered.length > 1) {
          const line = L.polyline(
            ordered.map((p) => [p.latitude, p.longitude]),
            layer.isPrimary
              ? { color: "#ffffff", weight: 1.5, dashArray: "4, 8", opacity: 0.75 }
              : { color: layer.color, weight: 2, opacity: 0.85 }
          );
          layerRef.current!.addLayer(line);
        }

        if (layer.isPrimary) {
          // Primary tiger keeps the detailed numbered-pin trail.
          ordered.forEach((p, i) => {
            const isLatest = i === ordered.length - 1;
            const markerColor = ALERT_COLORS[p.alert_level || "SAFE"] || ALERT_COLORS.SAFE;
            const icon = L.divIcon({
              className: "custom-trail-icon",
              html: `<div style="
                width:20px;height:20px;border-radius:50%;
                display:flex;align-items:center;justify-content:center;
                font-family:ui-monospace,monospace;font-size:10px;font-weight:700;
                background:${isLatest ? markerColor : "rgba(9,9,11,0.85)"};
                color:${isLatest ? "#fff" : "#e4e4e7"};
                border:2px solid ${isLatest ? "#fff" : markerColor};
                transform:${isLatest ? "scale(1.2)" : "scale(1)"};
              ">${i + 1}</div>`,
              iconSize: [20, 20],
              iconAnchor: [10, 10],
            });
            const marker = L.marker([p.latitude, p.longitude], { icon });
            marker.bindPopup(
              `<div style="font-family: ui-monospace, monospace; font-size: 11px;">
                <b>${layer.tigerId} &middot; ${p.camera_id || p.station || "Unknown station"}</b><br>
                ${p.timestamp ? new Date(p.timestamp).toLocaleString() : "Unknown time"}<br>
                <span style="color:${markerColor}">${p.alert_level || "SAFE"}</span>
              </div>`,
              { className: "gis-map-tooltip" }
            );
            layerRef.current!.addLayer(marker);
          });
        } else {
          // Compared tigers: small dots (not giant numbered pins) so
          // overlapping trails around shared stations stay legible.
          ordered.forEach((p, i) => {
            const marker = L.circleMarker([p.latitude, p.longitude], {
              radius: i === ordered.length - 1 ? 6 : 4,
              color: "#ffffff",
              weight: 1.2,
              fillColor: layer.color,
              fillOpacity: 0.9,
            });
            marker.bindPopup(
              `<div style="font-family: ui-monospace, monospace; font-size: 11px;">
                <b>${layer.tigerId} &middot; ${p.camera_id || p.station || "Unknown station"}</b><br>
                ${p.timestamp ? new Date(p.timestamp).toLocaleString() : "Unknown time"}
              </div>`,
              { className: "gis-map-tooltip" }
            );
            layerRef.current!.addLayer(marker);
          });
        }
      }

      if (allValidPoints.length > 0) {
        const bounds = L.latLngBounds(allValidPoints);
        currentMap.flyToBounds(bounds.pad(0.35), { duration: 0.6 });
      }
    });
  }, [layers, gisBundle, mapReady]);

  async function openPicker() {
    setAddError(null);
    setPickerOpen((v) => !v);
    if (!allTigerIds) {
      try {
        const res = await api.gallery();
        setAllTigerIds(res.individuals.map((i) => i.tiger_id).sort());
      } catch {
        setAddError("Couldn't load tiger list.");
      }
    }
  }

  async function addTiger(id: string) {
    setPickerOpen(false);
    setPickerQuery("");
    setAddError(null);
    setLoadingTiger(id);
    try {
      const detail = await api.galleryDetail(id);
      const pts: TrailPoint[] = (detail.captures || []).map((c) => ({
        latitude: c.latitude,
        longitude: c.longitude,
        timestamp: c.timestamp,
        station: c.station,
        camera_id: c.camera_id,
        alert_level: c.alert_level,
      }));
      if (!pts.some((p) => typeof p.latitude === "number" && typeof p.longitude === "number")) {
        setAddError(`${id} has no located sightings to plot.`);
        setLoadingTiger(null);
        return;
      }
      setCompared((prev) => [...prev.filter((c) => c.tigerId !== id), { tigerId: id, points: pts }]);
    } catch {
      setAddError(`Couldn't load ${id}.`);
    } finally {
      setLoadingTiger(null);
    }
  }

  function removeTiger(id: string) {
    setCompared((prev) => prev.filter((c) => c.tigerId !== id));
  }

  async function handleExport() {
    if (!captureRef.current || exporting) return;
    setExporting(true);
    try {
      const html2canvas = (await import("html2canvas")).default;
      const canvas = await html2canvas(captureRef.current, {
        useCORS: true,
        backgroundColor: "#09090b",
        scale: 2,
      });
      const link = document.createElement("a");
      const ids = layers.map((l) => l.tigerId).join("_");
      link.download = `tiger-territory-map_${ids}_${Date.now()}.png`;
      link.href = canvas.toDataURL("image/png");
      link.click();
    } catch (err) {
      console.error("Trail map export failed:", err);
      setAddError("Export failed. Try again.");
    } finally {
      setExporting(false);
    }
  }

  const availableToAdd = useMemo(() => {
    if (!allTigerIds) return [];
    const excluded = new Set([tigerId, ...compared.map((c) => c.tigerId)]);
    return allTigerIds
      .filter((id) => !excluded.has(id))
      .filter((id) => id.toLowerCase().includes(pickerQuery.toLowerCase()));
  }, [allTigerIds, tigerId, compared, pickerQuery]);

  return (
    <div className="relative h-90 w-full overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl">
      <div className="absolute inset-x-0 top-0 z-[1000] flex flex-wrap items-center gap-1.5 border-b border-zinc-800 bg-zinc-950/90 px-2.5 py-2 backdrop-blur-md">
        <span className="flex items-center gap-1.5 rounded-full bg-zinc-900 px-2.5 py-1 text-2xs font-mono font-bold text-white ring-1 ring-white/30">
          <span className="h-2 w-2 rounded-full bg-white" />
          {tigerId}
        </span>

        {compared.map((c, i) => (
          <span
            key={c.tigerId}
            className="flex items-center gap-1.5 rounded-full bg-zinc-900 px-2.5 py-1 text-2xs font-mono font-bold text-white"
            style={{ boxShadow: `inset 0 0 0 1px ${colorForIndex(i)}66` }}
          >
            <span className="h-2 w-2 rounded-full" style={{ backgroundColor: colorForIndex(i) }} />
            {c.tigerId}
            <button
              onClick={() => removeTiger(c.tigerId)}
              className="ml-0.5 rounded-full p-0.5 text-zinc-400 hover:bg-zinc-800 hover:text-white"
              aria-label={`Remove ${c.tigerId}`}
            >
              <X size={10} weight="bold" />
            </button>
          </span>
        ))}

        {loadingTiger && (
          <span className="flex items-center gap-1.5 rounded-full bg-zinc-900 px-2.5 py-1 text-2xs font-mono text-zinc-400">
            <Spinner size={10} className="animate-spin" />
            {loadingTiger}
          </span>
        )}

        <div className="relative" ref={pickerRef}>
          <button
            onClick={openPicker}
            className="flex items-center gap-1 rounded-full border border-dashed border-zinc-700 px-2.5 py-1 text-2xs font-mono font-bold text-zinc-300 hover:border-zinc-500 hover:text-white"
          >
            <Plus size={11} weight="bold" />
            Add Tiger
          </button>

          {pickerOpen && (
            <div className="absolute left-0 top-full z-[1001] mt-1.5 w-56 overflow-hidden rounded-lg border border-zinc-800 bg-zinc-900 shadow-2xl">
              <input
                autoFocus
                value={pickerQuery}
                onChange={(e) => setPickerQuery(e.target.value)}
                placeholder="Search tiger ID…"
                className="w-full border-b border-zinc-800 bg-zinc-900 px-2.5 py-1.5 text-2xs font-mono text-white placeholder:text-zinc-500 focus:outline-none"
              />
              <div className="max-h-48 overflow-y-auto">
                {allTigerIds === null ? (
                  <div className="px-2.5 py-2 text-2xs font-mono text-zinc-500">Loading…</div>
                ) : availableToAdd.length === 0 ? (
                  <div className="px-2.5 py-2 text-2xs font-mono text-zinc-500">No matches</div>
                ) : (
                  availableToAdd.map((id) => (
                    <button
                      key={id}
                      onClick={() => addTiger(id)}
                      className="block w-full px-2.5 py-1.5 text-left text-2xs font-mono text-zinc-200 hover:bg-zinc-800"
                    >
                      {id}
                    </button>
                  ))
                )}
              </div>
            </div>
          )}
        </div>

        <div className="ml-auto flex items-center gap-1.5">
          <button
            onClick={handleExport}
            disabled={exporting}
            className="flex items-center gap-1.5 rounded-full bg-white px-2.5 py-1 text-2xs font-mono font-bold text-zinc-950 hover:bg-zinc-200 disabled:opacity-60"
          >
            {exporting ? <Spinner size={11} className="animate-spin" /> : <DownloadSimple size={11} weight="bold" />}
            Export
          </button>
        </div>
      </div>

      {addError && (
        <div className="absolute left-2.5 top-[42px] z-[1000] rounded-md bg-red-950/90 px-2 py-1 text-2xs font-mono text-red-300 shadow-lg">
          {addError}
        </div>
      )}

      {overlaps.length > 0 && (
        <div className="absolute bottom-2 right-2 z-[1000] max-h-32 w-44 space-y-1 overflow-y-auto rounded-md bg-zinc-950/85 p-1.5 shadow-lg backdrop-blur-md">
          {overlaps.map((o) => (
            <div
              key={`${o.a}-${o.b}`}
              className={`rounded px-1.5 py-1 text-[10px] font-mono font-bold leading-tight ${
                o.overlapping ? "bg-amber-950/80 text-amber-300" : "bg-zinc-900/80 text-zinc-500"
              }`}
            >
              <div className="truncate">{o.a} ↔ {o.b}</div>
              <div>{o.overlapping ? "⚠ territories merge" : "separate"}</div>
            </div>
          ))}
        </div>
      )}

      <div ref={captureRef} className="absolute inset-0">
        <div ref={containerRef} className="h-full w-full z-0" />

        {layers.length > 1 && (
          <div
            className="pointer-events-none absolute bottom-2 left-2 z-[999] rounded-md px-2.5 py-1.5 text-2xs font-mono shadow-lg backdrop-blur-md"
            style={{ backgroundColor: "rgba(9,9,11,0.85)", color: "#ffffff" }}
          >
            <div className="mb-1 font-bold" style={{ color: "#d4d4d8" }}>Territory comparison</div>
            {layers.map((l, i) => (
              <div key={l.tigerId} className="flex items-center gap-1.5">
                <span
                  className="h-2 w-2 rounded-full"
                  style={{ backgroundColor: l.isPrimary ? "#ffffff" : colorForIndex(i - 1) }}
                />
                <span>{l.tigerId}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
