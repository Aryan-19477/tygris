"use client";

import { useEffect, useRef, useState } from "react";
import type { GISMapBundle, GISStation } from "@/lib/api";

type BasemapStyle = "satellite" | "google_hybrid" | "dark" | "topo";
type LeafletMap = import("leaflet").Map;
type LeafletLayer = import("leaflet").Layer;

const BASEMAP_TILES: Record<BasemapStyle, { name: string; url: string; attribution: string; maxZoom: number }> = {
  satellite: {
    name: "ESRI Satellite",
    url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
    attribution: "Tiles &copy; Esri",
    maxZoom: 19,
  },
  google_hybrid: {
    name: "Google Hybrid",
    url: "https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}",
    attribution: "Google Satellite",
    maxZoom: 20,
  },
  dark: {
    name: "Dark GIS",
    url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    attribution: "CARTO DarkMatter",
    maxZoom: 19,
  },
  topo: {
    name: "OpenTopo",
    url: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
    attribution: "OpenTopoMap",
    maxZoom: 17,
  },
};

function hueForId(id: string) {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  }
  return hash % 360;
}

/**
 * Sub-regions only carry a center point, not a boundary polygon, so a
 * tiger is assigned to whichever range's center its territory centroid is
 * closest to - the same nearest-center convention the backend already
 * uses to assign camera stations to a range (pench_environment.py's
 * get_nearest_sub_region).
 */
function countTigersPerRange(bundle: GISMapBundle): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const sr of bundle.sub_regions || []) counts[sr.name] = 0;

  for (const t of Object.values(bundle.territories || {})) {
    if (!Array.isArray(t.centroid) || t.centroid.length !== 2) continue;
    const [tLat, tLon] = t.centroid;

    let nearest: string | null = null;
    let nearestDist = Infinity;
    for (const sr of bundle.sub_regions || []) {
      const dlat = (sr.center[0] - tLat) * 111.0;
      const dlon = (sr.center[1] - tLon) * 103.0;
      const d = dlat * dlat + dlon * dlon;
      if (d < nearestDist) {
        nearestDist = d;
        nearest = sr.name;
      }
    }
    if (nearest) counts[nearest] = (counts[nearest] ?? 0) + 1;
  }

  return counts;
}

export interface MapLayerToggles {
  core: boolean;
  buffer: boolean;
  stations: boolean;
  villages: boolean;
  territories: boolean;
  subregions: boolean;
  lastSeen: boolean;
}

interface LeafletSatelliteMapProps {
  bundle: GISMapBundle | null;
  selectedStation: GISStation | null;
  selectedTigerId: string | null;
  layers: MapLayerToggles;
  onSelectStation: (station: GISStation) => void;
  onSelectTiger: (tigerId: string) => void;
  /** Hide the basemap switcher, recenter button, and legend — for use as a
   * full-bleed hero background where a host view provides its own chrome. */
  chrome?: boolean;
  /** Drop the panel border/rounding/shadow so the map can bleed edge to edge. */
  bare?: boolean;
  /** Extra fitBounds padding, in px, per side — lets a host view reserve
   * screen space (e.g. a floating card column) that the auto-fit and
   * "Reset Pench View" should treat as unusable for the map content. */
  fitPadding?: { topLeft?: [number, number]; bottomRight?: [number, number] };
}

const ALERT_COLORS: Record<string, string> = {
  SAFE: "#10b981",
  CAUTION: "#f59e0b",
  CRITICAL: "#ef4444",
};

/**
 * One marker per tiger: its most recent recent_sightings entry, falling
 * back to the territory centroid for tigers with no recent event on file
 * (recent_sightings is a capped recent-activity feed, not a full history,
 * so a few tigers may have nothing in it yet).
 */
