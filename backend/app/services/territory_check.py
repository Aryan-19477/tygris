"""
Territory-check intelligence: when a ranger logs a wildlife-sighting/sign
observation in the field (via the Ranger Flutter app -> Supabase
`observations` table), find the camera-trap stations nearest to that
report's GPS position and flag them as prioritized for a manual check.

Output shape matches the `territory_checks` Supabase table (minus
check_id/computed_at, which the DB/insert path fills in):
    {
        "observation_id": str,
        "resident_tiger_id": None,
        "nearest_cameras": [{"camera_id", "distance_km", "zone", "sub_region"}, ...],
        "status": "cameras_prioritized" | "no_recent_data" | "no_location",
        "summary": str,
    }
"""

import os
import sys
import math
import sqlite3
from typing import Optional, List, Dict, Any

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")

NEAREST_CAMERA_COUNT = 5


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Geodesic distance in kilometers. Mirrors app/simulation/pench_environment.py."""
    r = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def _empty_result(observation_id: str, status: str, summary: str) -> Dict[str, Any]:
    return {
        "observation_id": observation_id,
        "resident_tiger_id": None,
        "nearest_cameras": [],
        "status": status,
        "summary": summary,
    }


def run_territory_check(observation: Dict[str, Any]) -> Dict[str, Any]:
    observation_id = observation.get("observation_id") or ""
    lat = observation.get("lat")
    lon = observation.get("lon")

    if lat is None or lon is None:
        return _empty_result(
            observation_id,
            "no_location",
            "This report has no GPS coordinates attached, so nearby cameras could not be identified.",
        )

    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return _empty_result(
            observation_id,
            "no_location",
            "This report has no GPS coordinates attached, so nearby cameras could not be identified.",
        )

    if not os.path.exists(DB_PATH):
        return _empty_result(
            observation_id,
            "no_recent_data",
            "Camera-trap reference database is unavailable; nearby cameras could not be identified.",
        )

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT camera_id, latitude, longitude, zone, sub_region FROM camera_stations")
    stations = cur.fetchall()
    conn.close()

    station_distances = []
    for s in stations:
        try:
            d = _haversine_km(lat, lon, float(s["latitude"]), float(s["longitude"]))
        except (TypeError, ValueError):
            continue
        station_distances.append((d, s))
    station_distances.sort(key=lambda x: x[0])
    nearest = station_distances[:NEAREST_CAMERA_COUNT]
    nearest_cameras: List[Dict[str, Any]] = [
        {
            "camera_id": s["camera_id"],
            "distance_km": round(d, 1),
            "zone": s["zone"],
            "sub_region": s["sub_region"],
        }
        for d, s in nearest
    ]

    if not nearest_cameras:
        return _empty_result(
            observation_id,
            "no_recent_data",
            "No camera stations were found near this report's location.",
        )

    camera_list = ", ".join(f"{c['camera_id']} ({c['distance_km']}km)" for c in nearest_cameras)
    plural = "s" if len(nearest_cameras) != 1 else ""
    summary = (
        f"{len(nearest_cameras)} camera{plural} near this report have been prioritized "
        f"for checking: {camera_list}."
    )

    return {
        "observation_id": observation_id,
        "resident_tiger_id": None,
        "nearest_cameras": nearest_cameras,
        "status": "cameras_prioritized",
        "summary": summary,
    }
