"""
FastAPI Router: Pass 1 Cheap Screening (temporary/standalone dashboard tool)

Takes a raw camera-trap video clip, runs blank-frame rejection + YOLOv8
animal/person/vehicle screening + best-frame quality selection, and returns
a frame-by-frame breakdown plus the single best representative frame.

This is a standalone screening utility - it is intentionally NOT wired into
the /api/identify Re-ID flow.
"""

import os
import sys
import tempfile

from fastapi import APIRouter, File, UploadFile, HTTPException, Query

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.ml.screening import screen_video

router = APIRouter(prefix="/api/screening", tags=["Pass1Screening"])


@router.post("/process-video")
async def process_video(
    file: UploadFile = File(...),
    sample_fps: float = Query(3.0, ge=0.5, le=15.0),
):
    if not file.content_type or not file.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be a video.")

    suffix = os.path.splitext(file.filename or "")[1] or ".mp4"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        result = screen_video(tmp_path, sample_fps=sample_fps)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Screening failed: {e}")
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass

    return result
