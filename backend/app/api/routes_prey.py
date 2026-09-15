"""
API Router for Pench Wildlife Prey Intelligence & Animal Identification Checker.
Follows prey-prd.md and prey-ml.md specifications.
"""

import json
import logging
from typing import Optional, Dict, Any, List
from fastapi import APIRouter, File, UploadFile, Form, HTTPException, Query
from pydantic import BaseModel

from backend.app.prey.pipeline import PreyDetectionPipeline, load_config, CONFIG_PATH
from backend.app.prey.insights_service import PreyInsightsService
from backend.app.prey.db import (
    insert_observation,
    query_observations,
    get_review_queue,
    resolve_review_item,
    get_db_connection
)

logger = logging.getLogger("tygris.prey.routes")
router = APIRouter(prefix="/api/prey", tags=["Prey Intelligence"])


class ObservationCreate(BaseModel):
    camera_id: str
    species: str
    species_confidence: float
    timestamp: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    bbox: Optional[List[int]] = None
    count: Optional[int] = 1
    sex: Optional[str] = "unknown"
    age_class: Optional[str] = "unknown"
    behaviour: Optional[str] = "unknown"
    behaviour_confidence: Optional[float] = 0.0
    image_quality: Optional[float] = 1.0
    lighting_condition: Optional[str] = "day"
    verification_status: Optional[str] = "ai_verified"
    notes: Optional[str] = None


class ReviewResolveRequest(BaseModel):
    action: str  # 'confirm', 'correct', 'reject'
    verified_species: Optional[str] = None
    verified_sex: Optional[str] = "unknown"
    verified_age: Optional[str] = "unknown"
    verified_behaviour: Optional[str] = "unknown"
    notes: Optional[str] = None
    reviewer_id: Optional[str] = "ranger_admin"


class ConfigUpdateRequest(BaseModel):
    auto_accept_threshold: Optional[float] = None
    review_floor: Optional[float] = None
    min_quality_score: Optional[float] = None
    prey_classifier_weights: Optional[str] = None


@router.post("/identify-check")
async def identify_check(
    file: UploadFile = File(...),
    camera_id: Optional[str] = Form(None),
    timestamp: Optional[str] = Form(None),
    record_observation: bool = Form(False)
):
    """
    Dedicated Animal Identify Checker.
    Runs 5-stage inference on input image:
    1. Image Quality Assessment
    2. General Wildlife Detector (YOLO)
    3. Multi-Species Crop Classifier & Attribute Extractor
    4. Confidence Calibration & Abstention (Auto / Review / Unknown)
    5. Annotation & Base64 rendering
    """
    try:
        contents = await file.read()
        pipeline = PreyDetectionPipeline.get_instance()
        result = pipeline.process_image(contents, camera_id=camera_id, timestamp=timestamp)

        saved_ids = []
        if record_observation and result.get("animals"):
            for a in result["animals"]:
                obs_data = {
                    "camera_id": camera_id or "PTR-FIELD-01",
                    "timestamp": timestamp,
                    "species": a["species"],
                    "species_confidence": a["species_confidence"],
                    "bbox": a["bbox"],
                    "count": a.get("count", 1),
                    "sex": a.get("sex", "unknown"),
                    "age_class": a.get("age_class", "unknown"),
                    "behaviour": a.get("behaviour", "unknown"),
                    "behaviour_confidence": a.get("behaviour_confidence", 0.0),
                    "image_quality": result.get("image_quality", {}).get("quality_score", 1.0),
                    "lighting_condition": result.get("image_quality", {}).get("lighting_condition", "day"),
                    "verification_status": "ai_verified" if a["decision"] == "auto_accepted" else "needs_review",
                    "review_reason": a.get("decision_reason")
                }
                obs_id = insert_observation(obs_data)
                saved_ids.append(obs_id)

        result["saved_observation_ids"] = saved_ids
        return result
    except Exception as exc:
        logger.exception("Identify check failed")
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/insights/summary")
def get_insights():
    """Returns dynamic ecological intelligence dashboard metrics."""
    try:
        return PreyInsightsService.get_full_insights()
    except Exception as exc:
        logger.exception("Failed to compute prey insights")
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/observations")
def list_observations(
    species: Optional[str] = None,
    camera_id: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0)
):
    """Query structured wildlife observations."""
    try:
        return query_observations(species=species, camera_id=camera_id, status=status, limit=limit, offset=offset)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/observations")
def create_observation(obs: ObservationCreate):
    """Manually or programmatically persist a verified wildlife observation."""
    try:
        obs_id = insert_observation(obs.model_dump())
        return {"success": True, "observation_id": obs_id}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/review-queue")
def list_review_queue(limit: int = Query(50, ge=1, le=100)):
    """Fetches items routed to human review queue."""
    try:
        return get_review_queue(limit=limit)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/review-queue/{review_id}/resolve")
def resolve_review(review_id: str, body: ReviewResolveRequest):
    """Resolves a human review queue item and logs to active learning."""
    try:
        success = resolve_review_item(
            review_id=review_id,
            action=body.action,
            verified_species=body.verified_species,
            verified_sex=body.verified_sex,
            verified_age=body.verified_age,
            verified_behaviour=body.verified_behaviour,
            notes=body.notes,
            reviewer_id=body.reviewer_id
        )
        if not success:
            raise HTTPException(status_code=404, detail="Review item not found")
        return {"success": True, "review_id": review_id, "action": body.action}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/config")
def get_pipeline_config():
    """Returns runtime pipeline thresholds and taxonomy."""
    return load_config()


@router.post("/config")
def update_pipeline_config(body: ConfigUpdateRequest):
    """Updates runtime thresholds or pluggable model paths."""
    config = load_config()
    if body.auto_accept_threshold is not None:
        config["thresholds"]["auto_accept_threshold"] = body.auto_accept_threshold
    if body.review_floor is not None:
        config["thresholds"]["review_floor"] = body.review_floor
    if body.min_quality_score is not None:
        config["thresholds"]["min_quality_score"] = body.min_quality_score
    if body.prey_classifier_weights is not None:
        config["models"]["prey_classifier_weights"] = body.prey_classifier_weights

    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)

    # Reload pipeline instance
    pipeline = PreyDetectionPipeline.get_instance()
    pipeline.config = config
    return {"success": True, "config": config}


@router.get("/export-training-data")
def export_training_data():
    """
    Exports human-reviewed active learning annotations formatted for future
    YOLO / PyTorch classifier fine-tuning.
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM prey_active_learning ORDER BY created_at DESC")
        rows = [dict(r) for r in cur.fetchall()]
        return {
            "total_annotated_samples": len(rows),
            "samples": rows
        }
    finally:
        conn.close()
