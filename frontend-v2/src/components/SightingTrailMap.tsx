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
type LeafletTileLayer = import("leaflet").TileLayer;

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
  "#f87171", // red
  "#22d3ee", // cyan
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

// Minimum convex polygon (100% MCP) via Andrew's monotone chain — the
// actual boundary connecting a tiger's outermost real sighting locations,
// as opposed to a synthetic/estimated shape.
function convexHull(points: [number, number][]): [number, number][] {
  const unique = Array.from(new Map(points.map((p) => [`${p[0]},${p[1]}`, p])).values()).sort(
    (a, b) => a[0] - b[0] || a[1] - b[1]
  );
  if (unique.length < 3) return unique;
  const cross = (o: [number, number], a: [number, number], b: [number, number]) =>
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lower: [number, number][] = [];
  for (const p of unique) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) lower.pop();
    lower.push(p);
  }
  const upper: [number, number][] = [];
  for (let i = unique.length - 1; i >= 0; i--) {
    const p = unique[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) upper.pop();
    upper.push(p);
  }
  lower.pop();
  upper.pop();
  return lower.concat(upper);
}

// Shoelace formula over a local equirectangular projection (same
// lat/lon-to-km scale factors used by distKm above).
function polygonAreaKm2(hull: [number, number][]): number {
  if (hull.length < 3) return 0;
  const [originLat, originLon] = hull[0];
  const proj = hull.map(([lat, lon]): [number, number] => [(lon - originLon) * 103.0, (lat - originLat) * 111.0]);
  let area = 0;
  for (let i = 0; i < proj.length; i++) {
    const [x1, y1] = proj[i];
    const [x2, y2] = proj[(i + 1) % proj.length];
    area += x1 * y2 - x2 * y1;
  }
  return Math.abs(area) / 2;
}

interface Territory {
  kind: "polygon" | "circle";
  polygon?: [number, number][];
  center?: [number, number];
  radiusKm?: number;
  areaKm2: number;
}

// A tiger's territory is traced directly from its own real sighting
// locations (the actual path it traced), not any pre-baked shape — a
// convex hull when there are enough distinct fixes, otherwise a small
// estimated circle around them.
function computeTerritory(tigerId: string, color: string, points: TrailPoint[]): Territory | null {
  const valid = points.filter(
    (p): p is TrailPoint & { latitude: number; longitude: number } =>
      typeof p.latitude === "number" && typeof p.longitude === "number"
  );
  if (valid.length === 0) return null;
  const hull = convexHull(valid.map((p): [number, number] => [p.latitude, p.longitude]));
  if (hull.length >= 3) {
    return { kind: "polygon", polygon: hull, areaKm2: polygonAreaKm2(hull) };
  }
  const circle = computeCircleTerritory(tigerId, color, points);
  if (!circle) return null;
  return { kind: "circle", center: circle.center, radiusKm: circle.radiusKm, areaKm2: Math.PI * circle.radiusKm * circle.radiusKm };
}

const ARCGIS_SATELLITE_URL =
  "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}";

/**
 * Leaflet map for a tiger's sighting trail. In single-tiger mode it renders
 * the satellite basemap with a numbered, per-camera-station pin trail. As
 * soon as a second tiger is added for comparison, it switches to a clean
 * reserve-boundary basemap (Core/Buffer zones) with colored territory
 * outlines and direct labels — matching the department's static MCP
 * territory reports — since per-station pins for several tigers at once
 * stop being legible. Supports exporting the rendered map as a PNG.
 */
