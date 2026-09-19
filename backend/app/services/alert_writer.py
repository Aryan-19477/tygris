"""
Shared infrastructure for writing live field alerts into the `sightings`
table — the one place every trigger source lands, so they all surface
through the existing, unmodified `/api/alerts` endpoint and frontend
dashboard exactly like a camera-trap alert does:

- Buffer-zone / village-proximity crossings during an active ranger patrol
  (backend/app/services/patrol_alerts.py)
- Territory-change detections ("possible_move") from ranger field
  observations (backend/app/api/routes_ranger_ops.py)
- Live camera-trap identifications (backend/app/api/routes_identify.py)

Each caller supplies its own `source_ref` (a stable id for the specific
event that triggered the alert — a GPS point id, an observation id, a
camera event id) so the same trigger never gets inserted twice across
repeated polls.
"""

import os
import sys
import sqlite3
import uuid
from typing import Any, Optional

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")


def _ensure_source_ref_column():
    if not os.path.exists(DB_PATH):
        return
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(sightings)")
    columns = {row[1] for row in cur.fetchall()}
    if "source_ref" not in columns:
        # Dedup key: whatever event triggered this alert (a GPS point id, an
        # observation id, ...), so the same trigger is never inserted twice
        # across repeated polls.
        cur.execute("ALTER TABLE sightings ADD COLUMN source_ref TEXT")
        conn.commit()
    conn.close()


_ensure_source_ref_column()


def alert_already_recorded(source_ref: str) -> bool:
    if not source_ref or not os.path.exists(DB_PATH):
        return False
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT 1 FROM sightings WHERE source_ref = ? LIMIT 1", (source_ref,))
    found = cur.fetchone() is not None
    conn.close()
    return found


def write_field_alert(
    *,
    event_prefix: str,
    alert_level: str,
    threat_reason: str,
    source_ref: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    zone: Optional[str] = None,
    tiger_id: Optional[str] = None,
    camera_id: Optional[str] = None,
    timestamp: Optional[str] = None,
    anomaly_class: Optional[str] = None,
) -> Optional[str]:
    """Inserts one alert row into `sightings`, skipping it if `source_ref`
    has already produced an alert. Returns the new event_id, or None if it
    was a duplicate or the DB doesn't exist. `anomaly_class` should be one
    of the keys in ANOMALY_TAXONOMY (anomaly_engine.py) when the caller
    wants this alert to resolve to a named category via categorize_anomaly
    (village proximity / male territory conflict / unidentified tiger)."""
    if not os.path.exists(DB_PATH):
        return None
    if alert_already_recorded(source_ref):
        return None

    import datetime
    ts = timestamp or datetime.datetime.now().isoformat(timespec="seconds")

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    evt_id = f"{event_prefix}{uuid.uuid4().hex[:6].upper()}"
    cur.execute("""
        INSERT INTO sightings
        (event_id, tiger_id, camera_id, timestamp, latitude, longitude, zone, alert_level, threat_reason, source_ref, anomaly_class)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (evt_id, tiger_id, camera_id, ts, latitude, longitude, zone, alert_level, threat_reason, source_ref, anomaly_class))
    conn.commit()
    conn.close()
    return evt_id
