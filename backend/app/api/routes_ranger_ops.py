"""
FastAPI Router: Ranger Field Ops — reading ranger patrol/observation data
back out of Supabase and computing the "is the resident tiger still here?"
territory-check intelligence against the existing camera-trap network.

The Ranger Flutter app writes into Supabase directly; this backend only
reads from it (polling — see main.py's background task) and writes
`territory_checks` rows back. There is no inbound webhook path since
Supabase is cloud-hosted and this server runs locally.
"""

import logging
from typing import Any, Dict, List
from fastapi import APIRouter, HTTPException

from backend.app.services.supabase_client import get_supabase_client
from backend.app.services.territory_check import run_territory_check

logger = logging.getLogger("tygris.ranger_ops")

router = APIRouter(prefix="/api/ranger", tags=["Ranger Ops"])

WILDLIFE_OBS_TYPES = {
    "wildlifeSighting",
    "wildlifeSign",
    "wildlife_sighting",
    "wildlife_sign",
}


def _require_client():
    client = get_supabase_client()
    if client is None:
        raise HTTPException(
            status_code=503,
            detail="Supabase not configured — set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY",
        )
    return client


@router.post("/territory-check/{observation_id}")
def post_territory_check(observation_id: str):
    """
    Fetches one observation from Supabase, runs the territory-check
    algorithm against the local camera-trap/sightings database, inserts
    the result into `territory_checks`, and returns the inserted row.
    """
    client = _require_client()

    try:
        resp = client.table("observations").select("*").eq("observation_id", observation_id).single().execute()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Failed to fetch observation from Supabase: {exc}")

    observation = getattr(resp, "data", None)
    if not observation:
        raise HTTPException(status_code=404, detail=f"Observation '{observation_id}' not found.")

    result = run_territory_check(observation)

    try:
        insert_resp = client.table("territory_checks").insert(result).execute()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Failed to write territory_checks row: {exc}")

    rows = getattr(insert_resp, "data", None) or []
    return rows[0] if rows else result


@router.get("/reports")
def get_reports():
    """
    Convenience endpoint for the Admin dashboard: recent patrols and
    observations from Supabase in one call, most recent first.
    """
    client = get_supabase_client()
    if client is None:
        return {"patrols": [], "observations": [], "configured": False}

    try:
        patrols_resp = client.table("patrols").select("*").order("created_at", desc=True).limit(100).execute()
    except Exception as exc:
        logger.warning(f"[ranger-ops] Failed to fetch patrols: {exc}")
        patrols_resp = None

    try:
        observations_resp = (
            client.table("observations").select("*").order("created_at", desc=True).limit(100).execute()
        )
    except Exception as exc:
        logger.warning(f"[ranger-ops] Failed to fetch observations: {exc}")
        observations_resp = None

    return {
        "patrols": getattr(patrols_resp, "data", None) or [],
        "observations": getattr(observations_resp, "data", None) or [],
        "configured": True,
    }


def _is_wildlife_obs_type(obs_type: Any) -> bool:
    return isinstance(obs_type, str) and obs_type in WILDLIFE_OBS_TYPES


def run_pending_territory_checks() -> Dict[str, Any]:
    """
    Finds wildlife-sighting/sign observations with no territory_checks row
    yet, runs the check for each, and inserts the results. Shared by the
    manual /run-pending endpoint and the background polling loop in main.py.
    """
    client = get_supabase_client()
    if client is None:
        return {"processed": 0, "configured": False}

    try:
        obs_resp = client.table("observations").select("*").order("created_at", desc=True).limit(500).execute()
    except Exception as exc:
        logger.warning(f"[ranger-ops] Failed to fetch observations for pending check: {exc}")
        return {"processed": 0, "configured": True, "error": str(exc)}

    observations: List[Dict[str, Any]] = getattr(obs_resp, "data", None) or []
    wildlife_obs = [o for o in observations if _is_wildlife_obs_type(o.get("obs_type"))]
    if not wildlife_obs:
        return {"processed": 0, "configured": True}

    try:
        checks_resp = client.table("territory_checks").select("observation_id").execute()
    except Exception as exc:
        logger.warning(f"[ranger-ops] Failed to fetch existing territory_checks: {exc}")
        return {"processed": 0, "configured": True, "error": str(exc)}

    already_checked = {row.get("observation_id") for row in (getattr(checks_resp, "data", None) or [])}
    pending = [o for o in wildlife_obs if o.get("observation_id") not in already_checked]

    processed = 0
    for obs in pending:
        try:
            result = run_territory_check(obs)
            client.table("territory_checks").insert(result).execute()
            processed += 1
        except Exception as exc:
            logger.warning(f"[ranger-ops] Territory check failed for {obs.get('observation_id')}: {exc}")

    return {"processed": processed, "configured": True, "pending_found": len(pending)}


@router.post("/territory-check/run-pending")
def post_run_pending():
    """
    Manual "catch up" endpoint: runs territory checks for every wildlife
    observation that doesn't have one yet. Also called by the background
    polling loop in main.py every 60 seconds.
    """
    result = run_pending_territory_checks()
    if not result.get("configured"):
        raise HTTPException(
            status_code=503,
            detail="Supabase not configured — set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY",
        )
    return result
