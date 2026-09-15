"""
Territory-check intelligence: "is the resident tiger of this area still
here, or does it look like it moved?"

Triggered whenever a ranger logs a wildlife-sighting/sign observation in
the field (via the Ranger Flutter app -> Supabase `observations` table).
Cross-references that report's GPS position against the reserve's real
camera-trap network (`camera_stations`) and tiger-sighting history
(`sightings`, `tiger_profiles`) in backend/data/pench_unified.db.

Output shape matches the `territory_checks` Supabase table (minus
check_id/computed_at, which the DB/insert path fills in):
    {
        "observation_id": str,
        "resident_tiger_id": str | None,
        "nearest_cameras": [{"camera_id", "distance_km", "zone", "sub_region"}, ...],
        "status": "confirmed_present" | "possible_move" | "no_recent_data" | "no_location",
        "summary": str,
    }
"""

import os
import sys
import math
import sqlite3
from datetime import datetime
from typing import Optional, List, Dict, Any

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")

# How far back (from the *observation's* timestamp, not "now" — the demo
# data is historical/fixed, so anchoring to wall-clock "now" would make
# every past sighting look stale) to look for the resident tiger's most
# recent camera-trap sighting before calling it "no recent data".
LOOKBACK_DAYS = 21

NEAREST_CAMERA_COUNT = 5


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Geodesic distance in kilometers. Mirrors app/simulation/pench_environment.py."""
    r = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def _parse_timestamp(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    text = str(value).strip()
    if not text:
        return None
    # Supabase timestamptz values commonly arrive as "...+00:00" or "...Z".
    text = text.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        # Fall back to a plain "YYYY-MM-DD HH:MM:SS" sqlite-style timestamp.
        for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S"):
            try:
                dt = datetime.strptime(text, fmt)
                break
            except ValueError:
                continue
        else:
            return None
    if dt.tzinfo is not None:
        dt = dt.replace(tzinfo=None)
    return dt


def _format_recency(delta_hours: float) -> str:
    if delta_hours < 24:
        hours = max(1, round(delta_hours))
        return f"{hours}h"
    days = round(delta_hours / 24.0)
    return f"{days}d" if days != 1 else "1d"


def _no_location_result(observation_id: str) -> Dict[str, Any]:
    return {
        "observation_id": observation_id,
        "resident_tiger_id": None,
        "nearest_cameras": [],
        "status": "no_location",
        "summary": "This report has no GPS coordinates attached, so a territory check could not be run.",
    }


def run_territory_check(observation: Dict[str, Any]) -> Dict[str, Any]:
    observation_id = observation.get("observation_id") or ""
    lat = observation.get("lat")
    lon = observation.get("lon")

    if lat is None or lon is None:
        return _no_location_result(observation_id)

    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return _no_location_result(observation_id)

    obs_time = _parse_timestamp(observation.get("timestamp")) or datetime.utcnow()

    if not os.path.exists(DB_PATH):
        return {
            "observation_id": observation_id,
            "resident_tiger_id": None,
            "nearest_cameras": [],
            "status": "no_recent_data",
            "summary": "Camera-trap reference database is unavailable; territory check could not be computed.",
        }

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # --- Nearest camera stations -----------------------------------------
    cur.execute("SELECT camera_id, latitude, longitude, zone, sub_region FROM camera_stations")
    stations = cur.fetchall()
    station_distances = []
    for s in stations:
        try:
            d = _haversine_km(lat, lon, float(s["latitude"]), float(s["longitude"]))
        except (TypeError, ValueError):
            continue
        station_distances.append((d, s))
    station_distances.sort(key=lambda x: x[0])
    nearest = station_distances[:NEAREST_CAMERA_COUNT]
    nearest_cameras = [
        {
            "camera_id": s["camera_id"],
            "distance_km": round(d, 1),
            "zone": s["zone"],
            "sub_region": s["sub_region"],
        }
        for d, s in nearest
    ]
    nearest_camera_ids = {c["camera_id"] for c in nearest_cameras}

    # --- Resident tiger: whose home-range centroid is closest -------------
    cur.execute("SELECT tiger_id, core_centroid_lat, core_centroid_lon FROM tiger_profiles")
    tigers = cur.fetchall()
    resident_tiger_id = None
    best_dist = None
    for t in tigers:
        if t["core_centroid_lat"] is None or t["core_centroid_lon"] is None:
            continue
        try:
            d = _haversine_km(lat, lon, float(t["core_centroid_lat"]), float(t["core_centroid_lon"]))
        except (TypeError, ValueError):
            continue
        if best_dist is None or d < best_dist:
            best_dist = d
            resident_tiger_id = t["tiger_id"]

    if resident_tiger_id is None:
        conn.close()
        return {
            "observation_id": observation_id,
            "resident_tiger_id": None,
            "nearest_cameras": nearest_cameras,
            "status": "no_recent_data",
            "summary": "No tiger territory data is available to cross-reference against this report.",
        }

    # --- Resident tiger's most recent sighting within the lookback window -
    cur.execute(
        """
        SELECT tiger_id, timestamp, camera_id, latitude, longitude
        FROM sightings
        WHERE tiger_id = ?
        ORDER BY timestamp DESC
        """,
        (resident_tiger_id,),
    )
    rows = cur.fetchall()
    conn.close()

    most_recent = None
    most_recent_dt = None
    for row in rows:
        ts = _parse_timestamp(row["timestamp"])
        if ts is None:
            continue
        age_days = (obs_time - ts).total_seconds() / 86400.0
        if age_days < 0:
            # Sighting after the report's own timestamp — not useful as "last seen before this report".
            continue
        if age_days > LOOKBACK_DAYS:
            break  # rows are timestamp DESC, so nothing further back qualifies either
        most_recent = row
        most_recent_dt = ts
        break

    if most_recent is None:
        return {
            "observation_id": observation_id,
            "resident_tiger_id": resident_tiger_id,
            "nearest_cameras": nearest_cameras,
            "status": "no_recent_data",
            "summary": (
                f"No confirmed sighting of {resident_tiger_id} (the usual territory holder here) "
                f"in the last {LOOKBACK_DAYS} days."
            ),
        }

    delta_hours = (obs_time - most_recent_dt).total_seconds() / 3600.0
    recency = _format_recency(delta_hours)
    last_camera_id = most_recent["camera_id"]

    try:
        dist_from_report = _haversine_km(
            lat, lon, float(most_recent["latitude"]), float(most_recent["longitude"])
        )
    except (TypeError, ValueError):
        dist_from_report = None
    dist_str = f"{round(dist_from_report, 1)}" if dist_from_report is not None else "an unknown distance"

    if last_camera_id in nearest_camera_ids:
        cam_dist = next((c["distance_km"] for c in nearest_cameras if c["camera_id"] == last_camera_id), dist_from_report)
        status = "confirmed_present"
        summary = (
            f"{resident_tiger_id} confirmed near this report — last seen {recency} ago "
            f"at {last_camera_id}, {cam_dist}km away."
        )
    else:
        status = "possible_move"
        summary = (
            f"{resident_tiger_id}'s territory covers this area, but it was last seen {recency} ago "
            f"at {last_camera_id} ({dist_str}km away) — may have shifted range."
        )

    return {
        "observation_id": observation_id,
        "resident_tiger_id": resident_tiger_id,
        "nearest_cameras": nearest_cameras,
        "status": status,
        "summary": summary,
    }
