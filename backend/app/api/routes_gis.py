"""
FastAPI Router: GIS Map Layers, 311 Stations, Boundaries, and Territories
"""

import os
import sys
import json
import sqlite3
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, HTTPException

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

router = APIRouter(prefix="/api", tags=["GIS"])

DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
BUNDLE_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gis", "pench_web_bundle.json")


@router.get("/gis/bundle")
def get_map_bundle():
    """
    Returns complete vector map bundle: Core/Buffer boundaries, 11 sub-regions, 44 villages, 311 camera stations, territories, and recent sightings.
    """
    if os.path.exists(BUNDLE_PATH):
        with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)

    raise HTTPException(status_code=503, detail="GIS Web Bundle is still generating. Please retry in a moment.")


@router.get("/stations")
def list_stations():
    """
    Lists all 311 camera stations with operational status, zone, and habitat attributes.
    """
    if not os.path.exists(DB_PATH):
        if os.path.exists(BUNDLE_PATH):
            with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
                bundle = json.load(f)
            return {"stations": bundle.get("stations", [])}
        return {"stations": []}

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT * FROM camera_stations ORDER BY camera_id ASC")
    rows = [dict(r) for r in cur.fetchall()]
    conn.close()
    return {"stations": rows}
