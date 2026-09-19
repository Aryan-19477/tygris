"""
Service: Live Patrol Field-Risk Alerting

Rangers' GPS points land directly in Supabase's `gps_track_points` table
while a patrol is active (pushed by `ActivePatrolController` in the Flutter
app — see `pushLivePatrolUpdate` in `sync_queue_service.dart`). This service
polls that table for active patrols and runs each point through the same
`ConflictAlertClassifier` the offline ecological simulation uses
(`backend/app/simulation/anomaly_engine.py`) — the WII-calibrated taxonomy
that already covers both buffer/core zone and village-proximity thresholds
in one place — so a patrol's route escalating from SAFE into CAUTION/
CRITICAL raises a `sightings` alert row exactly like a camera-trap alert
does. This is what closes the "GPS -> buffer zone / village proximity ->
alert" pipeline end-to-end.

Called by the background poll loop in `main.py`, same pattern as
`routes_ranger_ops.run_pending_territory_checks`.
"""

import os
import sys
import logging
from collections import defaultdict
from typing import Any, Dict, List

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.simulation.pench_environment import CORE_BOUNDARY, BUFFER_BOUNDARY, VILLAGES_44, is_point_in_polygon, haversine_distance_km
from backend.app.simulation.anomaly_engine import ConflictAlertClassifier
from backend.app.services.supabase_client import get_supabase_client
from backend.app.services.alert_writer import write_field_alert, alert_already_recorded

logger = logging.getLogger("tygris.patrol_alerts")

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")

# Alert levels a transition INTO should raise an alert for. Improving back
# to SAFE never raises one — leaving the safe state is the event worth
# flagging.
ESCALATION_LEVELS = {"CAUTION", "CRITICAL"}


def classify_zone(lat: float, lon: float) -> str:
    """Same CORE/BUFFER/OUTSIDE classification as
    PenchEnvironment.classify_zone, but using the module-level boundary
    polygons directly so this doesn't need to build the full simulation's
    2km sampling grid on every poll tick."""
    if is_point_in_polygon(lat, lon, CORE_BOUNDARY):
        return "CORE"
    elif is_point_in_polygon(lat, lon, BUFFER_BOUNDARY):
        return "BUFFER"
    return "OUTSIDE"


def distance_to_nearest_village_km(lat: float, lon: float) -> float:
    """Same as PenchEnvironment.get_distance_to_nearest_village, using the
    module-level village list directly to skip building the sampling grid."""
    return min(haversine_distance_km(lat, lon, v["lat"], v["lon"]) for v in VILLAGES_44)


def classify_point_risk(lat: float, lon: float) -> Dict[str, Any]:
    """Runs one GPS point through the same conflict-risk taxonomy real tiger
    sightings are classified with, covering buffer/core zone AND village
    proximity in a single, already-calibrated decision (see
    ConflictAlertClassifier.classify_sighting_threat's thresholds:
    <=0.5km / <=1.2km village proximity, OUTSIDE / BUFFER zone)."""
    zone = classify_zone(lat, lon)
    village_km = distance_to_nearest_village_km(lat, lon)
    result = ConflictAlertClassifier.classify_sighting_threat(
        lat=lat, lon=lon, zone=zone,
        dist_to_nearest_village_km=village_km,
        dist_to_nearest_water_km=0.0,  # unused by the classifier's branches
    )
    result["zone"] = zone
    result["village_km"] = round(village_km, 2)
    return result


def _write_patrol_risk_alert(patrol_id: str, ranger_id: Any, point: Dict[str, Any], risk: Dict[str, Any]) -> None:
    reason = f"Ranger patrol {patrol_id[:8]} (ranger {ranger_id or 'unknown'}): {risk['reason']}"
    write_field_alert(
        event_prefix="EVT_PATROL_",
        alert_level=risk["alert_level"],
        threat_reason=reason,
        source_ref=point.get("point_id"),
        latitude=point.get("lat"),
        longitude=point.get("lon"),
        zone=risk["zone"],
        timestamp=point.get("timestamp"),
        anomaly_class=risk.get("anomaly_type"),
    )


def run_pending_patrol_zone_checks() -> Dict[str, Any]:
    """
    Finds active patrols, walks each one's GPS points in order, and raises a
    `sightings` alert row for every SAFE -> CAUTION/CRITICAL (or
    CAUTION -> CRITICAL) transition — buffer/reserve-boundary crossing or
    village-proximity approach alike — that hasn't already been recorded.
    Shared by the manual endpoint (routes_patrol.py) and the background
    polling loop in main.py.
    """
    if not os.path.exists(DB_PATH):
        return {"processed": 0, "configured": True, "error": "pench_unified.db not found"}

    client = get_supabase_client()
    if client is None:
        return {"processed": 0, "configured": False}

    try:
        patrols_resp = client.table("patrols").select("patrol_id, ranger_id").eq("status", "active").execute()
    except Exception as exc:
        logger.warning(f"[patrol-alerts] Failed to fetch active patrols: {exc}")
        return {"processed": 0, "configured": True, "error": str(exc)}

    active_patrols = getattr(patrols_resp, "data", None) or []
    if not active_patrols:
        return {"processed": 0, "configured": True}

    ranger_by_patrol = {p["patrol_id"]: p.get("ranger_id") for p in active_patrols}
    patrol_ids = list(ranger_by_patrol.keys())

    try:
        points_resp = (
            client.table("gps_track_points")
            .select("*")
            .in_("patrol_id", patrol_ids)
            .order("patrol_id")
            .order("sequence_num")
            .execute()
        )
    except Exception as exc:
        logger.warning(f"[patrol-alerts] Failed to fetch gps_track_points: {exc}")
        return {"processed": 0, "configured": True, "error": str(exc)}

    points: List[Dict[str, Any]] = getattr(points_resp, "data", None) or []
    by_patrol: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for pt in points:
        by_patrol[pt["patrol_id"]].append(pt)

    processed = 0
    for patrol_id, pts in by_patrol.items():
        prev_level = None
        for pt in pts:
            lat, lon = pt.get("lat"), pt.get("lon")
            if lat is None or lon is None:
                continue
            risk = classify_point_risk(lat, lon)
            level = risk["alert_level"]
            if prev_level is not None and level != prev_level and level in ESCALATION_LEVELS:
                point_id = pt.get("point_id")
                if point_id and not alert_already_recorded(point_id):
                    _write_patrol_risk_alert(patrol_id, ranger_by_patrol.get(patrol_id), pt, risk)
                    processed += 1
            prev_level = level

    return {"processed": processed, "configured": True}
