"""
augment_sightings.py

Lightweight data augmentation for pench_unified.db: tops up each of the 44
PTR_TIG_* tigers' sighting history toward ~50 rows for the Sighting Window
timeline UI, WITHOUT re-running the full agent-based simulation.

Each tiger's *existing* distinct (camera_id, latitude, longitude, zone)
combinations become its fixed "home stations" - no new station or
coordinate is invented, so there's no risk of a synthesized position
landing somewhere implausible (e.g. in open water). New rows just repeat
visits to those same real stations, spread across a wider timestamp range,
with realistic per-visit jitter on the fields that should vary (time,
speed, flank side, image quality).
"""

import os
import random
import sqlite3
import datetime

RANDOM_SEED = 42
random.seed(RANDOM_SEED)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(BASE_DIR, "data", "pench_unified.db")

TARGET_MIN = 45
TARGET_MAX = 55

# Spread augmented sightings across this window (existing data starts
# 2025-11-04); stretching a few years back gives the timeline slider
# meaningful "5/10/15/25/All" presets to differentiate between.
WINDOW_START = datetime.datetime(2021, 6, 1)
WINDOW_END = datetime.datetime(2026, 8, 17)  # matches latest existing timestamp

THREAT_REASONS = {
    "CORE": "Normal core forest patrol",
    "BUFFER": "Buffer corridor crossing",
}


def random_timestamp():
    delta = WINDOW_END - WINDOW_START
    total_seconds = int(delta.total_seconds())
    offset = random.randint(0, total_seconds)
    dt = WINDOW_START + datetime.timedelta(seconds=offset)

    # crepuscular/nocturnal bias, matching the existing rows' spread
    r = random.random()
    if r < 0.55:
        hour = random.choice([*range(5, 9), *range(17, 21)])
    elif r < 0.80:
        hour = random.choice([*range(21, 24), *range(0, 5)])
    else:
        hour = random.randint(9, 17)
    dt = dt.replace(hour=hour, minute=random.randint(0, 59), second=random.randint(0, 59))
    return dt


def main():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT tiger_id FROM tiger_profiles ORDER BY tiger_id ASC")
    tiger_ids = [r["tiger_id"] for r in cur.fetchall()]
    print(f"Loaded {len(tiger_ids)} tiger profiles.")

    total_added = 0
    counts_before = {}
    counts_after = {}

    for tid in tiger_ids:
        cur.execute("SELECT * FROM sightings WHERE tiger_id = ? ORDER BY timestamp ASC", (tid,))
        existing = [dict(r) for r in cur.fetchall()]
        counts_before[tid] = len(existing)

        if not existing:
            # No anchor rows to reuse for this tiger - skip rather than
            # invent a station/position from scratch.
            counts_after[tid] = 0
            continue

        target = random.randint(TARGET_MIN, TARGET_MAX)
        need = target - len(existing)
        if need <= 0:
            counts_after[tid] = len(existing)
            continue

        # Home stations = every distinct real station this tiger has
        # actually been recorded at.
        home_stations = []
        seen = set()
        for row in existing:
            key = row["camera_id"]
            if key not in seen:
                seen.add(key)
                home_stations.append(row)

        # Existing max event index for this tiger, to avoid event_id collisions
        max_idx = -1
        for row in existing:
            try:
                idx = int(row["event_id"].rsplit("_", 1)[-1])
                max_idx = max(max_idx, idx)
            except (ValueError, AttributeError):
                pass

        new_rows = []
        for i in range(need):
            anchor = random.choice(home_stations)
            dt = random_timestamp()
            zone = anchor["zone"] or "CORE"

            max_idx += 1
            eid = f"EVT_{tid}_{max_idx:03d}"

            new_rows.append((
                eid,
                tid,
                dt.isoformat(),
                anchor["camera_id"],
                anchor["latitude"],
                anchor["longitude"],
                anchor["grid_id"],
                zone,
                anchor["habitat_type"],
                random.choice(["Left", "Right"]),
                round(random.uniform(1.0, 6.5), 2),
                anchor["distance_to_nearest_village_km"],
                anchor["distance_to_nearest_water_km"],
                anchor["prey_density"],
                str(round(random.uniform(0.75, 0.98), 2)),
                anchor["reid_confidence"],
                anchor["anomaly_class"],
                "CRITICAL" if zone == "VILLAGE_EDGE" else ("CAUTION" if zone == "BUFFER" else "SAFE"),
                THREAT_REASONS.get(zone, anchor["threat_reason"]),
            ))

        cur.executemany("""
            INSERT OR REPLACE INTO sightings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, new_rows)

        total_added += len(new_rows)
        counts_after[tid] = len(existing) + len(new_rows)

    # Refresh total_captures on tiger_profiles to match the new sighting counts
    cur.execute("SELECT tiger_id, COUNT(*) as c FROM sightings WHERE tiger_id LIKE 'PTR_TIG_%' GROUP BY tiger_id")
    for row in cur.fetchall():
        cur.execute("UPDATE tiger_profiles SET total_captures = ? WHERE tiger_id = ?", (row["c"], row["tiger_id"]))

    conn.commit()

    print(f"\nAdded {total_added} new sighting rows across {len(tiger_ids)} tigers.")
    before_vals = list(counts_before.values())
    after_vals = list(counts_after.values())
    print(f"Sightings/tiger before: min={min(before_vals)}, median={sorted(before_vals)[len(before_vals)//2]}, max={max(before_vals)}")
    print(f"Sightings/tiger after:  min={min(after_vals)}, median={sorted(after_vals)[len(after_vals)//2]}, max={max(after_vals)}")

    cur.execute("SELECT COUNT(*) as c FROM sightings")
    print(f"\nTotal sightings in DB now: {cur.fetchone()['c']}")

    conn.close()


if __name__ == "__main__":
    main()
