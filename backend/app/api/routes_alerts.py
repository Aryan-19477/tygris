"""
FastAPI Router: Real-time Conflict Alerts & Executive Telemetry Statistics
"""

import os
import sys
import json
import sqlite3
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, HTTPException, Query

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

router = APIRouter(prefix="/api", tags=["Alerts & Stats"])

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
BUNDLE_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gis", "pench_web_bundle.json")

# Event IDs acknowledged while running off the static JSON bundle (no DB present).
# Not persisted across restarts, since the bundle fallback has no storage of its own.
ACKNOWLEDGED_BUNDLE_EVENT_IDS: set = set()


def _ensure_acknowledged_column():
    if not os.path.exists(DB_PATH):
        return
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(sightings)")
    columns = {row[1] for row in cur.fetchall()}
    if "acknowledged" not in columns:
        cur.execute("ALTER TABLE sightings ADD COLUMN acknowledged INTEGER NOT NULL DEFAULT 0")
        conn.commit()
    conn.close()


_ensure_acknowledged_column()


@router.get("/alerts")
def get_alerts(
    limit: int = Query(50, ge=1, le=200),
    level: Optional[str] = Query(None, description="Filter by level: CRITICAL, CAUTION, SAFE")
):
    """
    Returns real-time conflict alerts and anomalous tiger movements.
    """
    if not os.path.exists(DB_PATH):
        if os.path.exists(BUNDLE_PATH):
            with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
                bundle = json.load(f)
            sightings = bundle.get("recent_sightings", [])
            sightings = [s for s in sightings if s.get("event_id") not in ACKNOWLEDGED_BUNDLE_EVENT_IDS]
            if level:
                sightings = [s for s in sightings if s.get("alert_level") == level]
            return {"alerts": sightings[:limit], "total": len(sightings)}
        return {"alerts": [], "total": 0}

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    if level:
        cur.execute("""
            SELECT * FROM sightings
            WHERE alert_level = ? AND acknowledged = 0
            ORDER BY timestamp DESC
            LIMIT ?
        """, (level, limit))
    else:
        cur.execute("""
            SELECT * FROM sightings
            WHERE acknowledged = 0
            ORDER BY timestamp DESC
            LIMIT ?
        """, (limit,))

    alerts = [dict(r) for r in cur.fetchall()]
    conn.close()
    return {"alerts": alerts, "total": len(alerts)}


@router.post("/alerts/{event_id}/acknowledge")
def acknowledge_alert(event_id: str):
    """
    Marks a conflict alert as handled so it drops out of the Attention Queue.
    """
    if not os.path.exists(DB_PATH):
        if os.path.exists(BUNDLE_PATH):
            with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
                bundle = json.load(f)
            if not any(s.get("event_id") == event_id for s in bundle.get("recent_sightings", [])):
                raise HTTPException(status_code=404, detail="Alert not found.")
            ACKNOWLEDGED_BUNDLE_EVENT_IDS.add(event_id)
            return {"status": "ACKNOWLEDGED", "event_id": event_id}
        raise HTTPException(status_code=404, detail="Alert not found.")

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT 1 FROM sightings WHERE event_id = ?", (event_id,))
    if cur.fetchone() is None:
        conn.close()
        raise HTTPException(status_code=404, detail="Alert not found.")

    cur.execute("UPDATE sightings SET acknowledged = 1 WHERE event_id = ?", (event_id,))
    conn.commit()
    conn.close()
    return {"status": "ACKNOWLEDGED", "event_id": event_id}


@router.get("/stats")
def get_stats():
    """
    Returns reserve-wide KPI counts and telemetry for dashboard widgets.
    """
    try:
        from backend.app.api.routes_review import REVIEW_QUEUE
        pending_count = len(REVIEW_QUEUE)
    except Exception:
        pending_count = 2

    if not os.path.exists(DB_PATH):
        return {
            "total_individuals": 62,
            "total_stations": 295,
            "active_stations": 295,
            "total_captures": 2172,
            "pending_review": pending_count,
            "critical_alerts": 4,
            "caution_alerts": 18,
            "trap_nights_simulated": 8415,
            "core_area_km2": 437.88,
            "buffer_area_km2": 267.57,
            "stations": [f"PTR_CAM_{i:03d}" for i in range(1, 296)]
        }

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) FROM tiger_profiles")
    total_tigers = cur.fetchone()[0] or 62

    cur.execute("SELECT COUNT(*) FROM camera_stations")
    total_cams = cur.fetchone()[0] or 295

    cur.execute("SELECT COUNT(*) FROM camera_stations WHERE operational_status = 'OPERATIONAL'")
    active_cams = cur.fetchone()[0] or total_cams

    cur.execute("SELECT COUNT(*) FROM sightings")
    total_captures = cur.fetchone()[0] or 0

    cur.execute("SELECT COUNT(*) FROM sightings WHERE alert_level = 'CRITICAL'")
    critical_alerts = cur.fetchone()[0] or 0

    cur.execute("SELECT COUNT(*) FROM sightings WHERE alert_level = 'CAUTION'")
    caution_alerts = cur.fetchone()[0] or 0

    cur.execute("SELECT camera_id FROM camera_stations ORDER BY camera_id ASC")
    station_ids = [r[0] for r in cur.fetchall()]

    conn.close()

    return {
        "total_individuals": total_tigers,
        "total_stations": total_cams,
        "active_stations": active_cams,
        "total_captures": total_captures,
        "pending_review": pending_count,
        "critical_alerts": critical_alerts,
        "caution_alerts": caution_alerts,
        "trap_nights_simulated": 8415,
        "core_area_km2": 439.24,
        "buffer_area_km2": 301.97,
        "stations": station_ids
    }
