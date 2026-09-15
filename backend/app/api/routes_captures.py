"""
FastAPI Router: Capture Log

A browsable, filterable history of every real recorded sighting — the
"Capture Log" item from docs/ux-mockups/platform-roadmap.html's roadmap,
which was planned but never built. Before this, the only ways to see a
tiger's sightings were the per-tiger dossier (one tiger at a time, no
photos — see routes_gallery.py) or the review queue (only the handful of
items still awaiting a human decision). Nothing let you browse everything
that's actually been captured, across cameras and tigers, with the real
photo.
"""

import os
import sqlite3
import sys
from typing import Optional
from fastapi import APIRouter, Query

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

router = APIRouter(prefix="/api", tags=["Capture Log"])

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")


@router.get("/captures")
def list_captures(
    limit: int = Query(40, ge=1, le=200),
    before: Optional[str] = Query(None, description="ISO timestamp cursor — returns captures strictly before this"),
    camera_id: Optional[str] = Query(None),
    tiger_id: Optional[str] = Query(None),
):
    """Paginated, filterable capture history, most recent first. Every row
    is a real row from `sightings` — nothing here is synthetic."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    clauses = []
    params: list = []
    if before:
        clauses.append("s.timestamp < ?")
        params.append(before)
    if camera_id:
        clauses.append("s.camera_id = ?")
        params.append(camera_id)
    if tiger_id:
        clauses.append("s.tiger_id = ?")
        params.append(tiger_id)
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""

    cur.execute(
        f"""
        SELECT s.event_id, s.tiger_id, t.name AS tiger_name, s.camera_id, s.zone,
               s.timestamp, s.flank_side, s.alert_level, s.image_path, t.thumbnail
        FROM sightings s
        LEFT JOIN tiger_profiles t ON t.tiger_id = s.tiger_id
        {where}
        ORDER BY s.timestamp DESC
        LIMIT ?
        """,
        (*params, limit + 1),
    )
    rows = cur.fetchall()
    conn.close()

    has_more = len(rows) > limit
    rows = rows[:limit]
    items = [
        {
            "event_id": r["event_id"],
            "tiger_id": r["tiger_id"],
            "tiger_name": r["tiger_name"],
            "camera_id": r["camera_id"],
            "zone": r["zone"],
            "timestamp": r["timestamp"],
            "flank_side": r["flank_side"],
            "alert_level": r["alert_level"],
            "image_url": r["image_path"] or r["thumbnail"] or (f"/tigers/{r['tiger_id']}.jpg" if r["tiger_id"] else None),
        }
        for r in rows
    ]
    return {
        "items": items,
        "next_before": items[-1]["timestamp"] if (has_more and items) else None,
    }
