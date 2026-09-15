"""
TYGRIS: Unified Backend Server
Combines Paper-Faithful 5-Stage Visual Re-ID (Ma et al. 2025) and WII-2021 Ecological GIS Engine.
"""

import os
import sys
import asyncio
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

# Load backend/.env (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ...) if present.
# python-dotenv may not be installed yet — degrade gracefully, don't crash startup.
try:
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
except ImportError:
    pass

logger = logging.getLogger("tygris.main")

from backend.app.api.routes_identify import router as identify_router
from backend.app.api.routes_gallery import router as gallery_router
from backend.app.api.routes_gis import router as gis_router
from backend.app.api.routes_alerts import router as alerts_router
from backend.app.api.routes_captures import router as captures_router
from backend.app.api.routes_review import router as review_router
from backend.app.api.routes_embedding import router as embedding_router
from backend.app.api.routes_screening import router as screening_router

# Ranger-ops routes depend on the `supabase` package, which may not be
# installed yet in this environment. Import defensively so a missing
# dependency only disables /api/ranger/* — it must never crash the rest
# of the backend.
try:
    from backend.app.api.routes_ranger_ops import router as ranger_ops_router
    from backend.app.api.routes_ranger_ops import run_pending_territory_checks
    _RANGER_OPS_AVAILABLE = True
except ImportError as exc:
    logger.warning(f"[ranger-ops] Routes disabled (missing dependency): {exc}")
    ranger_ops_router = None
    run_pending_territory_checks = None
    _RANGER_OPS_AVAILABLE = False

RANGER_OPS_POLL_SECONDS = 60


async def _ranger_ops_poll_loop():
    from backend.app.services.supabase_client import get_supabase_client

    if get_supabase_client() is None:
        logger.info("[ranger-ops] Supabase not configured — background polling loop will not run.")
        return

    logger.info(f"[ranger-ops] Starting background territory-check poll loop ({RANGER_OPS_POLL_SECONDS}s interval).")
    while True:
        await asyncio.sleep(RANGER_OPS_POLL_SECONDS)
        try:
            result = run_pending_territory_checks()
            if result.get("processed"):
                logger.info(f"[ranger-ops] Poll loop processed {result['processed']} new territory check(s).")
        except Exception as exc:
            logger.warning(f"[ranger-ops] Poll loop iteration failed (will retry): {exc}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = None
    if _RANGER_OPS_AVAILABLE:
        task = asyncio.create_task(_ranger_ops_poll_loop())
    yield
    if task is not None:
        task.cancel()


app = FastAPI(
    title="TYGRIS AI Wildlife Monitoring Platform",
    description="Unified 5-stage Computer Vision Tiger Re-ID and WII-Calibrated Pench Ecological GIS Engine.",
    version="2.0.0",
    lifespan=lifespan,
)

# Enable CORS for Next.js frontend (port 3000) and any local origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serves real captured-sighting photos saved by _record_sighting() (see
# routes_identify.py) — the Capture Log reads image_path values like
# "/captures/EVT_LIVE_xxx.jpg" from the sightings table and fetches them
# from here.
_CAPTURES_DIR = os.path.join(PROJECT_ROOT, "backend", "data", "captures")
os.makedirs(_CAPTURES_DIR, exist_ok=True)
app.mount("/captures", StaticFiles(directory=_CAPTURES_DIR), name="captures")

# One-time, idempotent migration: older copies of pench_unified.db (this
# file is committed to the repo as seed data) predate the Capture Log and
# don't have this column yet. Adding it here — rather than requiring a
# specific committed DB binary — means the column always exists on
# startup regardless of which snapshot of the DB is on disk.
_db_path = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
if os.path.exists(_db_path):
    import sqlite3 as _sqlite3
    _conn = _sqlite3.connect(_db_path)
    _cols = [r[1] for r in _conn.execute("PRAGMA table_info(sightings)").fetchall()]
    if "image_path" not in _cols:
        _conn.execute("ALTER TABLE sightings ADD COLUMN image_path TEXT")
        _conn.commit()
    _conn.close()

# Register API Routers
app.include_router(identify_router)
app.include_router(gallery_router)
app.include_router(gis_router)
app.include_router(alerts_router)
app.include_router(captures_router)
app.include_router(review_router)
app.include_router(embedding_router)
app.include_router(screening_router)
if _RANGER_OPS_AVAILABLE:
    app.include_router(ranger_ops_router)


@app.get("/")
def root():
    return {
        "system": "TYGRIS Wildlife Intelligence Platform",
        "version": "2.0.0",
        "status": "ONLINE",
        "endpoints": [
            "/api/identify",
            "/api/identify-burst",
            "/api/gallery",
            "/api/gis/bundle",
            "/api/stations",
            "/api/alerts",
            "/api/captures",
            "/api/stats",
            "/api/review-queue",
            "/api/embedding-space",
            "/api/screening/process-video",
            "/api/ranger/reports",
            "/api/ranger/territory-check/{observation_id}",
            "/api/ranger/territory-check/run-pending",
        ],
        "ranger_ops_enabled": _RANGER_OPS_AVAILABLE,
    }


if __name__ == "__main__":
    import uvicorn
    print("[TYGRIS] Starting Unified Backend Server on http://0.0.0.0:8420")
    uvicorn.run(app, host="0.0.0.0", port=8420)
