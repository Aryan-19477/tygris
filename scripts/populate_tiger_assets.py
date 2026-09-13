"""
Populates High-Res Tiger Camera-Trap Imagery & Enriches 44 Tiger Dossiers with Realistic Sighting Histories.
"""

import os
import sys
import shutil
import sqlite3
import random
import json
import numpy as np

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCE_IMAGES_DIR = os.path.join(PROJECT_ROOT, "detection", "data", "images", "train")
PUBLIC_TIGERS_DIR = os.path.join(PROJECT_ROOT, "frontend", "public", "tigers")
DB_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
BUNDLE_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gis", "pench_web_bundle.json")
FRONTEND_BUNDLE_PATH = os.path.join(PROJECT_ROOT, "frontend", "public", "pench_web_bundle.json")

os.makedirs(PUBLIC_TIGERS_DIR, exist_ok=True)


def main():
    print("[1/4] Copying Real Tiger Camera-Trap Assets...")
    available_imgs = [f for f in os.listdir(SOURCE_IMAGES_DIR) if f.endswith(".jpg")]
    random.seed(42)
    selected_imgs = random.sample(available_imgs, min(60, len(available_imgs)))

    # Map each tiger 1..44 to a distinct image
    tiger_img_map = {}
    for idx in range(1, 45):
        tid = f"PTR_TIG_{idx:03d}"
        src_file = os.path.join(SOURCE_IMAGES_DIR, selected_imgs[(idx - 1) % len(selected_imgs)])
        dst_file = os.path.join(PUBLIC_TIGERS_DIR, f"{tid}.jpg")
        shutil.copyfile(src_file, dst_file)
        tiger_img_map[tid] = f"/tigers/{tid}.jpg"

    print(f"Copied {len(tiger_img_map)} tiger photos to {PUBLIC_TIGERS_DIR}")

    print("[2/4] Connecting to Unified SQLite Database...")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Fetch 311 camera stations for spatial assignment
    # Ensure thumbnail column exists
    try:
        cur.execute("ALTER TABLE tiger_profiles ADD COLUMN thumbnail TEXT")
    except sqlite3.OperationalError:
        pass

    cur.execute("SELECT camera_id, latitude, longitude, zone, sub_region FROM camera_stations")
    cams = cur.fetchall()



    # Clear old sightings to rebuild rich baseline
    cur.execute("DELETE FROM sightings")

    # Range of dates: 60 days
    base_timestamps = [
        "2025-11-04T06:14:00", "2025-11-09T18:42:00", "2025-11-15T07:22:00",
        "2025-11-21T19:05:00", "2025-11-28T05:50:00", "2025-12-04T20:18:00",
        "2025-12-11T06:33:00", "2025-12-18T18:15:00", "2025-12-25T07:02:00",
        "2026-01-02T19:40:00", "2026-01-10T06:11:00", "2026-01-18T18:50:00",
        "2026-01-26T07:30:00", "2026-02-04T19:15:00", "2026-02-12T06:45:00"
    ]

    total_sightings_added = 0

    print("[3/4] Generating Rich Sighting Timeline & Updating Profiles...")
    for idx in range(1, 45):
        tid = f"PTR_TIG_{idx:03d}"
        img_url = tiger_img_map[tid]

        # Determine tiger home zone and pick 3-6 nearby stations
        zone = "CORE" if idx <= 28 else "BUFFER"
        zone_cams = [c for c in cams if c[3] == zone]
        if not zone_cams:
            zone_cams = cams

        # Cluster cameras around a primary range
        start_cam = random.choice(zone_cams)
        sub_cams = [c for c in zone_cams if c[4] == start_cam[4]]
        if len(sub_cams) < 3:
            sub_cams = random.sample(zone_cams, min(5, len(zone_cams)))
        else:
            sub_cams = random.sample(sub_cams, min(6, len(sub_cams)))

        num_sightings = random.randint(6, 12)
        mcp_area = round(random.uniform(28.0, 58.0), 1)

        # Update profile
        cur.execute("""
            UPDATE tiger_profiles 
            SET thumbnail = ?, mcp_area_km2 = ?, total_captures = ?
            WHERE tiger_id = ?
        """, (img_url, mcp_area, num_sightings, tid))

        # Add historical sightings
        for s_idx in range(num_sightings):
            cam = random.choice(sub_cams)
            ts = base_timestamps[s_idx % len(base_timestamps)]
            flank = "Left" if (s_idx + idx) % 2 == 0 else "Right"
            speed = round(random.uniform(1.2, 5.8), 1)

            # Conflict alert logic
            if cam[3] == "BUFFER" and random.random() < 0.35:
                alert = "CRITICAL" if random.random() < 0.30 else "CAUTION"
                reason = "Village fringe proximity (< 0.8km)" if alert == "CRITICAL" else "Buffer corridor crossing"
            else:
                alert = "SAFE"
                reason = "Normal core forest patrol"

            event_id = f"EVT_{tid}_{s_idx:03d}"
            cur.execute("""
                INSERT INTO sightings 
                (event_id, tiger_id, camera_id, timestamp, latitude, longitude, zone, flank_side, speed_kmh, image_quality, alert_level, threat_reason)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (event_id, tid, cam[0], ts, cam[1], cam[2], cam[3], flank, speed, 0.92, alert, reason))
            total_sightings_added += 1

    conn.commit()
    conn.close()
    print(f"Added {total_sightings_added} rich sightings across 44 tigers.")

    print("[4/4] Updating Web GIS Bundles...")
    # Read bundle, update tiger thumbnails
    if os.path.exists(BUNDLE_PATH):
        with open(BUNDLE_PATH, "r", encoding="utf-8") as f:
            bundle = json.load(f)

        if "territories" in bundle:
            for tid, tdata in bundle["territories"].items():
                if tid in tiger_img_map:
                    tdata["thumbnail"] = tiger_img_map[tid]

        with open(BUNDLE_PATH, "w", encoding="utf-8") as f:
            json.dump(bundle, f, indent=2)

        with open(FRONTEND_BUNDLE_PATH, "w", encoding="utf-8") as f:
            json.dump(bundle, f, indent=2)
        print("Exported updated GIS bundles.")

    print("[SUCCESS] Tiger Assets & Dossiers Populated Successfully!")


if __name__ == "__main__":
    main()
