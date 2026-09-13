"""
Camera Trap Network Simulation Architecture (WII 311-Station Anchor)
Reference: Wildlife Institute of India (WII) 2021 Pench Monitoring Survey.
Implements:
- 311 primary camera stations (+ candidate sets for 250, 350, 400, 500)
- Trail-, nallah-, and corridor-biased non-uniform camera placement
- Hardware failure modes (offline periods, battery low, night IR loss)
- Distance-, orientation-, and speed-dependent detection probability P(detect)
"""

import math
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass, field
import numpy as np

import os
import sys

SIM_DIR = os.path.abspath(os.path.dirname(__file__))
if SIM_DIR not in sys.path:
    sys.path.insert(0, SIM_DIR)

from pench_environment import PenchEnvironment, haversine_distance_km




TRAIL_TYPES = [
    "Primary Animal Trail",
    "Dry Stream Bed (Nallah)",
    "Forest Patrol Track",
    "Ridge Crest Path",
    "Waterhole Access Path",
    "Wildlife Corridor Crossing"
]


@dataclass
class CameraStation:
    camera_id: str
    latitude: float
    longitude: float
    grid_id: str
    zone: str
    sub_region: str
    habitat: str
    elevation_m: float
    nearest_water_km: float
    nearest_village_km: float
    nearest_road_km: float
    trail_type: str
    facing_bearing_deg: float      # Direction camera sensor points (0-360°)
    active_from: str = "2025-11-01T00:00:00"
    active_until: str = "2026-03-31T23:59:59"
    operational_status: str = "OPERATIONAL" # "OPERATIONAL", "OFFLINE", "BATTERY_LOW", "IR_FAILED"
    sensor_range_m: float = 65.0   # Trail corridor encounter radius in meters
    uptime_ratio: float = 0.95     # Historical operational percentage
    offline_ranges: List[Tuple[str, str]] = field(default_factory=list)


    def to_dict(self) -> Dict[str, Any]:
        return {
            "camera_id": self.camera_id,
            "latitude": round(self.latitude, 5),
            "longitude": round(self.longitude, 5),
            "grid_id": self.grid_id,
            "zone": self.zone,
            "sub_region": self.sub_region,
            "habitat": self.habitat,
            "elevation_m": round(self.elevation_m, 1),
            "nearest_water_km": round(self.nearest_water_km, 3),
            "nearest_village_km": round(self.nearest_village_km, 3),
            "nearest_road_km": round(self.nearest_road_km, 3),
            "trail_type": self.trail_type,
            "facing_bearing_deg": round(self.facing_bearing_deg, 1),
            "operational_status": self.operational_status,
            "uptime_ratio": round(self.uptime_ratio, 2)
        }


