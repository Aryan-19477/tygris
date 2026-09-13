"use client";

import { useEffect, useRef, useState } from "react";

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

function distKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const dlat = (lat2 - lat1) * 111.0;
  const dlon = (lon2 - lon1) * 103.0;
  return Math.sqrt(dlat * dlat + dlon * dlon);
}

/**
 * Focused Leaflet map for a single tiger's sighting trail. Given the
 * currently visible (windowed) points from SightingWindowSlider, draws a
 * connecting polyline, numbered alert-colored pins, and a territory circle
 * sized to the visible cluster.
 */
export function SightingTrailMap({ points, tigerId }: { points: TrailPoint[]; tigerId: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const layerRef = useRef<LeafletLayerGroup | null>(null);
  const [mapReady, setMapReady] = useState(false);

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

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;

    import("leaflet").then((leafletModule) => {
      const L = leafletModule.default || leafletModule;
      const currentMap = mapRef.current;
      if (!currentMap || !layerRef.current) return;

      layerRef.current.clearLayers();

      const valid = points.filter(
        (p): p is TrailPoint & { latitude: number; longitude: number } =>
          typeof p.latitude === "number" && typeof p.longitude === "number"
      );
      if (valid.length === 0) return;

      const avgLat = valid.reduce((sum, p) => sum + p.latitude, 0) / valid.length;
      const avgLon = valid.reduce((sum, p) => sum + p.longitude, 0) / valid.length;
      const maxDistKm = Math.max(...valid.map((p) => distKm(avgLat, avgLon, p.latitude, p.longitude)), 0);
      const radiusKm = Math.max(1.5, maxDistKm * 1.15);

      const circle = L.circle([avgLat, avgLon], {
        radius: radiusKm * 1000,
        color: "#f59e0b",
        weight: 1.8,
        dashArray: "6, 8",
        fillColor: "#f59e0b",
        fillOpacity: 0.05,
      });
      circle.bindTooltip(
        `<strong>Tiger ${tigerId} Territory</strong><br>~${(Math.PI * radiusKm * radiusKm).toFixed(1)} km² (radius ${radiusKm.toFixed(2)} km)`,
        { sticky: true, className: "gis-map-tooltip" }
      );
      layerRef.current.addLayer(circle);

      if (valid.length > 1) {
        const ordered = [...valid].reverse();
        const line = L.polyline(
          ordered.map((p) => [p.latitude, p.longitude]),
          { color: "#ffffff", weight: 1.5, dashArray: "4, 8", opacity: 0.75 }
        );
        layerRef.current.addLayer(line);
      }

      const ordered = [...valid].reverse();
      ordered.forEach((p, i) => {
        const isLatest = i === ordered.length - 1;
        const color = ALERT_COLORS[p.alert_level || "SAFE"] || ALERT_COLORS.SAFE;
        const icon = L.divIcon({
          className: "custom-trail-icon",
          html: `<div style="
            width:20px;height:20px;border-radius:50%;
            display:flex;align-items:center;justify-content:center;
            font-family:ui-monospace,monospace;font-size:10px;font-weight:700;
            background:${isLatest ? color : "rgba(9,9,11,0.85)"};
            color:${isLatest ? "#fff" : "#e4e4e7"};
            border:2px solid ${isLatest ? "#fff" : color};
            transform:${isLatest ? "scale(1.2)" : "scale(1)"};
          ">${i + 1}</div>`,
          iconSize: [20, 20],
          iconAnchor: [10, 10],
        });
        const marker = L.marker([p.latitude, p.longitude], { icon });
        marker.bindPopup(
          `<div style="font-family: ui-monospace, monospace; font-size: 11px;">
            <b>${p.camera_id || p.station || "Unknown station"}</b><br>
            ${p.timestamp ? new Date(p.timestamp).toLocaleString() : "Unknown time"}<br>
            <span style="color:${color}">${p.alert_level || "SAFE"}</span>
          </div>`,
          { className: "gis-map-tooltip" }
        );
        layerRef.current!.addLayer(marker);
      });

      const bounds = L.latLngBounds(valid.map((p) => [p.latitude, p.longitude]));
      currentMap.flyToBounds(bounds.pad(0.35), { duration: 0.6 });
    });
  }, [points, mapReady, tigerId]);

  return (
    <div className="relative h-90 w-full overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl">
      <div ref={containerRef} className="h-full w-full z-0" />
    </div>
  );
}
