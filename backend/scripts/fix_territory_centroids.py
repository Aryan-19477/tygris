"""
fix_territory_centroids.py

Fixes a data-consistency bug that predates this session's work: each
tiger's core_centroid_lat/lon in tiger_profiles was set independently at
population-generation time (world_generator.py's random territory
placement) and was never actually reconciled with where that tiger's real
sightings occurred. 34/44 tigers ended up with a stored centroid 9-17km
away from every camera station they were ever detected at, which produces
a visibly wrong "territory" polygon in the Reserve Map view (offset from
the tiger's own last-seen pins) and directional attraction toward
whichever water source happens to sit near the wrong centroid.

Sightings are camera-trap detections at real, fixed station coordinates,
so they are ground truth. This script recomputes each tiger's centroid as
the mean of its own sighting coordinates, and its MCP (Minimum Convex
Polygon) area via the same convex-hull method world_generator.py already
uses for its own MCP computation, so territory polygons and last-seen pins
are consistent with each other on the map.
"""

import os
import math
import sqlite3

import numpy as np
from scipy.spatial import ConvexHull

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(BASE_DIR, "data", "pench_unified.db")


def compute_mcp_area(points):
    """Same method as SimulationWorldGenerator._compute_mcp_area."""
    if len(points) < 3:
        return 25.0
    coords = np.array(points)
    c_lat, c_lon = np.mean(coords[:, 0]), np.mean(coords[:, 1])
    y = (coords[:, 0] - c_lat) * 111.32
    x = (coords[:, 1] - c_lon) * (111.32 * math.cos(math.radians(c_lat)))
    try:
        hull = ConvexHull(np.column_stack([x, y]))
        return round(float(hull.volume), 2)
    except Exception:
        return 25.0


def main():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT tiger_id, core_centroid_lat, core_centroid_lon, mcp_area_km2 FROM tiger_profiles")
    profiles = {r["tiger_id"]: dict(r) for r in cur.fetchall()}

    fixed = 0
    skipped_no_sightings = []

    for tid, profile in profiles.items():
        cur.execute("SELECT latitude, longitude FROM sightings WHERE tiger_id = ?", (tid,))
        rows = cur.fetchall()
        points = [(r["latitude"], r["longitude"]) for r in rows if r["latitude"] is not None and r["longitude"] is not None]

        if not points:
            skipped_no_sightings.append(tid)
            continue

        new_lat = float(np.mean([p[0] for p in points]))
        new_lon = float(np.mean([p[1] for p in points]))
        new_area = compute_mcp_area(points)

        old_lat, old_lon = profile["core_centroid_lat"], profile["core_centroid_lon"]

        def dist_km(lat1, lon1, lat2, lon2):
            dlat = (lat2 - lat1) * 111.0
            dlon = (lon2 - lon1) * 103.0
            return math.sqrt(dlat ** 2 + dlon ** 2)

        moved_km = dist_km(old_lat, old_lon, new_lat, new_lon)

        cur.execute(
            "UPDATE tiger_profiles SET core_centroid_lat = ?, core_centroid_lon = ?, mcp_area_km2 = ? WHERE tiger_id = ?",
            (round(new_lat, 6), round(new_lon, 6), new_area, tid),
        )
        fixed += 1
        if moved_km > 5:
            print(f"  {tid}: centroid moved {moved_km:.1f} km -> now at real sighting cluster, MCP={new_area} km2")

    conn.commit()
    conn.close()

    print(f"\nRecomputed centroid + MCP area for {fixed} tigers.")
    if skipped_no_sightings:
        print(f"Skipped (no sightings on file): {skipped_no_sightings}")


if __name__ == "__main__":
    main()
