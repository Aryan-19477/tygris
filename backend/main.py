"""
TYGRIS: Unified Backend Server
Combines Paper-Faithful 5-Stage Visual Re-ID (Ma et al. 2025) and WII-2021 Ecological GIS Engine.
"""

import os
import sys
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.api.routes_identify import router as identify_router
from backend.app.api.routes_gallery import router as gallery_router
from backend.app.api.routes_gis import router as gis_router
from backend.app.api.routes_alerts import router as alerts_router
from backend.app.api.routes_review import router as review_router
from backend.app.api.routes_embedding import router as embedding_router

app = FastAPI(
    title="TYGRIS AI Wildlife Monitoring Platform",
    description="Unified 5-stage Computer Vision Tiger Re-ID and WII-Calibrated Pench Ecological GIS Engine.",
    version="2.0.0"
)

# Enable CORS for Next.js frontend (port 3000) and any local origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register API Routers
app.include_router(identify_router)
app.include_router(gallery_router)
app.include_router(gis_router)
app.include_router(alerts_router)
app.include_router(review_router)
app.include_router(embedding_router)


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
            "/api/stats",
            "/api/review-queue",
            "/api/embedding-space"
        ]
    }


if __name__ == "__main__":
    import uvicorn
    print("[TYGRIS] Starting Unified Backend Server on http://0.0.0.0:8420")
    uvicorn.run(app, host="0.0.0.0", port=8420)
