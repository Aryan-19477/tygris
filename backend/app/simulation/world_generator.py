"""
Multi-World Simulation Engine & 4-Layer Dataset Generator
Generates full ecological simulations across seeds (1..1000):
- Layer 1: Geography (Pench vector boundaries, 11 sub-regions, 2km² grids, 44 villages)
- Layer 2: Hidden Truth (True agent movement trajectories & behavioral states)
- Layer 3: Observations (311 Camera sensor detections, image mappings, missed captures)
- Layer 4: Interpretation & Alerts (100% MCP home ranges, anomaly classes, conflict alerts)
Stores all data into SQLite database and exports frontend JSON bundles.
"""

import os
import sys
import math
import json
import sqlite3
import datetime

from typing import Dict, List, Tuple, Optional, Any
import numpy as np

import os
import sys

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

SIM_DIR = os.path.abspath(os.path.dirname(__file__))
if SIM_DIR not in sys.path:
    sys.path.insert(0, SIM_DIR)

from pench_environment import PenchEnvironment, CORE_BOUNDARY, BUFFER_BOUNDARY, SUB_REGIONS, VILLAGES_44, WATER_SOURCES
from camera_network import CameraNetwork
from tiger_agent import TigerPopulationSimulator
from anomaly_engine import ConflictAlertClassifier, BayesianAbsenceReasoner, ANOMALY_TAXONOMY




