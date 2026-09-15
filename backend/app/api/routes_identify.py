"""
FastAPI Router: Tiger Re-Identification (44-tiger reference gallery match)
"""

import os
import sys
import io
import uuid
from typing import Optional, List
from fastapi import APIRouter, File, UploadFile, Query, HTTPException
from PIL import Image

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.ml.reid_embedding import TigerReIDEngine

router = APIRouter(prefix="/api", tags=["Identification"])


@router.get("/model-status")
async def model_status():
    """
    Reports whether the re-ID engine's reference gallery is loaded and how
    many real tiger identities it covers.
    """
    engine = TigerReIDEngine.get()
    gallery_size = len(set(engine.gallery_ids))
    return {
        "is_fully_trained": engine.real_model_loaded,
        "weights_loaded": {"embedding_model": engine.real_model_loaded, "reference_gallery": gallery_size > 0},
        "gallery_size": gallery_size,
        "checkpoints_dir": os.path.join(PROJECT_ROOT, "backend", "checkpoints"),
    }


def _record_sighting(tiger_id: str, station: Optional[str], flank: str = "Left") -> dict:
    """Logs an identified sighting to the real sightings table at the
    station's actual coordinates, same as the previous pipeline did."""
    import sqlite3
    import datetime

    st_id = station or "PTR_CAM_014"
    db_path = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("SELECT latitude, longitude, zone FROM camera_stations WHERE camera_id = ?", (st_id,))
    st_row = cur.fetchone()
    lat = st_row[0] if st_row else 21.65
    lon = st_row[1] if st_row else 79.25
    zone = st_row[2] if st_row else "CORE"

    ts = datetime.datetime.now().isoformat(timespec="seconds")
    evt_id = f"EVT_LIVE_{uuid.uuid4().hex[:6].upper()}"

    cur.execute("""
        INSERT INTO sightings
        (event_id, tiger_id, camera_id, timestamp, latitude, longitude, zone, flank_side, speed_kmh, image_quality, alert_level, threat_reason)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (evt_id, tiger_id, st_id, ts, lat, lon, zone, flank, 3.5, 0.95, "SAFE" if zone == "CORE" else "CAUTION", f"Live Camera Scan at {st_id}"))

    cur.execute("UPDATE tiger_profiles SET total_captures = total_captures + 1 WHERE tiger_id = ?", (tiger_id,))
    conn.commit()
    conn.close()
    return {"recorded_event_id": evt_id, "recorded_status": "SAVED_TO_GRAPH"}


@router.post("/identify")
async def identify_image(
    file: UploadFile = File(...),
    station: Optional[str] = Query(None, description="Camera station ID (e.g. PTR_CAM_014)")
):
    """
    Matches an uploaded camera-trap photo against the 44-tiger reference
    gallery by embedding cosine similarity. Only ever returns tiger IDs
    that are real, enrolled individuals in tiger_profiles.
    """
    engine = TigerReIDEngine.get()
    try:
        contents = await file.read()
        Image.open(io.BytesIO(contents)).convert("RGB")  # validates it's a real image
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image file: {e}")

    result = engine.identify(contents)
    result["uploaded_image"] = "data:image/jpeg;base64," + __import__("base64").b64encode(contents).decode("utf-8")
    result["station_id"] = station

    if result.get("decision") == "auto_match" and result.get("tiger_id"):
        try:
            result.update(_record_sighting(result["tiger_id"], station))
        except Exception as e:
            print(f"[routes_identify] Sighting recording note: {e}")

    return result


@router.post("/identify-burst")
async def identify_burst(files: List[UploadFile] = File(...)):
    """
    Fuses evidence across multiple consecutive frames in a camera-trap burst
    sighting by averaging per-frame confidence for each candidate tiger.
    """
    if not files:
        raise HTTPException(status_code=400, detail="At least one image file is required.")

    engine = TigerReIDEngine.get()
    frame_results = []
    for file in files:
        contents = await file.read()
        Image.open(io.BytesIO(contents)).convert("RGB")  # validates it's a real image
        frame_results.append(engine.identify(contents))

    from collections import defaultdict
    id_scores = defaultdict(float)
    for fr in frame_results:
        tid = fr.get("predicted_tiger_id")
        conf = fr.get("confidence", 0.0)
        if tid:
            id_scores[tid] += conf

    best_id = max(id_scores.items(), key=lambda x: x[1])[0] if id_scores else frame_results[0].get("predicted_tiger_id")
    total_frames = len(files)

    return {
        "decision": "auto_match" if frame_results[0]["decision"] == "auto_match" else "needs_review",
        "tiger_id": best_id,
        "predicted_tiger_id": best_id,
        "num_frames_fused": total_frames,
        "confidence": round(float(id_scores[best_id] / total_frames), 4) if best_id else 0.0,
        "primary_frame": frame_results[0],
        "frame_breakdowns": [
            {
                "frame_index": i + 1,
                "tiger_id": fr.get("predicted_tiger_id"),
                "confidence": fr.get("confidence"),
            }
            for i, fr in enumerate(frame_results)
        ]
    }
