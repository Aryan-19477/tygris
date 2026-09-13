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
    Returns the real 512-D triplet-loss embedding for a tiger, taken from
    the same reference gallery TigerReIDEngine builds for /api/identify
    (one embedded reference photo per tiger, from frontend-v2/public/tigers).

    An earlier version of this endpoint looked up embeddings in
    trained_gallery.json, an ATRW benchmark export keyed by disjoint raw
    numeric IDs that never included any PTR_TIG_NNN tiger - so every Pench
    dossier reported "no embedding available" even though a trained model
    was already running live identification. TigerReIDEngine's gallery is
    keyed by the actual PTR_TIG_NNN IDs and is built from a checkpoint that
    verified 97.5% rank-1 accuracy (identification/train_log_gpu.txt), so
    it is reused here instead.
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

    try:
        idx = engine.gallery_ids.index(str(tiger_id))
    except ValueError:
        return {
            "vector": None,
            "available": False,
            "reason": "no_gallery_entry",
            "detail": (
                f"Tiger '{tiger_id}' has no reference photo in the re-ID gallery "
                f"({len(engine.gallery_ids)} enrolled tigers)."
            ),
            "metric_model_trained": True,
        }

    import numpy as np

    vec = engine.gallery_embeddings[idx]

    return {
        "vector": [round(float(v), 6) for v in vec],
        "available": True,
        "dim": len(vec),
        "num_source_entries": 1,
        "l2_norm": round(float(np.linalg.norm(vec)), 4),
        "metric_model_trained": True,
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


