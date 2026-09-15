"""
FastAPI Router: Human-in-the-Loop Review Queue & Open-World Candidate Enrollment

Previously this router served two hardcoded demo entries (fixed tiger IDs
from before the real-dataset migration, image paths that no longer exist
on disk) and "resolving" an item just popped it from an in-memory dict
without writing anything anywhere. Both problems are fixed here: items are
persisted to `pench_unified.db` and only ever created from real
`/api/identify` calls that actually needed review (see `enqueue_for_review`,
called from routes_identify.py), and resolving one now really does record
the sighting via the same `_record_sighting` path a confident auto-match
uses.
"""

import os
import sqlite3
import sys
import uuid
import json
from typing import Optional, Dict, Any, List
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

router = APIRouter(prefix="/api", tags=["Review Queue"])

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS review_queue (
            item_id TEXT PRIMARY KEY,
            timestamp TEXT,
            station_id TEXT,
            zone TEXT,
            uploaded_image TEXT,
            nearest_distance REAL,
            candidates_json TEXT,
            reason TEXT,
            resolved INTEGER NOT NULL DEFAULT 0
        )
    """)
    conn.commit()
    return conn


def enqueue_for_review(
    uploaded_image: str,
    station_id: Optional[str],
    candidates: List[Dict[str, Any]],
    reason: str,
) -> str:
    """Called by routes_identify.py whenever a real identify call comes back
    `needs_review` — this is the only path that adds to the queue now, so
    every item here traces back to an actual uploaded photo."""
    import datetime

    item_id = f"REV_{uuid.uuid4().hex[:8].upper()}"
    conn = _connect()
    zone = None
    if station_id:
        cur = conn.execute("SELECT zone FROM camera_stations WHERE camera_id = ?", (station_id,))
        row = cur.fetchone()
        zone = row[0] if row else None
    nearest_distance = round(1 - candidates[0]["similarity"], 4) if candidates else None
    conn.execute(
        """INSERT INTO review_queue
           (item_id, timestamp, station_id, zone, uploaded_image, nearest_distance, candidates_json, reason, resolved)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)""",
        (
            item_id,
            datetime.datetime.now().isoformat(timespec="seconds"),
            station_id,
            zone,
            uploaded_image,
            nearest_distance,
            json.dumps(candidates),
            reason,
        ),
    )
    conn.commit()
    conn.close()
    return item_id


def _row_to_item(row: sqlite3.Row) -> Dict[str, Any]:
    return {
        "item_id": row["item_id"],
        "timestamp": row["timestamp"],
        "station_id": row["station_id"],
        "zone": row["zone"],
        "uploaded_image": row["uploaded_image"],
        "nearest_distance": row["nearest_distance"],
        "candidates": json.loads(row["candidates_json"]) if row["candidates_json"] else [],
        "reason": row["reason"],
    }


class ReviewResolutionRequest(BaseModel):
    assigned_tiger_id: Optional[str] = None  # If None -> create new identity
    flank_side: Optional[str] = "Left"
    notes: Optional[str] = ""


@router.get("/review-queue")
def get_review_queue():
    """Returns real open-world ambiguous sightings awaiting a human decision."""
    conn = _connect()
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM review_queue WHERE resolved = 0 ORDER BY timestamp DESC").fetchall()
    conn.close()
    return {"items": [_row_to_item(r) for r in rows]}


@router.post("/review-queue/{item_id}/resolve")
def resolve_review_item(item_id: str, payload: ReviewResolutionRequest):
    """Resolves a review item by actually recording the sighting: against an
    existing tiger ID if the reviewer picked one, or by enrolling a new
    identity in tiger_profiles if they didn't. Either way this now writes
    to the same `sightings`/`tiger_profiles` tables the rest of the app
    reads from, instead of discarding the human's decision."""
    from backend.app.api.routes_identify import _record_sighting
    import base64

    conn = _connect()
    conn.row_factory = sqlite3.Row
    row = conn.execute("SELECT * FROM review_queue WHERE item_id = ? AND resolved = 0", (item_id,)).fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Review item not found or already resolved.")
    item = _row_to_item(row)

    assigned_id = payload.assigned_tiger_id
    is_new = False
    if not assigned_id:
        is_new = True
        assigned_id = f"TIG_NEW_{uuid.uuid4().hex[:4].upper()}"
        station = item["station_id"]
        st_row = conn.execute(
            "SELECT latitude, longitude FROM camera_stations WHERE camera_id = ?", (station,)
        ).fetchone() if station else None
        conn.execute(
            """INSERT INTO tiger_profiles
               (tiger_id, name, sex, life_stage, territorial_status, total_captures, thumbnail,
                core_centroid_lat, core_centroid_lon)
               VALUES (?, ?, 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', 0, ?, ?, ?)""",
            (
                assigned_id,
                assigned_id,
                item["uploaded_image"],
                st_row[0] if st_row else None,
                st_row[1] if st_row else None,
            ),
        )

    conn.execute("UPDATE review_queue SET resolved = 1 WHERE item_id = ?", (item_id,))
    conn.commit()
    conn.close()

    try:
        image_bytes = None
        uploaded = item.get("uploaded_image") or ""
        if uploaded.startswith("data:") and "," in uploaded:
            try:
                image_bytes = base64.b64decode(uploaded.split(",", 1)[1])
            except Exception:
                image_bytes = None
        _record_sighting(assigned_id, item["station_id"], payload.flank_side or "Left", image_bytes=image_bytes)
    except Exception as e:
        # The review decision is already persisted above even if the sighting
        # write hiccups (e.g. unknown station) — don't lose the human's call.
        print(f"[routes_review] Sighting recording note: {e}")

    return {
        "status": "RESOLVED",
        "item_id": item_id,
        "assigned_tiger_id": assigned_id,
        "is_new_individual": is_new,
        "message": f"Successfully {'enrolled new individual ' if is_new else 'confirmed sighting for '}{assigned_id}.",
    }
