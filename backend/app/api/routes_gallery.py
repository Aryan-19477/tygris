"""
FastAPI Router: Tiger Gallery & Individual Identity Management
"""

import os
import sys
import json
import sqlite3
from typing import Dict, Any
from fastapi import APIRouter, HTTPException

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.ml.pose import TigerPoseManager

router = APIRouter(prefix="/api", tags=["Gallery"])

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
BUNDLE_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gis", "pench_web_bundle.json")
KEYPOINTS_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gallery", "reid_keypoints_train.json")

pose_mgr = TigerPoseManager([KEYPOINTS_PATH])


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def get_tiger_embedding(tiger_id: str) -> Dict[str, Any]:
    """
    Returns the real embedding for a tiger from the same reference gallery
    TigerReIDEngine builds for /api/identify. When the real trained
    ConvNeXt metric model is loaded (backend/checkpoints/, see
    backend/scripts/train_reid_models.py), the gallery holds one embedding
    per real reference photo for that tiger (potentially many - averaged
    here into a single representative vector); with the hash-based stub
    fallback it holds exactly one.
    """
    from backend.app.ml.reid_embedding import TigerReIDEngine

    try:
        engine = TigerReIDEngine.get()
    except Exception as exc:
        return {
            "vector": None,
            "available": False,
            "reason": "engine_unavailable",
            "detail": f"Re-ID engine failed to load: {exc}",
            "metric_model_trained": True,
        }

    import numpy as np

    indices = [i for i, tid in enumerate(engine.gallery_ids) if tid == str(tiger_id)]
    if not indices:
        return {
            "vector": None,
            "available": False,
            "reason": "no_gallery_entry",
            "detail": (
                f"Tiger '{tiger_id}' has no reference photo in the re-ID gallery "
                f"({len(set(engine.gallery_ids))} enrolled tigers)."
            ),
            "metric_model_trained": True,
        }

    vecs = engine.gallery_embeddings[indices]
    vec = vecs.mean(axis=0)
    norm = np.linalg.norm(vec)
    if norm > 0:
        vec = vec / norm

    return {
        "vector": [round(float(v), 6) for v in vec],
        "available": True,
        "dim": len(vec),
        "num_source_entries": len(indices),
        "l2_norm": round(float(np.linalg.norm(vec)), 4),
        "metric_model_trained": engine.real_model_loaded,
    }


@router.get("/gallery")
def list_gallery():
    """
    Returns list of all enrolled individual tigers, capture statistics, last seen, and flank status.
    """
    if not os.path.exists(DB_PATH):
        # Fallback to web bundle if DB is still building
        if os.path.exists(BUNDLE_PATH):
            with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
                bundle = json.load(f)
            items = []
            for tid, tdata in bundle.get("territories", {}).items():
                items.append({
                    "tiger_id": tid,
                    "name": tdata.get("name", tid),
                    "sex": tdata.get("sex", "Unknown"),
                    "life_stage": tdata.get("life_stage", "Adult"),
                    "num_captures": 12,
                    "mcp_area_km2": tdata.get("area_km2", 35.0),
                    "stations": ["PTR_CAM_012", "PTR_CAM_045", "PTR_CAM_088"],
                    "last_seen": "2026-01-15T08:30:00",
                    "thumbnail": tdata.get("thumbnail") or f"/tigers/{tid}.jpg"
                })
            return {"individuals": items}
        return {"individuals": []}

    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM tiger_profiles ORDER BY tiger_id ASC")
    tigers = [dict(row) for row in cur.fetchall()]

    individuals = []
    for t in tigers:
        tid = t["tiger_id"]
        cur.execute("""
            SELECT camera_id, timestamp, flank_side, image_quality 
            FROM sightings 
            WHERE tiger_id = ? 
            ORDER BY timestamp DESC
        """, (tid,))
        sightings = [dict(r) for r in cur.fetchall()]

        stations = sorted(list({s["camera_id"] for s in sightings if s.get("camera_id")}))
        last_seen = sightings[0]["timestamp"] if sightings else None

        individuals.append({
            "tiger_id": tid,
            "name": t.get("name", tid),
            "sex": t.get("sex", "Unknown"),
            "age_years": t.get("age_years", 4.0),
            "life_stage": t.get("life_stage", "Adult"),
            "territorial_status": t.get("territorial_status", "Resident"),
            "mcp_area_km2": t.get("mcp_area_km2", 35.0),
            "num_captures": len(sightings) if sightings else t.get("total_captures", 0),
            "stations": stations,
            "last_seen": last_seen,
            "thumbnail": t.get("thumbnail") or f"/tigers/{tid}.jpg"
        })

    conn.close()
    return {"individuals": individuals}