function computeLastSeenPoints(bundle: GISMapBundle) {
  const latestByTiger = new Map<string, { latitude: number; longitude: number; timestamp: string; alert_level?: string; camera_id?: string; zone?: string }>();

  for (const s of bundle.recent_sightings || []) {
    if (typeof s.latitude !== "number" || typeof s.longitude !== "number") continue;
    const existing = latestByTiger.get(s.tiger_id);
    if (!existing || (s.timestamp && s.timestamp > existing.timestamp)) {
      latestByTiger.set(s.tiger_id, {
        latitude: s.latitude,
        longitude: s.longitude,
        timestamp: s.timestamp || "",
        alert_level: s.alert_level,
        camera_id: s.camera_id ?? undefined,
        zone: s.zone,
      });
    }
  }

  const points: { tiger_id: string; latitude: number; longitude: number; timestamp: string; alert_level: string; camera_id?: string; zone?: string; fromCentroid: boolean }[] = [];

  Object.values(bundle.territories || {}).forEach((t) => {
    const seen = latestByTiger.get(t.tiger_id);
    if (seen) {
      points.push({
        tiger_id: t.tiger_id,
        latitude: seen.latitude,
        longitude: seen.longitude,
        timestamp: seen.timestamp,
        alert_level: seen.alert_level || "SAFE",
        camera_id: seen.camera_id,
        zone: seen.zone,
        fromCentroid: false,
      });
    } else if (Array.isArray(t.centroid) && t.centroid.length === 2) {
      points.push({
        tiger_id: t.tiger_id,
        latitude: t.centroid[0],
        longitude: t.centroid[1],
        timestamp: "",
        alert_level: "SAFE",
        fromCentroid: true,
      });
    }
  });

  return points;
}

