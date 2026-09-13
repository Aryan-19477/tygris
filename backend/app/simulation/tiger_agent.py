"""
Agent-Based Tiger Population & Spatio-Temporal Movement Engine
Implements:
- 44 individual tigers with individual heterogeneity and biological priors
- Female philopatry (strong site fidelity, 20-55 km² home ranges)
- Male-biased dispersal (subadult exploration, 50-120+ km² home ranges)
- Multi-tier territory structure (core use, peripheral, overlap boundary)
- Step-Selection Function (SSF) over 100m fine landscape raster
- Circadian activity rhythm & seasonal water dependence
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




LIFE_STAGES = ["CUB", "SUBADULT", "YOUNG_ADULT", "ADULT", "OLDER_ADULT"]
BEHAVIORAL_STATES = ["RESTING", "FORAGING", "PATROLLING", "TRAVELING", "DISPERSING"]


@dataclass
class TigerAgent:
    tiger_id: str
    name: str
    sex: str                        # "FEMALE" | "MALE"
    age_years: float
    life_stage: str                 # CUB | SUBADULT | YOUNG_ADULT | ADULT | OLDER_ADULT
    body_condition: float           # 0.5 to 1.0
    territorial_status: str         # "RESIDENT", "TRANSIENT", "DISPERSING"
    home_range_target_km2: float    # Sampled: Female: 20-55, Male: 50-120
    core_centroid_lat: float
    core_centroid_lon: float
    current_lat: float
    current_lon: float
    current_state: str = "PATROLLING"
    current_bearing_deg: float = 0.0
    current_speed_kmh: float = 2.5
    preferred_habitat: str = "Teak-Bamboo Dense"
    water_dependency: float = 0.85
    human_avoidance: float = 0.95
    village_tolerance: float = 0.10
    activity_pattern: str = "CREPUSCULAR_NOCTURNAL"
    natal_centroid: Optional[Tuple[float, float]] = None
    step_history: List[Dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tiger_id": self.tiger_id,
            "name": self.name,
            "sex": self.sex,
            "age_years": round(self.age_years, 1),
            "life_stage": self.life_stage,
            "body_condition": round(self.body_condition, 2),
            "territorial_status": self.territorial_status,
            "home_range_target_km2": round(self.home_range_target_km2, 1),
            "core_centroid": [round(self.core_centroid_lat, 5), round(self.core_centroid_lon, 5)],
            "current_location": [round(self.current_lat, 5), round(self.current_lon, 5)],
            "current_state": self.current_state,
            "water_dependency": round(self.water_dependency, 2),
            "human_avoidance": round(self.human_avoidance, 2),
            "activity_pattern": self.activity_pattern,
            "total_steps_simulated": len(self.step_history)
        }


class TigerPopulationSimulator:
    """
    Simulates the agent-based tiger population and step-by-step landscape movements.
    """
    def __init__(self, env: PenchEnvironment, population_size: int = 44, random_seed: int = 42):
        self.env = env
        self.pop_size = population_size
        self.rng = np.random.default_rng(random_seed)
        self.tigers: Dict[str, TigerAgent] = {}

        self._initialize_population()

    def _initialize_population(self):
        """
        Initializes 44 tigers with demographic structures matching the WII 2021 Pench survey:
        ~58% Adult/Young Adult Females, ~32% Adult/Subadult Males, ~10% Older/Transients.
        """
        core_grids = [g for g in self.env.grids_2km.values() if g.zone == "CORE"]
        self.rng.shuffle(core_grids)

        for i in range(1, self.pop_size + 1):
            tid = f"PTR_TIG_{i:03d}"
            # Sex ratio: ~60% females, 40% males
            is_female = self.rng.random() < 0.60
            sex = "FEMALE" if is_female else "MALE"

            # Life stage distribution
            stage_roll = self.rng.random()
            if stage_roll < 0.12:
                stage = "SUBADULT"
                age = float(self.rng.uniform(1.5, 2.5))
            elif stage_roll < 0.35:
                stage = "YOUNG_ADULT"
                age = float(self.rng.uniform(2.5, 4.0))
            elif stage_roll < 0.85:
                stage = "ADULT"
                age = float(self.rng.uniform(4.0, 9.0))
            else:
                stage = "OLDER_ADULT"
                age = float(self.rng.uniform(9.0, 13.5))

            # Home range size sampling based on sex (PMC genetic study constraints)
            if is_female:
                # Female philopatry: smaller, tightly defended core territories
                hr_size = float(self.rng.uniform(20.0, 55.0))
                disp_status = "RESIDENT" if stage != "SUBADULT" else (
                    "DISPERSING" if self.rng.random() < 0.25 else "RESIDENT"
                )
            else:
                # Male-biased dispersal: expansive overlapping home ranges
                hr_size = float(self.rng.uniform(50.0, 115.0))
                disp_status = "DISPERSING" if stage == "SUBADULT" else "RESIDENT"

            # Choose centroid
            anchor_grid = core_grids[(i - 1) % len(core_grids)]
            c_lat = anchor_grid.center_lat + float(self.rng.uniform(-0.005, 0.005))
            c_lon = anchor_grid.center_lon + float(self.rng.uniform(-0.005, 0.005))

            agent = TigerAgent(
                tiger_id=tid,
                name=f"Pench Tiger {tid[-3:]} ({sex[0]})",
                sex=sex,
                age_years=age,
                life_stage=stage,
                body_condition=float(self.rng.uniform(0.75, 1.0)),
                territorial_status=disp_status,
                home_range_target_km2=hr_size,
                core_centroid_lat=c_lat,
                core_centroid_lon=c_lon,
                current_lat=c_lat,
                current_lon=c_lon,
                current_bearing_deg=float(self.rng.uniform(0.0, 360.0)),
                water_dependency=float(self.rng.uniform(0.75, 0.98)),
                human_avoidance=float(self.rng.uniform(0.85, 0.99)) if is_female else float(self.rng.uniform(0.70, 0.92)),
                village_tolerance=float(self.rng.uniform(0.02, 0.15)) if is_female else float(self.rng.uniform(0.08, 0.30)),
                natal_centroid=(c_lat, c_lon)
            )
            self.tigers[tid] = agent

        print(f"[TigerPopulation] Initialized {len(self.tigers)} tigers across Pench Reserve.")

    def step_agent_movement(
        self,
        tiger: TigerAgent,
        hour_of_day: int,
        season: str = "WINTER",
        step_duration_hours: float = 0.5
    ) -> Dict[str, Any]:
        """
        Executes a single Step-Selection Function (SSF) movement step for an individual tiger.
        """
        # 1. Evaluate circadian activity probability
        # Crepuscular (5-8, 17-21) and Nocturnal (21-5) peak
        is_crepuscular = (5 <= hour_of_day <= 8) or (17 <= hour_of_day <= 21)
        is_night = (hour_of_day > 21) or (hour_of_day < 5)
        activity_multiplier = 1.0 if is_crepuscular else (0.85 if is_night else 0.25)

        # 2. Determine state transition
        roll = self.rng.random()
        if activity_multiplier < 0.40 and roll > 0.30:
            tiger.current_state = "RESTING"
            speed_kmh = float(self.rng.uniform(0.0, 0.2))
        elif tiger.territorial_status == "DISPERSING":
            tiger.current_state = "DISPERSING" if roll < 0.60 else "FORAGING"
            speed_kmh = float(self.rng.uniform(4.0, 8.5))
        else:
            if roll < 0.50:
                tiger.current_state = "PATROLLING"
                speed_kmh = float(self.rng.uniform(2.0, 4.5))
            elif roll < 0.85:
                tiger.current_state = "FORAGING"
                speed_kmh = float(self.rng.uniform(0.8, 2.5))
            else:
                tiger.current_state = "TRAVELING"
                speed_kmh = float(self.rng.uniform(3.5, 6.0))

        tiger.current_speed_kmh = speed_kmh
        step_distance_km = speed_kmh * step_duration_hours

        # 3. Generate candidate step directions (8 directions around current position)
        candidate_bearings = np.linspace(0, 360, num=8, endpoint=False)
        utilities = []
        candidate_coords = []

        # Seasonal water weight: peak in summer
        beta_water = 3.5 if season == "SUMMER" else (0.8 if season == "MONSOON" else 1.8)

        for b in candidate_bearings:
            rad = math.radians(b)
            # 1 deg lat ~ 111.32 km, 1 deg lon ~ 103.5 km at 21.6°
            dlat = (step_distance_km * math.cos(rad)) / 111.32
            dlon = (step_distance_km * math.sin(rad)) / (111.32 * math.cos(math.radians(tiger.current_lat)))

            cand_lat = tiger.current_lat + dlat
            cand_lon = tiger.current_lon + dlon
            candidate_coords.append((cand_lat, cand_lon))

            zone = self.env.classify_zone(cand_lat, cand_lon)
            d_water = self.env.get_distance_to_nearest_water(cand_lat, cand_lon)
            d_village = self.env.get_distance_to_nearest_village(cand_lat, cand_lon)
            d_centroid = haversine_distance_km(cand_lat, cand_lon, tiger.core_centroid_lat, tiger.core_centroid_lon)

            # Calculate Utility Score U(j)
            # Habitat & Zone utility
            u_zone = 2.5 if zone == "CORE" else (1.0 if zone == "BUFFER" else -5.0)

            # Prey utility
            prey = self.env.sample_prey_density(zone if zone != "OUTSIDE" else "BUFFER")
            u_prey = prey / 20.0

            # Water utility
            u_water = beta_water * (1.0 / (0.1 + d_water))

            # Home range fidelity constraint (Gaussian penalty for straying far from centroid)
            # Dispersing subadults have lower fidelity
            max_r = math.sqrt(tiger.home_range_target_km2 / math.pi)
            fidelity_penalty = (d_centroid / max_r)**2 if tiger.territorial_status != "DISPERSING" else (d_centroid / (max_r * 2.5))

            # Directional persistence: prefer maintaining current bearing
            angle_diff = abs(b - tiger.current_bearing_deg) % 360.0
            if angle_diff > 180.0:
                angle_diff = 360.0 - angle_diff
            u_persist = 1.2 * math.cos(math.radians(angle_diff))

            # Human / Village avoidance penalty
            village_penalty = 0.0
            if d_village < 2.0:
                village_penalty = tiger.human_avoidance * (2.0 - d_village) * 4.0

            utility = u_zone + u_prey + u_water + u_persist - fidelity_penalty - village_penalty
            utilities.append(utility)

        # 4. Softmax probability sampling
        max_u = max(utilities)
        exp_u = [math.exp(u - max_u) for u in utilities]
        sum_exp = sum(exp_u)
        probs = [e / sum_exp for e in exp_u]

        chosen_idx = int(self.rng.choice(len(candidate_coords), p=probs))
        next_lat, next_lon = candidate_coords[chosen_idx]
        next_bearing = candidate_bearings[chosen_idx]

        tiger.current_lat = next_lat
        tiger.current_lon = next_lon
        tiger.current_bearing_deg = next_bearing

        step_record = {
            "lat": round(next_lat, 5),
            "lon": round(next_lon, 5),
            "speed_kmh": round(speed_kmh, 2),
            "bearing": round(next_bearing, 1),
            "state": tiger.current_state,
            "hour": hour_of_day,
            "zone": self.env.classify_zone(next_lat, next_lon)
        }
        tiger.step_history.append(step_record)
        return step_record