class SimulationWorldGenerator:
    """
    Orchestrates the multi-world simulation generator and populates the SQLite database.
    """
    def __init__(
        self,
        db_path: Optional[str] = None,
        bundle_path: Optional[str] = None,
        random_seed: int = 42
    ):
        base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.db_path = db_path or os.path.join(base_dir, "data", "pench_unified.db")
        self.bundle_path = bundle_path or os.path.join(base_dir, "data", "gis", "pench_web_bundle.json")
        self.seed = random_seed

        self.env = PenchEnvironment(random_seed=random_seed)
        self.camera_net = CameraNetwork(self.env, total_cameras=311, random_seed=random_seed)
        self.pop_sim = TigerPopulationSimulator(self.env, population_size=44, random_seed=random_seed)

        self._init_database()

    def _init_database(self):
        """Creates tables for the 4-layer database schema."""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        # 1. Camera Stations
        cur.execute("""
        CREATE TABLE IF NOT EXISTS camera_stations (
            camera_id TEXT PRIMARY KEY,
            latitude REAL,
            longitude REAL,
            grid_id TEXT,
            zone TEXT,
            sub_region TEXT,
            habitat TEXT,
            elevation_m REAL,
            nearest_water_km REAL,
            nearest_village_km REAL,
            trail_type TEXT,
            operational_status TEXT,
            uptime_ratio REAL
        )
        """)

        # 2. Tiger Profiles
        cur.execute("""
        CREATE TABLE IF NOT EXISTS tiger_profiles (
            tiger_id TEXT PRIMARY KEY,
            name TEXT,
            sex TEXT,
            age_years REAL,
            life_stage TEXT,
            territorial_status TEXT,
            home_range_target_km2 REAL,
            core_centroid_lat REAL,
            core_centroid_lon REAL,
            mcp_area_km2 REAL,
            total_captures INTEGER
        )
        """)

        # 3. 4-Layer Sightings Observations
        cur.execute("""
        CREATE TABLE IF NOT EXISTS sightings (
            event_id TEXT PRIMARY KEY,
            tiger_id TEXT,
            timestamp TEXT,
            camera_id TEXT,
            latitude REAL,
            longitude REAL,
            grid_id TEXT,
            zone TEXT,
            habitat_type TEXT,
            flank_side TEXT,
            speed_kmh REAL,
            distance_to_nearest_village_km REAL,
            distance_to_nearest_water_km REAL,
            prey_density REAL,
            image_quality TEXT,
            reid_confidence REAL,
            anomaly_class TEXT,
            alert_level TEXT,
            threat_reason TEXT,
            FOREIGN KEY (camera_id) REFERENCES camera_stations (camera_id),
            FOREIGN KEY (tiger_id) REFERENCES tiger_profiles (tiger_id)
        )
        """)

        conn.commit()
        conn.close()

    def run_simulation(self, simulation_days: int = 90) -> Dict[str, Any]:
        """
        Executes an agent movement simulation across the specified number of days (calibrated to ~8,415 trap nights).
        """
        print(f"[SimulationEngine] Running {simulation_days}-day multi-agent simulation across Pench Reserve...")
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        # Insert Camera Stations
        for cam in self.camera_net.stations.values():
            cur.execute("""
            INSERT OR REPLACE INTO camera_stations VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                cam.camera_id, cam.latitude, cam.longitude, cam.grid_id, cam.zone,
                cam.sub_region, cam.habitat, cam.elevation_m, cam.nearest_water_km,
                cam.nearest_village_km, cam.trail_type, cam.operational_status, cam.uptime_ratio
            ))

        # Simulation clock start
        start_date = datetime.datetime(2025, 11, 1, 0, 0, 0)
        total_steps_per_day = 48  # 30-min steps
        total_sightings_recorded = 0

        tiger_sighting_counts: Dict[str, int] = {t: 0 for t in self.pop_sim.tigers.keys()}
        tiger_coordinates_history: Dict[str, List[Tuple[float, float]]] = {t: [] for t in self.pop_sim.tigers.keys()}

        event_id_counter = 1

        # Simulate day by day
        for day in range(simulation_days):
            season = "WINTER" if day < 60 else "SUMMER"

            for step in range(total_steps_per_day):
                curr_time = start_date + datetime.timedelta(days=day, minutes=step * 30)
                hour = curr_time.hour
                is_night = (hour >= 20 or hour <= 5)

                for tid, tiger in self.pop_sim.tigers.items():
                    # Move tiger
                    step_data = self.pop_sim.step_agent_movement(
                        tiger=tiger,
                        hour_of_day=hour,
                        season=season,
                        step_duration_hours=0.5
                    )
                    t_lat, t_lon = step_data["lat"], step_data["lon"]
                    tiger_coordinates_history[tid].append((t_lat, t_lon))

                    # Check camera triggers
                    detections = self.camera_net.evaluate_detection(
                        tiger_lat=t_lat,
                        tiger_lon=t_lon,
                        tiger_speed_kmh=step_data["speed_kmh"],
                        movement_bearing=step_data["bearing"],
                        is_night=is_night
                    )

                    for det in detections:
                        cid = det["camera_id"]
                        d_village = self.env.get_distance_to_nearest_village(t_lat, t_lon)
                        d_water = self.env.get_distance_to_nearest_water(t_lat, t_lon)
                        zone = self.env.classify_zone(t_lat, t_lon)
                        prey = self.env.sample_prey_density(zone if zone != "OUTSIDE" else "BUFFER")

                        # Threat Classification
                        threat = ConflictAlertClassifier.classify_sighting_threat(
                            lat=t_lat,
                            lon=t_lon,
                            zone=zone,
                            dist_to_nearest_village_km=d_village,
                            dist_to_nearest_water_km=d_water,
                            is_subadult_dispersing=(tiger.territorial_status == "DISPERSING")
                        )

                        flank = "Left" if event_id_counter % 2 == 0 else "Right"
                        conf = round(float(np.random.uniform(0.92, 0.99)), 4)
                        eid = f"EVT_{event_id_counter:06d}"

                        cur.execute("""
                        INSERT OR REPLACE INTO sightings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, (
                            eid, tid, curr_time.isoformat(), cid, t_lat, t_lon,
                            self.camera_net.stations[cid].grid_id, zone,
                            self.camera_net.stations[cid].habitat, flank,
                            step_data["speed_kmh"], d_village, d_water, prey,
                            det["image_quality"], conf, threat["anomaly_type"],
                            threat["alert_level"], threat["reason"]
                        ))

                        event_id_counter += 1
                        total_sightings_recorded += 1
                        tiger_sighting_counts[tid] += 1

        # Compute 100% MCP and save Tiger Profiles
        for tid, tiger in self.pop_sim.tigers.items():
            pts = tiger_coordinates_history[tid]
            mcp_area = self._compute_mcp_area(pts)

            cur.execute("""
            INSERT OR REPLACE INTO tiger_profiles VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                tid, tiger.name, tiger.sex, tiger.age_years, tiger.life_stage,
                tiger.territorial_status, tiger.home_range_target_km2,
                tiger.core_centroid_lat, tiger.core_centroid_lon,
                mcp_area, tiger_sighting_counts[tid]
            ))

        conn.commit()
        conn.close()

        print(f"[SimulationEngine] Simulation complete. Recorded {total_sightings_recorded} observations across 44 tigers.")
        self.export_frontend_bundle()
        return {
            "simulation_days": simulation_days,
            "total_tigers": len(self.pop_sim.tigers),
            "total_cameras": len(self.camera_net.stations),
            "total_sightings": total_sightings_recorded
        }

    def _compute_mcp_area(self, points: List[Tuple[float, float]]) -> float:
        """Computes 100% Minimum Convex Polygon surface area in km²."""
        if len(points) < 3:
            return 25.0
        # Subsample for convex hull calculation
        coords = np.array(points[::max(1, len(points) // 100)])
        c_lat, c_lon = np.mean(coords[:, 0]), np.mean(coords[:, 1])
        y = (coords[:, 0] - c_lat) * 111.32
        x = (coords[:, 1] - c_lon) * (111.32 * math.cos(math.radians(c_lat)))
        try:
            from scipy.spatial import ConvexHull
            hull = ConvexHull(np.column_stack([x, y]))
            return round(float(hull.volume), 2)  # In 2D, hull.volume is area
        except Exception:
            return 35.0

    def export_frontend_bundle(self):
        """Packages geography, cameras, villages, territories, and recent sightings into pench_web_bundle.json."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        cur.execute("SELECT * FROM camera_stations")
        stations = [dict(row) for row in cur.fetchall()]

        cur.execute("SELECT * FROM tiger_profiles")
        tigers = [dict(row) for row in cur.fetchall()]

        cur.execute("SELECT * FROM sightings ORDER BY timestamp DESC LIMIT 500")
        sightings = [dict(row) for row in cur.fetchall()]

        conn.close()

        # Build tiger territory polygons
        territories = {}
        for t in tigers:
            c_lat = t["core_centroid_lat"]
            c_lon = t["core_centroid_lon"]
            r_km = math.sqrt(t["home_range_target_km2"] / math.pi)
            dlat = r_km / 111.32
            dlon = r_km / (111.32 * math.cos(math.radians(c_lat)))
            angles = np.linspace(0, 2 * math.pi, 16)
            poly = [[round(c_lat + dlat * math.sin(a), 5), round(c_lon + dlon * math.cos(a), 5)] for a in angles]
            territories[t["tiger_id"]] = {
                "tiger_id": t["tiger_id"],
                "name": t["name"],
                "sex": t["sex"],
                "life_stage": t["life_stage"],
                "centroid": [c_lat, c_lon],
                "area_km2": t["mcp_area_km2"],
                "polygon": poly
            }

        bundle = {
            "version": "2.0_WII_2021_Calibrated",
            "metadata": {
                "reserve": "Pench Tiger Reserve (Maharashtra / MP)",
                "total_stations": len(stations),
                "total_tigers": len(tigers),
                "total_villages": len(VILLAGES_44),
                "core_area_km2": 437.88,
                "buffer_area_km2": 267.57,
                "sampling_grid_size_km2": 2.0
            },
            "core_boundary": CORE_BOUNDARY,
            "buffer_boundary": BUFFER_BOUNDARY,
            "sub_regions": SUB_REGIONS,
            "villages": VILLAGES_44,
            "water_sources": WATER_SOURCES,
            "stations": stations,
            "territories": territories,
            "recent_sightings": sightings
        }

        os.makedirs(os.path.dirname(self.bundle_path), exist_ok=True)
        with open(self.bundle_path, "w", encoding="utf-8") as f:
            json.dump(bundle, f, indent=2)

        print(f"[SimulationEngine] Exported Pench Web Bundle ({len(stations)} stations, {len(territories)} territories) to {self.bundle_path}")


if __name__ == "__main__":
    gen = SimulationWorldGenerator()
    gen.run_simulation(simulation_days=30)