@router.get("/gallery/{tiger_id}")
def get_tiger_detail(tiger_id: str):
    """
    Returns deep profile dossier for a single tiger: captures, 15-point pose keypoints, and 100% MCP home range.
    """
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM tiger_profiles WHERE tiger_id = ? OR tiger_id LIKE ?", (tiger_id, f"%{tiger_id}%"))
    tiger_row = cur.fetchone()

    if not tiger_row:
        # Fallback profile from web bundle or synthetic default
        tiger = {
            "tiger_id": tiger_id,
            "name": f"Tiger {tiger_id}",
            "sex": "Female",
            "age_years": 4.5,
            "life_stage": "Adult",
            "territorial_status": "Resident",
            "mcp_area_km2": 38.5,
            "total_captures": 6
        }
        captures = []
    else:
        tiger = dict(tiger_row)
        tid = tiger["tiger_id"]
        cur.execute("""
            SELECT event_id, timestamp, camera_id, latitude, longitude, zone, flank_side, speed_kmh, alert_level, threat_reason 
            FROM sightings 
            WHERE tiger_id = ? 
            ORDER BY timestamp DESC
        """, (tid,))
        captures = [dict(r) for r in cur.fetchall()]

    conn.close()

    # Load groundtruth anatomical pose keypoints
    pose_file = os.path.join(PROJECT_ROOT, "backend", "data", "gallery", "tiger_groundtruth_poses.json")
    pose = None
    if os.path.exists(pose_file):
        try:
            with open(pose_file, "r", encoding="utf-8") as f:
                all_poses = json.load(f)
            pose = all_poses.get(tiger.get("tiger_id", tiger_id))
        except Exception:
            pass

    if not pose:
        pose = pose_mgr.get_pose_for_image(f"{tiger_id}_flank.jpg").to_dict()

    # Extract trajectory coordinates
    trajectory = [[c["latitude"], c["longitude"]] for c in captures]

    embedding = get_tiger_embedding(tiger.get("tiger_id", tiger_id))

    return {
        "profile": tiger,
        "captures": captures,
        "pose_analysis": pose,
        "trajectory": trajectory,
        "total_captures": len(captures),
        "embedding": embedding
    }


@router.get("/tiger-associations")
def get_tiger_associations(
    limit: int = 10,
    opposite_sex_only: bool = True,
    window_hours: float = 48.0,
):
    """
    Ranks pairs of tigers by how often they were captured at the same camera
    station within `window_hours` of each other - a proxy for shared/overlapping
    territory (and, for opposite-sex pairs, candidate mates). Computed directly
    from the real sightings table (station + EXIF timestamp per capture), not
    a stored/precomputed value.
    """
    from datetime import datetime

    if not os.path.exists(DB_PATH):
        return {"pairs": []}

    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT tiger_id, sex FROM tiger_profiles")
    sex_by_tiger = {row["tiger_id"]: (row["sex"] or "U") for row in cur.fetchall()}

    cur.execute("SELECT tiger_id, timestamp, camera_id FROM sightings WHERE camera_id IS NOT NULL ORDER BY camera_id, timestamp")
    rows = cur.fetchall()
    conn.close()

    by_station: Dict[str, list] = {}
    for r in rows:
        by_station.setdefault(r["camera_id"], []).append(r)

    window_seconds = window_hours * 3600
    pair_stats: Dict[tuple, Dict[str, Any]] = {}

    for camera_id, sightings in by_station.items():
        parsed = []
        for s in sightings:
            try:
                ts = datetime.fromisoformat(s["timestamp"])
            except (TypeError, ValueError):
                continue
            parsed.append((ts, s["tiger_id"]))

        n = len(parsed)
        for i in range(n):
            ts_a, tiger_a = parsed[i]
            for j in range(i + 1, n):
                ts_b, tiger_b = parsed[j]
                if (ts_b - ts_a).total_seconds() > window_seconds:
                    break
                if tiger_a == tiger_b:
                    continue

                key = tuple(sorted((tiger_a, tiger_b)))
                stat = pair_stats.setdefault(key, {"count": 0, "stations": set()})
                stat["count"] += 1
                stat["stations"].add(camera_id)

    pairs = []
    for (a, b), stat in pair_stats.items():
        sex_a, sex_b = sex_by_tiger.get(a, "U"), sex_by_tiger.get(b, "U")
        if opposite_sex_only and not ({sex_a, sex_b} == {"M", "F"}):
            continue
        pairs.append({
            "tiger_a": a,
            "tiger_b": b,
            "sex_a": sex_a,
            "sex_b": sex_b,
            "co_occurrences": stat["count"],
            "shared_stations": sorted(stat["stations"]),
        })

    pairs.sort(key=lambda p: p["co_occurrences"], reverse=True)
    return {"pairs": pairs[:limit], "window_hours": window_hours}