export function LeafletSatelliteMap({
  bundle,
  selectedStation,
  selectedTigerId,
  layers,
  onSelectStation,
  onSelectTiger,
  chrome = true,
  bare = false,
  fitPadding,
}: LeafletSatelliteMapProps) {
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<LeafletMap | null>(null);
  const tileLayerRef = useRef<LeafletLayer | null>(null);
  const corePolyRef = useRef<import("leaflet").Polygon | null>(null);
  const territoryPolysRef = useRef<Record<string, import("leaflet").Polygon>>({});
  const [mapReady, setMapReady] = useState(false);
  const [basemap, setBasemap] = useState<BasemapStyle>("satellite");

  const layersGroupRef = useRef<Record<string, LeafletLayer | undefined>>({});

  // 1. Initialize Leaflet Map Instance
  useEffect(() => {
    if (typeof window === "undefined" || !mapContainerRef.current) return;

    let isMounted = true;

    import("leaflet").then((leafletModule) => {
      if (!isMounted || !mapContainerRef.current) return;
      const L = leafletModule.default || leafletModule;

      if (!mapInstanceRef.current) {
        const map = L.map(mapContainerRef.current, {
          center: [21.65, 79.25],
          zoom: 11,
          zoomControl: false,
          attributionControl: false,
        });

        L.control.zoom({ position: "topright" }).addTo(map);

        const currentTile = BASEMAP_TILES[basemap];
        const tileLayer = L.tileLayer(currentTile.url, {
          attribution: currentTile.attribution,
          maxZoom: currentTile.maxZoom,
          subdomains: "abcd",
        }).addTo(map);

        tileLayerRef.current = tileLayer;
        mapInstanceRef.current = map;
        setMapReady(true);
      }
    });

    return () => {
      isMounted = false;
      if (mapInstanceRef.current) {
        mapInstanceRef.current.remove();
        mapInstanceRef.current = null;
        setMapReady(false);
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 2. Switch Tile Layers
  useEffect(() => {
    const map = mapInstanceRef.current;
    if (!map || !mapReady) return;

    import("leaflet").then((leafletModule) => {
      const L = leafletModule.default || leafletModule;
      const currentMap = mapInstanceRef.current;
      if (!currentMap) return;

      if (tileLayerRef.current && currentMap.hasLayer(tileLayerRef.current)) {
        currentMap.removeLayer(tileLayerRef.current);
      }

      const currentTile = BASEMAP_TILES[basemap];
      const newTileLayer = L.tileLayer(currentTile.url, {
        attribution: currentTile.attribution,
        maxZoom: currentTile.maxZoom,
        subdomains: "abcd",
      }).addTo(currentMap);

      tileLayerRef.current = newTileLayer;
    });
  }, [basemap, mapReady]);

  // 3. Render Vector Layers and Handle Auto-Fit
  useEffect(() => {
    const map = mapInstanceRef.current;
    if (!map || !mapReady || !bundle) return;

    import("leaflet").then((leafletModule) => {
      const L = leafletModule.default || leafletModule;
      const currentMap = mapInstanceRef.current;
      if (!currentMap) return;

      const groups = layersGroupRef.current;

      Object.values(groups).forEach((g) => {
        if (g && currentMap.hasLayer(g)) {
          currentMap.removeLayer(g);
        }
      });

      territoryPolysRef.current = {};

      // A. Buffer Zone Polygon
      if (layers.buffer && bundle.buffer_boundary && bundle.buffer_boundary.length > 0) {
        const bufferPoly = L.polygon(bundle.buffer_boundary, {
          color: "#06b6d4",
          weight: 1.5,
          dashArray: "5, 5",
          fillColor: "#06b6d4",
          fillOpacity: 0.05,
        }).bindPopup(`<div style="font-family: ui-monospace, monospace; font-size: 11px;"><b>Pench Buffer Zone</b><br>Area: ${bundle.metadata.buffer_area_km2 || 301.97} km²</div>`);
        bufferPoly.addTo(currentMap);
        groups.buffer = bufferPoly;
      }

      // B. Core Zone Polygon
      if (layers.core && bundle.core_boundary && bundle.core_boundary.length > 0) {
        const corePoly = L.polygon(bundle.core_boundary, {
          color: "#10b981",
          weight: 2.2,
          fillColor: "#10b981",
          fillOpacity: 0.12,
        }).bindPopup(`<div style="font-family: ui-monospace, monospace; font-size: 11px;"><b>Pench Core Forest Reserve</b><br>Area: ${bundle.metadata.core_area_km2 || 439.24} km²</div>`);
        corePoly.addTo(currentMap);
        groups.core = corePoly;
        corePolyRef.current = corePoly;

        if (!selectedTigerId && !selectedStation) {
          currentMap.fitBounds(corePoly.getBounds(), fitPadding
            ? { paddingTopLeft: fitPadding.topLeft ?? [35, 35], paddingBottomRight: fitPadding.bottomRight ?? [35, 35] }
            : { padding: [35, 35] });
        }
      }

      // C. Sub-Region Center Labels (name + tiger count in that range)
      if (layers.subregions && bundle.sub_regions) {
        const subregionGroup = L.layerGroup();
        const tigerCounts = countTigersPerRange(bundle);
        bundle.sub_regions.forEach((sr) => {
          const count = tigerCounts[sr.name] ?? 0;
          const divIcon = L.divIcon({
            className: "custom-subregion-label",
            html: `<div style="display:flex;align-items:center;gap:6px;background: rgba(9, 9, 11, 0.75); color: #e4e4e7; border: 1px solid rgba(255,255,255,0.12); font-size: 10px; font-weight: 600; font-family: ui-monospace, monospace; padding: 2px 7px; border-radius: 6px; white-space: nowrap; backdrop-filter: blur(4px); box-shadow: 0 4px 12px rgba(0,0,0,0.5); cursor: default;"><span>${sr.name}</span><span style="background:#10b981;color:#062b18;border-radius:999px;padding:0 6px;font-weight:700;">${count}</span></div>`,
            iconSize: [140, 20],
            iconAnchor: [70, 10],
          });
          const marker = L.marker(sr.center, { icon: divIcon, interactive: true });
          marker.bindTooltip(
            `<div style="font-family: ui-monospace, monospace;"><b>${sr.name}</b><br>${count} tiger${count === 1 ? "" : "s"} in range<br>${sr.area_km2} km² — ${sr.habitat}</div>`,
            { sticky: true, className: "gis-map-tooltip" }
          );
          marker.addTo(subregionGroup);
        });
        subregionGroup.addTo(currentMap);
        groups.subregions = subregionGroup;
      }

      // D. Tiger Territories
      if (bundle.territories) {
        const territoryGroup = L.layerGroup();

        Object.values(bundle.territories).forEach((t) => {
          const hue = hueForId(t.tiger_id);
          const isSelected = selectedTigerId === t.tiger_id;

          const shouldRender = isSelected || layers.territories;
          if (!shouldRender) {
            territoryPolysRef.current[t.tiger_id] = L.polygon(t.polygon);
            return;
          }

          const poly = L.polygon(t.polygon, {
            color: isSelected ? "#10b981" : `hsl(${hue}, 70%, 50%)`,
            weight: isSelected ? 3.5 : 1,
            fillColor: isSelected ? "#10b981" : `hsl(${hue}, 70%, 50%)`,
            fillOpacity: isSelected ? 0.35 : 0.04,
            dashArray: isSelected ? undefined : "3, 3",
          });

          poly.bindTooltip(
            `<div style="font-family: ui-monospace, monospace;"><b>${t.tiger_id} Territory</b><br>100% MCP: ${t.area_km2} km²<br><span style="color: #10b981;">Click to inspect dossier</span></div>`,
            { sticky: true, className: "gis-map-tooltip" }
          );

          poly.on("click", () => {
            onSelectTiger(t.tiger_id);
          });

          poly.addTo(territoryGroup);
          territoryPolysRef.current[t.tiger_id] = poly;
        });

        territoryGroup.addTo(currentMap);
        groups.territories = territoryGroup;
      }

      // E. Fringe Villages
      if (layers.villages && bundle.villages) {
        const villageGroup = L.layerGroup();
        bundle.villages.forEach((v) => {
          L.circle([v.lat, v.lon], {
            radius: 1000,
            color: "#ef4444",
            weight: 0.8,
            dashArray: "3, 3",
            fillColor: "#ef4444",
            fillOpacity: 0.03,
          }).addTo(villageGroup);

          const marker = L.circleMarker([v.lat, v.lon], {
            radius: 3,
            color: "#ffffff",
            weight: 1,
            fillColor: "#f59e0b",
            fillOpacity: 0.9,
          });

          marker.bindTooltip(
            `<div style="font-family: ui-monospace, monospace;"><b>Village: ${v.name}</b><br>Pop: ${v.population} | Livestock: ${v.livestock}</div>`,
            { direction: "top", className: "gis-map-tooltip" }
          );

          marker.addTo(villageGroup);
        });
        villageGroup.addTo(currentMap);
        groups.villages = villageGroup;
      }

      // F. Camera Trap Stations
      if (layers.stations && bundle.stations) {
        const stationGroup = L.layerGroup();
        bundle.stations.forEach((cam) => {
          const isOperational = cam.operational_status === "OPERATIONAL";
          const isSelected = selectedStation?.camera_id === cam.camera_id;

          const marker = L.circleMarker([cam.latitude, cam.longitude], {
            radius: isSelected ? 6.5 : 3,
            color: isSelected ? "#ffffff" : isOperational ? "#10b981" : "#ef4444",
            weight: isSelected ? 2 : 0.8,
            fillColor: isOperational ? "#10b981" : "#ef4444",
            fillOpacity: 0.85,
          });

          marker.bindTooltip(
            `<div style="font-family: ui-monospace, monospace;"><b>${cam.camera_id}</b><br>Zone: ${cam.zone} (${cam.sub_region})<br>Status: <span style="color: ${isOperational ? "#4ade80" : "#f87171"}">${cam.operational_status}</span></div>`,
            { direction: "top", className: "gis-map-tooltip" }
          );

          marker.on("click", () => {
            onSelectStation(cam);
          });

          marker.addTo(stationGroup);
        });
        stationGroup.addTo(currentMap);
        groups.stations = stationGroup;
      }

      // G. Tigers Last Seen — on by default per the situational-awareness redesign
      if (layers.lastSeen) {
        const lastSeenGroup = L.layerGroup();
        const points = computeLastSeenPoints(bundle);

        points.forEach((p) => {
          const isSelected = selectedTigerId === p.tiger_id;
          const color = ALERT_COLORS[p.alert_level] || ALERT_COLORS.SAFE;

          const icon = L.divIcon({
            className: "custom-lastseen-icon",
            html: `<div style="
              width:${isSelected ? 26 : 20}px;height:${isSelected ? 26 : 20}px;border-radius:50%;
              display:flex;align-items:center;justify-content:center;
              font-family:ui-monospace,monospace;font-size:9px;font-weight:700;color:#fff;
              background:${color};border:2px solid #ffffff;
              box-shadow:0 0 8px ${color}aa;
              ${p.fromCentroid ? "opacity:0.6;" : ""}
            "></div>`,
            iconSize: [isSelected ? 26 : 20, isSelected ? 26 : 20],
            iconAnchor: [isSelected ? 13 : 10, isSelected ? 13 : 10],
          });

          const marker = L.marker([p.latitude, p.longitude], { icon });
          marker.bindTooltip(
            `<div style="font-family: ui-monospace, monospace; font-size: 11px;">
              <b>${p.tiger_id}</b><br>
              ${p.fromCentroid
                ? '<span style="color:#a1a1aa;">No recent sighting on file — showing territory centroid</span>'
                : `${p.camera_id || "Unknown station"} (${p.zone || "?"})<br>${p.timestamp ? new Date(p.timestamp).toLocaleString() : ""}<br><span style="color:${color}">${p.alert_level}</span>`}
            </div>`,
            { sticky: true, className: "gis-map-tooltip" }
          );
          marker.on("click", () => onSelectTiger(p.tiger_id));
          marker.addTo(lastSeenGroup);
        });

        lastSeenGroup.addTo(currentMap);
        groups.lastSeen = lastSeenGroup;
      }
    });
  }, [bundle, layers, selectedStation, selectedTigerId, mapReady, onSelectStation, onSelectTiger, fitPadding]);

  // 4. Smooth Focus to Selected Tiger or Station
  useEffect(() => {
    const map = mapInstanceRef.current;
    if (!map || !mapReady) return;

    if (selectedTigerId && territoryPolysRef.current[selectedTigerId]) {
      const poly = territoryPolysRef.current[selectedTigerId];
      if (poly && typeof poly.getBounds === "function") {
        map.fitBounds(poly.getBounds(), { padding: [60, 60], maxZoom: 13 });
      }
    } else if (selectedStation) {
      map.flyTo([selectedStation.latitude, selectedStation.longitude], 14, { duration: 1.0 });
    }
  }, [selectedTigerId, selectedStation, mapReady]);

  const handleRecenter = () => {
    const currentMap = mapInstanceRef.current;
    if (!currentMap) return;

    if (corePolyRef.current) {
      currentMap.fitBounds(corePolyRef.current.getBounds(), fitPadding
        ? { paddingTopLeft: fitPadding.topLeft ?? [35, 35], paddingBottomRight: fitPadding.bottomRight ?? [35, 35] }
        : { padding: [35, 35] });
    } else {
      currentMap.flyTo([21.65, 79.25], 11, { duration: 1.0 });
    }
  };

  return (
    <div
      className={`relative h-full w-full overflow-hidden bg-zinc-950 ${
        bare ? "" : "rounded-2xl border border-border shadow-2xl"
      }`}
    >
      <div ref={mapContainerRef} className="h-full w-full z-0" style={{ minHeight: bare ? undefined : "560px" }} />

      {chrome && (
        <>
          <div className="absolute top-3 left-3 z-1000 flex items-center gap-1 rounded-xl border border-white/10 bg-zinc-950/80 p-1 backdrop-blur-md shadow-2xl">
            {(Object.keys(BASEMAP_TILES) as BasemapStyle[]).map((style) => {
              const isActive = basemap === style;
              return (
                <button
                  key={style}
                  onClick={() => setBasemap(style)}
                  className={`rounded-lg px-2.5 py-1 text-xs font-mono font-medium transition-all ${
                    isActive
                      ? "bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 font-semibold shadow-sm"
                      : "text-zinc-400 hover:text-zinc-200 hover:bg-white/5"
                  }`}
                >
                  {BASEMAP_TILES[style].name}
                </button>
              );
            })}
          </div>

          <button
            onClick={handleRecenter}
            className="absolute top-3 right-14 z-1000 flex items-center gap-1.5 rounded-xl border border-white/10 bg-zinc-950/80 px-3 py-1 text-xs font-mono font-medium text-zinc-200 backdrop-blur-md shadow-2xl hover:bg-white/10 hover:text-white transition-all"
          >
            <span>Reset Pench View</span>
          </button>

          <div className="absolute bottom-4 left-4 z-1000 rounded-xl border border-white/10 bg-zinc-950/85 p-3 text-xs font-mono backdrop-blur-md space-y-1.5 shadow-2xl">
            <div className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-emerald-400" />
              <span className="text-zinc-300 text-[11px]">Core Forest Reserve (439 km²)</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-cyan-400" />
              <span className="text-zinc-300 text-[11px]">Buffer Zone (301 km²)</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-amber-400" />
              <span className="text-zinc-300 text-[11px]">Fringe Villages</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-emerald-500" />
              <span className="text-zinc-300 text-[11px]">Camera Trap Stations</span>
            </div>
            {layers.lastSeen && (
              <div className="flex items-center gap-2">
                <span className="h-2 w-2 rounded-full bg-white ring-2 ring-emerald-400" />
                <span className="text-zinc-300 text-[11px]">Tigers Last Seen</span>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
