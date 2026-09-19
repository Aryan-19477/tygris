"""
Service: Male-Male Territory Overlap Detection ("Possible Fight Risk")

Adult male tigers hold exclusive, non-overlapping core territories — two
resident males camera-identified close together in space and time is the
classic precursor to a territorial fight (a leading cause of unnatural
tiger mortality). This runs synchronously right after a confident
camera-trap identification (`_record_sighting` in routes_identify.py) and
raises a CRITICAL alert through the same `write_field_alert` path every
other trigger source uses (see alert_writer.py), tagged with the
"MALE_TERRITORY_CONFLICT" anomaly class from anomaly_engine.py.

PROXIMITY_KM / RECENT_WINDOW_HOURS are a heuristic, not paper-calibrated:
known male home ranges here run ~12-70 km^2 (tiger_profiles.
home_range_target_km2), which corresponds to a core radius of roughly
2-5km, so two males camera-identified within PROXIMITY_KM of each other
inside RECENT_WINDOW_HOURS are treated as converging on contested ground.
"""

import os
import sys
import math
import sqlite3
import datetime
from typing import Optional

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.services.alert_writer import write_field_alert, alert_already_recorded

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")

PROXIMITY_KM = 6.0
RECENT_WINDOW_HOURS = 72


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Geodesic distance in kilometers. Mirrors app/simulation/pench_environment.py."""
    r = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def check_male_territory_conflict(
    tiger_id: str,
    camera_id: Optional[str],
    timestamp: str,
) -> Optional[str]:
    """Called right after a camera-trap sighting is recorded for `tiger_id`.
    If that tiger is male and another male was sighted within
    PROXIMITY_KM/RECENT_WINDOW_HOURS of this one, raises a single CRITICAL
    fight-risk alert naming both tigers and returns its event_id (or None
    if no conflict was found, the tiger isn't male, or it was a dedup-ed
    repeat of a pair/day already alerted)."""
    if not camera_id or not os.path.exists(DB_PATH):
        return None

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT sex FROM tiger_profiles WHERE tiger_id = ?", (tiger_id,))
    row = cur.fetchone()
    if not row or row["sex"] != "M":
        conn.close()
        return None

    cur.execute("SELECT latitude, longitude, zone FROM camera_stations WHERE camera_id = ?", (camera_id,))
    cam = cur.fetchone()
    if not cam or cam["latitude"] is None or cam["longitude"] is None:
        conn.close()
        return None

    try:
        cutoff = (
            datetime.datetime.fromisoformat(timestamp) - datetime.timedelta(hours=RECENT_WINDOW_HOURS)
        ).isoformat(timespec="seconds")
    except ValueError:
        # Malformed timestamp: skip the lookback window rather than fail the
        # sighting write this check rides along with.
        conn.close()
        return None

    cur.execute(
        """
        SELECT s.tiger_id AS other_tiger_id, s.camera_id AS other_camera_id, s.timestamp AS other_timestamp,
               c.latitude AS other_lat, c.longitude AS other_lon
        FROM sightings s
        JOIN tiger_profiles t ON t.tiger_id = s.tiger_id
        JOIN camera_stations c ON c.camera_id = s.camera_id
        WHERE t.sex = 'M' AND s.tiger_id != ? AND s.timestamp >= ? AND s.timestamp <= ?
        ORDER BY s.timestamp DESC
        """,
        (tiger_id, cutoff, timestamp),
    )
    candidates = cur.fetchall()
    conn.close()

    for cand in candidates:
        if cand["other_lat"] is None or cand["other_lon"] is None:
            continue
        dist = _haversine_km(cam["latitude"], cam["longitude"], cand["other_lat"], cand["other_lon"])
        if dist <= PROXIMITY_KM:
            other_id = cand["other_tiger_id"]
            pair_key = "_".join(sorted([tiger_id, other_id]))
            source_ref = f"CONFLICT_{pair_key}_{timestamp[:10]}"
            if alert_already_recorded(source_ref):
                return None

            reason = (
                f"Possible territorial conflict: male {tiger_id} sighted at {camera_id} only "
                f"{round(dist, 1)}km from male {other_id}'s sighting at {cand['other_camera_id']} "
                f"({cand['other_timestamp']}). Two resident males converging on the same ground is "
                f"a known precursor to a fight — flag both for a priority patrol check."
            )
            return write_field_alert(
                event_prefix="EVT_CONFLICT_",
                alert_level="CRITICAL",
                threat_reason=reason,
                source_ref=source_ref,
                latitude=cam["latitude"],
                longitude=cam["longitude"],
                zone=cam["zone"],
                tiger_id=tiger_id,
                camera_id=camera_id,
                timestamp=timestamp,
                anomaly_class="MALE_TERRITORY_CONFLICT",
            )

    return None
