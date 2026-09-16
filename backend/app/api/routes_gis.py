"""
FastAPI Router: GIS Map Layers, 311 Stations, Boundaries, and Territories
"""

import os
import sys
import json
import sqlite3
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, HTTPException

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

router = APIRouter(prefix="/api", tags=["GIS"])

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
BUNDLE_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gis", "pench_web_bundle.json")


@router.get("/gis/bundle")
def get_map_bundle():
    """
    Returns complete vector map bundle: Core/Buffer boundaries, 11 sub-regions, 44 villages, 311 camera stations, territories, and recent sightings.
    """
    if os.path.exists(BUNDLE_PATH):
        with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)

    raise HTTPException(status_code=503, detail="GIS Web Bundle is still generating. Please retry in a moment.")


@router.get("/stations")
def list_stations():
    """
    Lists all 311 camera stations with operational status, zone, and habitat attributes.
    """
    if not os.path.exists(DB_PATH):
        if os.path.exists(BUNDLE_PATH):
            with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
                bundle = json.load(f)
            return {"stations": bundle.get("stations", [])}
        return {"stations": []}

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT * FROM camera_stations ORDER BY camera_id ASC")
    rows = [dict(r) for r in cur.fetchall()]
    conn.close()
    return {"stations": rows}


@router.get("/stations/{cam_id}")
def get_station_detail(cam_id: str):
    """
    Returns full dossier for a specific camera station: metadata, occupancy stats,
    all tigers seen with their details, alert breakdown, and recent sightings history.
    """
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT * FROM camera_stations WHERE camera_id = ?", (cam_id,))
    st_row = cur.fetchone()
    station = dict(st_row) if st_row else {"camera_id": cam_id}

    cur.execute("""
        SELECT
            s.event_id, s.tiger_id, s.timestamp, s.camera_id,
            s.latitude, s.longitude, s.zone, s.habitat_type,
            s.flank_side, s.speed_kmh, s.prey_density,
            s.image_quality, s.reid_confidence, s.anomaly_class,
            s.alert_level, s.threat_reason, s.acknowledged,
            s.distance_to_nearest_village_km, s.distance_to_nearest_water_km,
            tp.sex, tp.age_years, tp.life_stage, tp.territorial_status,
            tp.mcp_area_km2, tp.home_range_target_km2,
            tp.core_centroid_lat, tp.core_centroid_lon, tp.thumbnail
        FROM sightings s
        LEFT JOIN tiger_profiles tp ON s.tiger_id = tp.tiger_id
        WHERE s.camera_id = ?
        ORDER BY s.timestamp DESC
    """, (cam_id,))
    sighting_rows = [dict(r) for r in cur.fetchall()]

    # Derive per-tiger summary
    tiger_map: Dict[str, Dict] = {}
    alert_counts: Dict[str, int] = {"SAFE": 0, "CAUTION": 0, "DANGER": 0}

    for s in sighting_rows:
        tid = s["tiger_id"]
        level = (s.get("alert_level") or "SAFE").upper()
        alert_counts[level] = alert_counts.get(level, 0) + 1

        if tid not in tiger_map:
            tiger_map[tid] = {
                "tiger_id": tid,
                "sex": s.get("sex"),
                "age_years": s.get("age_years"),
                "life_stage": s.get("life_stage"),
                "territorial_status": s.get("territorial_status"),
                "mcp_area_km2": s.get("mcp_area_km2"),
                "home_range_target_km2": s.get("home_range_target_km2"),
                "core_centroid_lat": s.get("core_centroid_lat"),
                "core_centroid_lon": s.get("core_centroid_lon"),
                "thumbnail": s.get("thumbnail"),
                "num_captures_here": 0,
                "last_seen_here": None,
                "flanks_seen": set(),
                "alert_levels": set(),
            }
        tiger_map[tid]["num_captures_here"] += 1
        if tiger_map[tid]["last_seen_here"] is None:
            tiger_map[tid]["last_seen_here"] = s["timestamp"]
        if s.get("flank_side"):
            tiger_map[tid]["flanks_seen"].add(s["flank_side"])
        if level:
            tiger_map[tid]["alert_levels"].add(level)

    # Convert sets to lists for JSON serialisation
    tigers_seen = []
    for t in tiger_map.values():
        t["flanks_seen"] = sorted(t["flanks_seen"])
        t["alert_levels"] = sorted(t["alert_levels"])
        tigers_seen.append(t)

    # Sort by most captures at this station
    tigers_seen.sort(key=lambda x: x["num_captures_here"], reverse=True)

    # Occupancy stats
    total_sightings = len(sighting_rows)
    unique_tigers = len(tiger_map)

    # Date range of activity
    timestamps = [s["timestamp"] for s in sighting_rows if s.get("timestamp")]
    first_seen = timestamps[-1] if timestamps else None
    last_seen = timestamps[0] if timestamps else None

    # Average image quality
    qualities = []
    for s in sighting_rows:
        try:
            qualities.append(float(s.get("image_quality") or 0))
        except (TypeError, ValueError):
            pass
    avg_quality = round(sum(qualities) / len(qualities), 3) if qualities else None

    # Average prey density
    densities = [s["prey_density"] for s in sighting_rows if s.get("prey_density") is not None]
    avg_prey_density = round(sum(densities) / len(densities), 2) if densities else None

    conn.close()

    return {
        "station": station,
        "stats": {
            "total_sightings": total_sightings,
            "unique_tigers": unique_tigers,
            "first_seen": first_seen,
            "last_seen": last_seen,
            "avg_image_quality": avg_quality,
            "avg_prey_density": avg_prey_density,
            "alert_counts": alert_counts,
        },
        "tigers_seen": tigers_seen,
        "recent_sightings": sighting_rows[:50],
    }
