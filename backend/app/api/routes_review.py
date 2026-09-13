"""
FastAPI Router: Human-in-the-Loop Review Queue & Open-World Candidate Enrollment
"""

import os
import sys
import uuid
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

router = APIRouter(prefix="/api", tags=["Review Queue"])

# In-memory review queue store
REVIEW_QUEUE: Dict[str, Dict[str, Any]] = {
    "REV_001": {
        "item_id": "REV_001",
        "timestamp": "2026-02-14T06:45:00",
        "station_id": "PTR_CAM_194",
        "zone": "BUFFER",
        "uploaded_image": "/tigers/PTR_TIG_014.jpg",
        "nearest_distance": 0.48,
        "candidates": [
            {"tiger_id": "PTR_TIG_014", "similarity": 0.58, "flank": "Right", "thumbnail": "/tigers/PTR_TIG_014.jpg"},
            {"tiger_id": "PTR_TIG_022", "similarity": 0.49, "flank": "Right", "thumbnail": "/tigers/PTR_TIG_022.jpg"}
        ],
        "reason": "Open-World Gating: Nearest neighbor distance (0.48) exceeds auto-match threshold (0.40)."
    },
    "REV_002": {
        "item_id": "REV_002",
        "timestamp": "2026-02-16T19:20:00",
        "station_id": "PTR_CAM_082",
        "zone": "CORE",
        "uploaded_image": "/tigers/PTR_TIG_007.jpg",
        "nearest_distance": 0.44,
        "candidates": [
            {"tiger_id": "PTR_TIG_007", "similarity": 0.62, "flank": "Left", "thumbnail": "/tigers/PTR_TIG_007.jpg"},
            {"tiger_id": "PTR_TIG_039", "similarity": 0.45, "flank": "Left", "thumbnail": "/tigers/PTR_TIG_039.jpg"}
        ],
        "reason": "Ambiguous Flank: Stripe distortion due to partial motion blur."
    }
}



class ReviewResolutionRequest(BaseModel):
    assigned_tiger_id: Optional[str] = None  # If None -> create new identity
    flank_side: Optional[str] = "Left"
    notes: Optional[str] = ""


@router.get("/review-queue")
def get_review_queue():
    """
    Returns list of open-world ambiguous sightings requiring expert biologist confirmation.
    """
    return {"items": list(REVIEW_QUEUE.values())}


@router.post("/review-queue/{item_id}/resolve")
def resolve_review_item(item_id: str, payload: ReviewResolutionRequest):
    """
    Resolves a review item: either associates it with an existing tiger ID or enrolls a new individual into the gallery.
    """
    entry = REVIEW_QUEUE.pop(item_id, None)
    if not entry:
        raise HTTPException(status_code=404, detail="Review item not found.")

    assigned_id = payload.assigned_tiger_id
    is_new = False
    if not assigned_id:
        is_new = True
        assigned_id = f"PTR_TIG_NEW_{uuid.uuid4().hex[:4].upper()}"

    return {
        "status": "RESOLVED",
        "item_id": item_id,
        "assigned_tiger_id": assigned_id,
        "is_new_individual": is_new,
        "message": f"Successfully {'enrolled new individual ' if is_new else 'confirmed sighting for '}{assigned_id}."
    }
