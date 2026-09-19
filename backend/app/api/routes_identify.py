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
        "load_error": engine.load_error,
    }


CAPTURES_DIR = os.path.join(PROJECT_ROOT, "backend", "data", "captures")


def _save_capture_image(event_id: str, image_bytes: bytes) -> str:
    """Persists the actual captured photo to disk so it can be shown later
    in the Capture Log — previously every recorded sighting kept metadata
    only and threw the image away, so there was nowhere to browse real
    frames. Returns the path clients should fetch as `/captures/<file>`
    (served by the StaticFiles mount in main.py)."""
    os.makedirs(CAPTURES_DIR, exist_ok=True)
    filename = f"{event_id}.jpg"
    with open(os.path.join(CAPTURES_DIR, filename), "wb") as f:
        f.write(image_bytes)
    return f"/captures/{filename}"


def _record_sighting(
    tiger_id: str,
    station: Optional[str],
    flank: str = "Left",
    image_bytes: Optional[bytes] = None,
) -> dict:
    """Logs an identified sighting to the real sightings table at the
    station's actual coordinates, same as the previous pipeline did. When
    the caller has the actual photo (a live /api/identify call, or a
    resolved review item), it's saved to disk and linked via image_path so
    the Capture Log has a real frame to show, not just metadata."""
    import sqlite3
    import datetime
    from backend.app.simulation.anomaly_engine import ConflictAlertClassifier

    st_id = station
    db_path = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    st_row = None
    if st_id:
        cur.execute("SELECT latitude, longitude, zone, nearest_village_km, nearest_water_km FROM camera_stations WHERE camera_id = ?", (st_id,))
        st_row = cur.fetchone()

    # No real station means no real fix for this sighting. Previously this
    # fell back to a fake "PTR_CAM_014" camera and the reserve's map-center
    # coordinates (21.65, 79.25) for every unlocated identification, which
    # silently gave every tiger identified this way an identical phantom
    # sighting — collapsing all of their MCP territory polygons onto that
    # one shared point instead of leaving the sighting unlocated.
    lat = st_row[0] if st_row else None
    lon = st_row[1] if st_row else None
    zone = st_row[2] if st_row else "CORE"
    village_km = st_row[3] if st_row and st_row[3] is not None else 99.0
    water_km = st_row[4] if st_row and st_row[4] is not None else 0.0

    # Same conflict-risk taxonomy live ranger-GPS alerts use (see
    # patrol_alerts.py) — a camera-trap tiger sighting near a village is a
    # human-wildlife-conflict trigger just as much as a ranger's own
    # proximity, so both paths should agree on thresholds/wording.
    risk = ConflictAlertClassifier.classify_sighting_threat(
        lat=lat, lon=lon, zone=zone,
        dist_to_nearest_village_km=village_km,
        dist_to_nearest_water_km=water_km,
    )

    ts = datetime.datetime.now().isoformat(timespec="seconds")
    evt_id = f"EVT_LIVE_{uuid.uuid4().hex[:6].upper()}"
    image_path = _save_capture_image(evt_id, image_bytes) if image_bytes else None

    cur.execute("""
        INSERT INTO sightings
        (event_id, tiger_id, camera_id, timestamp, latitude, longitude, zone, flank_side, speed_kmh, image_quality, alert_level, threat_reason, image_path, anomaly_class)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (evt_id, tiger_id, st_id, ts, lat, lon, zone, flank, 3.5, 0.95, risk["alert_level"], f"{risk['reason']} (Live Camera Scan at {st_id})", image_path, risk["anomaly_type"]))

    cur.execute("UPDATE tiger_profiles SET total_captures = total_captures + 1 WHERE tiger_id = ?", (tiger_id,))
    conn.commit()
    conn.close()

    # A tiger identified near a village is already flagged above via
    # ConflictAlertClassifier. Separately, check whether this sighting puts
    # two resident males within fight-risk range of each other (see
    # territory_conflict.py) — village proximity and male-male conflict are
    # independent triggers, so both can fire off the same sighting.
    try:
        from backend.app.services.territory_conflict import check_male_territory_conflict
        check_male_territory_conflict(tiger_id, st_id, ts)
    except Exception as e:
        print(f"[routes_identify] Male-territory-conflict check note: {e}")

    return {"recorded_event_id": evt_id, "recorded_status": "SAVED_TO_GRAPH"}


def _write_unidentified_alert(station: Optional[str], review_item_id: str, reason: str) -> None:
    """Every `needs_review` identify() result is, by definition, a tiger the
    gallery couldn't confidently place — surface that in the same
    `/api/alerts` feed the village-proximity and male-conflict triggers use
    (tagged "UNIDENTIFIED_TIGER"), so a ranger sees it in the main alert
    queue without having to separately remember to check the review queue.
    `source_ref` ties this 1:1 to the review item so re-polling the same
    photo never double-alerts."""
    import sqlite3
    import datetime
    from backend.app.services.alert_writer import write_field_alert

    lat = lon = zone = None
    if station:
        db_path = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT latitude, longitude, zone FROM camera_stations WHERE camera_id = ?", (station,))
        row = cur.fetchone()
        conn.close()
        if row:
            lat, lon, zone = row

    write_field_alert(
        event_prefix="EVT_UNID_",
        alert_level="CAUTION",
        threat_reason=f"Unidentified tiger — no gallery match cleared the auto-accept threshold. {reason}",
        source_ref=f"REVIEW_{review_item_id}",
        latitude=lat,
        longitude=lon,
        zone=zone,
        camera_id=station,
        timestamp=datetime.datetime.now().isoformat(timespec="seconds"),
        anomaly_class="UNIDENTIFIED_TIGER",
    )


def _finalize_identification(result: dict, station: Optional[str], contents: bytes) -> dict:
    """Shared post-processing for a completed identify() result, regardless
    of whether the embedding + gallery match ran server-side (TigerReIDEngine)
    or client-side (browser ONNX pipeline against /gallery-data). Records
    auto-matched sightings and enqueues low-confidence ones for review so
    both paths feed the same Capture Log / review queue."""
    if result.get("decision") == "auto_match" and result.get("tiger_id"):
        try:
            result.update(_record_sighting(result["tiger_id"], station, image_bytes=contents))
        except Exception as e:
            print(f"[routes_identify] Sighting recording note: {e}")
    elif result.get("decision") == "needs_review":
        try:
            from backend.app.api.routes_review import enqueue_for_review

            candidates = result.get("candidates") or []
            top = candidates[0] if candidates else None
            reason = (
                f"Open-World Gating: top candidate {top['tiger_id']} at "
                f"{round(top['similarity'] * 100)}% similarity, below the "
                f"{round((result.get('auto_accept_threshold') or 0) * 100)}% auto-accept floor."
                if top
                else "No candidate cleared the review floor."
            )
            result["review_item_id"] = enqueue_for_review(
                uploaded_image=result["uploaded_image"],
                station_id=station,
                candidates=candidates,
                reason=reason,
            )
            _write_unidentified_alert(station, result["review_item_id"], reason)
        except Exception as e:
            print(f"[routes_identify] Review-queue recording note: {e}")

    return result


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

    return _finalize_identification(result, station, contents)


@router.post("/identify/finalize")
async def identify_finalize(
    file: UploadFile = File(...),
    decision: str = Query(...),
    status: str = Query(...),
    tiger_id: Optional[str] = Query(None),
    predicted_tiger_id: Optional[str] = Query(None),
    confidence: float = Query(0.0),
    candidates_json: str = Query("[]"),
    gallery_size: int = Query(0),
    auto_accept_threshold: Optional[float] = Query(None),
    review_floor: Optional[float] = Query(None),
    station: Optional[str] = Query(None, description="Camera station ID (e.g. PTR_CAM_014)"),
):
    """
    Records/reviews a match that was already computed client-side (browser
    ONNX inference against /gallery-data/trained_gallery.json). Keeps the
    Capture Log, sighting DB, and review queue behaving identically whether
    the embedding + gallery match ran on this server or on the user's own
    device — see _finalize_identification.
    """
    import json as _json

    try:
        contents = await file.read()
        Image.open(io.BytesIO(contents)).convert("RGB")  # validates it's a real image
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image file: {e}")

    try:
        candidates = _json.loads(candidates_json)
    except Exception:
        candidates = []

    result = {
        "decision": decision,
        "status": status,
        "tiger_id": tiger_id,
        "predicted_tiger_id": predicted_tiger_id,
        "confidence": confidence,
        "candidates": candidates,
        "gallery_size": gallery_size,
        "auto_accept_threshold": auto_accept_threshold,
        "review_floor": review_floor,
        "model_status": "trained-client-onnx",
        "uploaded_image": "data:image/jpeg;base64," + __import__("base64").b64encode(contents).decode("utf-8"),
        "station_id": station,
    }

    return _finalize_identification(result, station, contents)


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