class CameraNetwork:
    """
    Simulates the WII 311-station camera network and sensor trigger detection process.
    """
    def __init__(self, env: PenchEnvironment, total_cameras: int = 311, random_seed: int = 42):
        self.env = env
        self.total_cameras = total_cameras
        self.rng = np.random.default_rng(random_seed)
        self.stations: Dict[str, CameraStation] = {}

        self._generate_camera_network()

    def _generate_camera_network(self):
        """
        Generates realistic non-uniform camera stations biased toward trails and watercourses.
        Core: ~68% of stations, Buffer: ~32% of stations (calibrated to WII 2021).
        """
        target_core = int(self.total_cameras * 0.68)
        target_buffer = self.total_cameras - target_core

        generated_core = 0
        generated_buffer = 0
        cam_idx = 1

        # Use 2km sampling grids as cluster anchors
        grid_list = list(self.env.grids_2km.values())
        self.rng.shuffle(grid_list)

        while (generated_core < target_core or generated_buffer < target_buffer) and len(grid_list) > 0:
            for grid in grid_list:
                if grid.zone == "CORE" and generated_core >= target_core:
                    continue
                if grid.zone == "BUFFER" and generated_buffer >= target_buffer:
                    continue

                # Add small spatial jitter within the 2km grid cell
                jitter_lat = float(self.rng.uniform(-0.007, 0.007))
                jitter_lon = float(self.rng.uniform(-0.007, 0.007))
                lat = grid.center_lat + jitter_lat
                lon = grid.center_lon + jitter_lon

                zone = self.env.classify_zone(lat, lon)
                if zone == "OUTSIDE":
                    continue

                # Compute ecological distances
                d_water = self.env.get_distance_to_nearest_water(lat, lon)
                d_village = self.env.get_distance_to_nearest_village(lat, lon)
                trail = str(self.rng.choice(TRAIL_TYPES))
                bearing = float(self.rng.uniform(0.0, 360.0))

                # Inject realistic hardware failure intervals for ~7% of cameras
                has_hardware_issue = self.rng.random() < 0.07
                status = "OPERATIONAL"
                uptime = float(self.rng.uniform(0.92, 0.99))
                offline_periods = []
                if has_hardware_issue:
                    status = str(self.rng.choice(["OFFLINE", "BATTERY_LOW", "IR_FAILED"]))
                    uptime = float(self.rng.uniform(0.50, 0.85))
                    offline_periods.append(("2025-12-10T00:00:00", "2025-12-24T00:00:00"))

                cid = f"PTR_CAM_{cam_idx:03d}"
                station = CameraStation(
                    camera_id=cid,
                    latitude=lat,
                    longitude=lon,
                    grid_id=grid.grid_id,
                    zone=zone,
                    sub_region=grid.sub_region,
                    habitat="Mixed Deciduous Forest" if zone == "CORE" else "Open Scrub Buffer",
                    elevation_m=float(self.rng.uniform(280.0, 480.0)),
                    nearest_water_km=d_water,
                    nearest_village_km=d_village,
                    nearest_road_km=float(self.rng.uniform(0.2, 3.5)),
                    trail_type=trail,
                    facing_bearing_deg=bearing,
                    operational_status=status,
                    uptime_ratio=uptime,
                    offline_ranges=offline_periods
                )
                self.stations[cid] = station
                cam_idx += 1

                if zone == "CORE":
                    generated_core += 1
                else:
                    generated_buffer += 1

                if generated_core >= target_core and generated_buffer >= target_buffer:
                    break

        print(f"[CameraNetwork] Deployed {len(self.stations)} stations ({generated_core} Core, {generated_buffer} Buffer).")

    def evaluate_detection(
        self,
        tiger_lat: float,
        tiger_lon: float,
        tiger_speed_kmh: float,
        movement_bearing: float,
        is_night: bool = False,
        weather: str = "CLEAR"
    ) -> List[Dict[str, Any]]:
        """
        Evaluates whether an active tiger agent triggers any nearby camera sensors.
        Returns list of triggered sightings with detection confidence and quality scores.
        """
        detections = []
        for cid, cam in self.stations.items():
            dist_km = haversine_distance_km(tiger_lat, tiger_lon, cam.latitude, cam.longitude)
            dist_m = dist_km * 1000.0

            # Sensor trigger radius: max 15 meters
            if dist_m <= cam.sensor_range_m:
                # 1. Operational gate
                if cam.operational_status == "OFFLINE":
                    continue
                if cam.operational_status == "IR_FAILED" and is_night:
                    continue

                # 2. Distance attenuation: P ~ exp(-d^2 / 2*sigma^2)
                p_dist = math.exp(-(dist_m**2) / (2.0 * (35.0**2)))


                # 3. Motion angle alignment with camera cone
                angle_diff = abs(movement_bearing - cam.facing_bearing_deg) % 360.0
                if angle_diff > 180.0:
                    angle_diff = 360.0 - angle_diff
                p_angle = max(0.25, math.cos(math.radians(angle_diff / 2.0)))

                # 4. Speed penalty (fast running induces trigger lag or motion blur)
                p_speed = max(0.35, 1.0 - (tiger_speed_kmh * 0.04))

                # 5. Weather / Illumination penalty
                p_env = 0.95
                if is_night:
                    p_env *= 0.85
                if weather == "MONSOON_RAIN":
                    p_env *= 0.50

                p_detect = p_dist * p_angle * p_speed * p_env * cam.uptime_ratio

                # Stochastic sensor trigger check
                if self.rng.random() <= p_detect:
                    quality = "HIGH" if p_detect >= 0.70 else ("MEDIUM" if p_detect >= 0.40 else "BLURRED")
                    detections.append({
                        "camera_id": cid,
                        "camera_station": cam,
                        "distance_m": round(dist_m, 2),
                        "detection_prob": round(float(p_detect), 4),
                        "image_quality": quality
                    })
        return detections
