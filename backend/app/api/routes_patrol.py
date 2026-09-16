"""
FastAPI Router: Live Ranger Patrols

Exposes the currently-active patrols and their live GPS tracks (read from
Supabase, where the Flutter app writes them — see
`ActivePatrolController.pushLivePatrolUpdate` / `sync_queue_service.dart`),
and a manual trigger for the buffer-zone alert check that normally runs on
the background poll loop in main.py. Read-only from the backend's point of
view: the ranger app is the only writer of patrol/GPS data.
"""

import os
import sys
from typing import Optional
from fastapi import APIRouter, HTTPException, Query

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.services.supabase_client import get_supabase_client
from backend.app.services.patrol_alerts import run_pending_patrol_zone_checks

router = APIRouter(prefix="/api", tags=["Patrols"])


@router.get("/patrols/active")
def get_active_patrols(limit: int = Query(50, ge=1, le=200)):
    """
    Currently-active patrols with their live GPS track, most recently
    started first. Used by the frontend to show rangers moving on the map.
    """
    client = get_supabase_client()
    if client is None:
        return {"patrols": [], "configured": False}

    try:
        patrols_resp = (
            client.table("patrols")
            .select("*")
            .eq("status", "active")
            .order("start_time", desc=True)
            .limit(limit)
            .execute()
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Failed to fetch active patrols: {exc}")

    patrols = getattr(patrols_resp, "data", None) or []
    patrol_ids = [p["patrol_id"] for p in patrols]

    tracks_by_patrol = {}
    if patrol_ids:
        try:
            points_resp = (
                client.table("gps_track_points")
                .select("*")
                .in_("patrol_id", patrol_ids)
                .order("sequence_num")
                .execute()
            )
            for pt in getattr(points_resp, "data", None) or []:
                tracks_by_patrol.setdefault(pt["patrol_id"], []).append(pt)
        except Exception as exc:
            # Track fetch failing shouldn't hide the patrol list itself.
            tracks_by_patrol = {}

    for p in patrols:
        p["route"] = tracks_by_patrol.get(p["patrol_id"], [])

    return {"patrols": patrols, "configured": True}


@router.post("/patrols/zone-check/run-pending")
def post_run_pending_zone_check():
    """
    Manual "check now" endpoint: runs the same buffer-zone crossing check
    the background poll loop runs every interval, immediately.
    """
    result = run_pending_patrol_zone_checks()
    if not result.get("configured"):
        raise HTTPException(
            status_code=503,
            detail="Supabase not configured — set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY",
        )
    return result