export function SightingTrailMap({ points, tigerId }: { points: TrailPoint[]; tigerId: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const captureRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const layerRef = useRef<LeafletLayerGroup | null>(null);
  const tileLayerRef = useRef<LeafletTileLayer | null>(null);
  const boundaryLayerRef = useRef<LeafletLayerGroup | null>(null);
  const [mapReady, setMapReady] = useState(false);

  const [compared, setCompared] = useState<{ tigerId: string; points: TrailPoint[] }[]>([]);
  const [loadingTiger, setLoadingTiger] = useState<string | null>(null);
  const [addError, setAddError] = useState<string | null>(null);

  const [pickerOpen, setPickerOpen] = useState(false);
  const [allTigerIds, setAllTigerIds] = useState<string[] | null>(null);
  const [pickerQuery, setPickerQuery] = useState("");
  const pickerRef = useRef<HTMLDivElement>(null);

  const [exporting, setExporting] = useState(false);

  // Comparing two or more tigers switches the whole map to the clean
  // boundary + territory-outline report style (see doc comment above).
  const compareMode = compared.length > 0;

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
        L.control.scale({ position: "bottomleft", imperial: false, maxWidth: 100 }).addTo(map);

        tileLayerRef.current = L.tileLayer(ARCGIS_SATELLITE_URL, {
          attribution: "Tiles &copy; Esri",
          maxZoom: 19,
          crossOrigin: true,
        }).addTo(map);

        layerRef.current = L.layerGroup().addTo(map);
        boundaryLayerRef.current = L.layerGroup();
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
    const result: TigerLayer[] = [
      { tigerId, points: resolvePoints(points), color: colorForIndex(0), isPrimary: true },
    ];
    compared.forEach((c, i) => {
      result.push({ tigerId: c.tigerId, points: resolvePoints(c.points), color: colorForIndex(i + 1), isPrimary: false });
    });
    return result;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tigerId, points, compared, stationCoords]);

  // Each tiger's territory is traced from its own real sighting locations
  // — see computeTerritory's doc comment.
  const territoryByTiger = useMemo(() => {
    const map = new Map<string, Territory>();
    for (const layer of layers) {
      const territory = computeTerritory(layer.tigerId, layer.color, layer.points);
      if (territory) map.set(layer.tigerId, territory);
    }
    return map;
  }, [layers]);

  function territoryCenter(t: Territory): [number, number] | null {
    if (t.kind === "circle") return t.center ?? null;
    if (!t.polygon?.length) return null;
    const lat = t.polygon.reduce((sum, p) => sum + p[0], 0) / t.polygon.length;
    const lon = t.polygon.reduce((sum, p) => sum + p[1], 0) / t.polygon.length;
    return [lat, lon];
  }

  function territoryRadiusKm(t: Territory): number {
    if (t.kind === "circle") return t.radiusKm ?? 0;
    return Math.sqrt(t.areaKm2 / Math.PI);
  }

  const overlaps = useMemo(() => {
    const pairs: { a: string; b: string; overlapping: boolean }[] = [];
    for (let i = 0; i < layers.length; i++) {
      for (let j = i + 1; j < layers.length; j++) {
        const layerA = layers[i];
        const layerB = layers[j];
        const tA = territoryByTiger.get(layerA.tigerId);
        const tB = territoryByTiger.get(layerB.tigerId);
        let overlapping = false;
        if (tA?.kind === "polygon" && tB?.kind === "polygon" && tA.polygon && tB.polygon) {
          overlapping = convexPolygonsOverlap(tA.polygon, tB.polygon);
        } else if (tA && tB) {
          const ca = territoryCenter(tA);
          const cb = territoryCenter(tB);
          overlapping = !!ca && !!cb && distKm(ca[0], ca[1], cb[0], cb[1]) < territoryRadiusKm(tA) + territoryRadiusKm(tB);
        }
        pairs.push({ a: layerA.tigerId, b: layerB.tigerId, overlapping });
      }
    }
    return pairs;
  }, [layers, territoryByTiger]);

  // Swap the basemap: satellite tiles for a single tiger, a plain
  // Core/Buffer boundary basemap once comparing — see doc comment above.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;

    import("leaflet").then((leafletModule) => {
      const L = leafletModule.default || leafletModule;
      const currentMap = mapRef.current;
      const tile = tileLayerRef.current;
      const boundary = boundaryLayerRef.current;
      if (!currentMap || !tile || !boundary) return;

      if (compareMode) {
        if (currentMap.hasLayer(tile)) currentMap.removeLayer(tile);
        boundary.clearLayers();
        if (gisBundle?.buffer_boundary?.length) {
          L.polygon(gisBundle.buffer_boundary, {
            color: "#52525b",
            weight: 1.5,
            fillColor: "#a1a1aa",
            fillOpacity: 0.35,
          }).addTo(boundary);
        }
        if (gisBundle?.core_boundary?.length) {
          L.polygon(gisBundle.core_boundary, {
            color: "#71717a",
            weight: 1.2,
            fillColor: "#d4d4d8",
            fillOpacity: 0.55,
          }).addTo(boundary);
        }
        if (!currentMap.hasLayer(boundary)) boundary.addTo(currentMap);
      } else {
        if (currentMap.hasLayer(boundary)) currentMap.removeLayer(boundary);
        if (!currentMap.hasLayer(tile)) tile.addTo(currentMap);
      }
    });
  }, [compareMode, gisBundle, mapReady]);

  // Territory labels are plain positioned React elements, not Leaflet
  // tooltips — html2canvas cannot correctly resolve a Leaflet tooltip's
  // nested CSS transform (it renders fine on screen but ends up floating
  // off in the exported PNG), while a plain absolute-positioned div in the
  // regular DOM exports exactly where it's drawn. Track each territory's
  // centroid in screen pixels and keep it in sync as the map moves.
  const [labelPositions, setLabelPositions] = useState<{ tigerId: string; x: number; y: number }[]>([]);
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady || !compareMode) {
      setLabelPositions([]);
      return;
    }

    function update() {
      const currentMap = mapRef.current;
      if (!currentMap) return;
      const positions: { tigerId: string; x: number; y: number }[] = [];
      for (const layer of layers) {
        const territory = territoryByTiger.get(layer.tigerId);
        const center = territory ? territoryCenter(territory) : null;
        if (!center) continue;
        const pt = currentMap.latLngToContainerPoint(center);
        positions.push({ tigerId: layer.tigerId, x: pt.x, y: pt.y });
      }
      setLabelPositions(positions);
    }

    update();
    map.on("move", update);
    map.on("zoom", update);
    map.on("resize", update);
    return () => {
      map.off("move", update);
      map.off("zoom", update);
      map.off("resize", update);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [compareMode, layers, territoryByTiger, mapReady]);

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

        // Territory shape: the convex hull actually traced by this
        // tiger's own real sighting locations (see computeTerritory).
        const territory = territoryByTiger.get(layer.tigerId);

        if (compareMode) {
          // Comparison view: outline + direct label only, no per-station
          // pins or trail lines — matches the static MCP report style.
          if (territory?.kind === "polygon" && territory.polygon) {
            territory.polygon.forEach((pt) => allValidPoints.push(pt));
            const poly = L.polygon(territory.polygon, {
              color: layer.color,
              weight: 2.5,
              fillColor: layer.color,
              fillOpacity: 0.08,
            });
            poly.bindPopup(
              `<strong>${layer.tigerId}</strong><br>100% MCP: ${territory.areaKm2.toFixed(1)} km²`,
              { className: "gis-map-tooltip" }
            );
            layerRef.current!.addLayer(poly);
          } else if (territory?.kind === "circle" && territory.center && territory.radiusKm) {
            allValidPoints.push(territory.center);
            const circle = L.circle(territory.center, {
              radius: territory.radiusKm * 1000,
              color: layer.color,
              weight: 2.5,
              fillColor: layer.color,
              fillOpacity: 0.08,
            });
            layerRef.current!.addLayer(circle);
          }
          continue;
        }

        // Single-tiger view: satellite basemap + numbered per-station pins.
        if (valid.length === 0) continue;
        valid.forEach((p) => allValidPoints.push([p.latitude, p.longitude]));

        if (territory?.kind === "polygon" && territory.polygon) {
          const poly = L.polygon(territory.polygon, {
            color: "#f59e0b",
            weight: 1.8,
            dashArray: "6, 8",
            fillColor: "#f59e0b",
            fillOpacity: 0.05,
          });
          poly.bindTooltip(
            `<strong>Tiger ${layer.tigerId} Territory</strong><br>100% MCP: ${territory.areaKm2.toFixed(1)} km²`,
            { sticky: true, className: "gis-map-tooltip" }
          );
          layerRef.current!.addLayer(poly);
        } else if (territory?.kind === "circle" && territory.center && territory.radiusKm) {
          const circle = L.circle(territory.center, {
            radius: territory.radiusKm * 1000,
            color: "#f59e0b",
            weight: 1.8,
            dashArray: "6, 8",
            fillColor: "#f59e0b",
            fillOpacity: 0.05,
          });
          circle.bindTooltip(
            `<strong>Tiger ${layer.tigerId} Territory (est.)</strong><br>~${territory.areaKm2.toFixed(1)} km²`,
            { sticky: true, className: "gis-map-tooltip" }
          );
          layerRef.current!.addLayer(circle);
        }

        const ordered = [...valid].reverse();

        if (ordered.length > 1) {
          const line = L.polyline(
            ordered.map((p) => [p.latitude, p.longitude]),
            { color: "#ffffff", weight: 1.5, dashArray: "4, 8", opacity: 0.75 }
          );
          layerRef.current!.addLayer(line);
        }

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
      }

      if (allValidPoints.length > 0) {
        const bounds = L.latLngBounds(allValidPoints);
        currentMap.flyToBounds(bounds.pad(compareMode ? 0.2 : 0.35), { duration: 0.6 });
      }
    });
  }, [layers, territoryByTiger, mapReady, compareMode]);

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
        backgroundColor: compareMode ? "#f4f2ec" : "#09090b",
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
        <span
          className="flex items-center gap-1.5 rounded-full bg-zinc-900 px-2.5 py-1 text-2xs font-mono font-bold text-white"
          style={{ boxShadow: `inset 0 0 0 1px ${compareMode ? `${layers[0].color}66` : "rgba(255,255,255,0.3)"}` }}
        >
          <span className="h-2 w-2 rounded-full" style={{ backgroundColor: compareMode ? layers[0].color : "#ffffff" }} />
          {tigerId}
        </span>

        {layers.slice(1).map((l) => (
          <span
            key={l.tigerId}
            className="flex items-center gap-1.5 rounded-full bg-zinc-900 px-2.5 py-1 text-2xs font-mono font-bold text-white"
            style={{ boxShadow: `inset 0 0 0 1px ${l.color}66` }}
          >
            <span className="h-2 w-2 rounded-full" style={{ backgroundColor: l.color }} />
            {l.tigerId}
            <button
              onClick={() => removeTiger(l.tigerId)}
              className="ml-0.5 rounded-full p-0.5 text-zinc-400 hover:bg-zinc-800 hover:text-white"
              aria-label={`Remove ${l.tigerId}`}
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
        <div ref={containerRef} className="h-full w-full z-0" style={{ background: compareMode ? "#f4f2ec" : undefined }} />

        {compareMode &&
          labelPositions.map((lp) => (
            // Anchored with plain left/top (no centering transform) —
            // html2canvas resolves percentage-based CSS transforms
            // incorrectly, which was floating this label away from its
            // polygon in the exported PNG despite rendering fine live.
            <div
              key={lp.tigerId}
              className="pointer-events-none absolute z-[950] whitespace-nowrap font-mono text-[11px] font-bold"
              style={{
                left: lp.x - lp.tigerId.length * 3.3,
                top: lp.y - 6,
                color: "#1f2420",
                textShadow: "0 0 3px #fff, 0 0 3px #fff, 0 0 3px #fff",
              }}
            >
              {lp.tigerId}
            </div>
          ))}

        {compareMode && (
          <div className="pointer-events-none absolute top-11 left-2 z-[900] flex flex-col items-center" style={{ color: "#3f3f46" }}>
            <svg width="14" height="18" viewBox="0 0 16 20" fill="none">
              <path d="M8 0 L14 14 L8 10 L2 14 Z" fill="currentColor" />
            </svg>
            <span className="text-[9px] font-mono font-bold">N</span>
          </div>
        )}

        {layers.length > 1 && (
          <div
            className="pointer-events-none absolute bottom-10 left-2 z-[999] rounded-md px-2.5 py-1.5 text-2xs font-mono shadow-lg backdrop-blur-md"
            style={{ backgroundColor: "rgba(9,9,11,0.85)", color: "#ffffff" }}
          >
            <div className="mb-1 font-bold" style={{ color: "#d4d4d8" }}>Territory comparison</div>
            {layers.map((l) => (
              <div key={l.tigerId} className="flex items-center gap-1.5">
                <span
                  className="h-2.5 w-2.5 rounded-[2px]"
                  style={{ border: `2px solid ${l.color}`, backgroundColor: `${l.color}22` }}
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
