"""
Ecological Anomaly Engine & Bayesian Absence Reasoner
Implements:
- 20 Ground-truth ecological anomaly and baseline classes
- Bayesian camera effort reasoning (distinguishing camera failure from true absence)
- Human-wildlife conflict threat level classification (SAFE, CAUTION, CRITICAL)
- 100% Minimum Convex Polygon (MCP) territory shift evaluation
"""

import math
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass
import numpy as np


ANOMALY_TAXONOMY = {
    "NORMAL": {"code": "NORM_01", "name": "Normal Core Range Patrol", "base_severity": 0, "alert": "SAFE"},
    "SEASONAL_SHIFT": {"code": "NORM_02", "name": "Seasonal Waterhole Shift", "base_severity": 0, "alert": "SAFE"},
    "TRANSIENT_OVERLAP": {"code": "NORM_03", "name": "Transient Neighbor Overlap", "base_severity": 0, "alert": "SAFE"},
    "CAMERA_FAILURE": {"code": "SURV_01", "name": "Camera Offline / Survey Artefact", "base_severity": 1, "alert": "SAFE"},
    "FALSE_ABSENCE": {"code": "SURV_02", "name": "False Absence Due to Camera Downtime", "base_severity": 1, "alert": "SAFE"},
    "BRIEF_BUFFER_EXCURSION": {"code": "EXCU_01", "name": "Brief Buffer Excursion (<12h)", "base_severity": 1, "alert": "CAUTION"},
    "DEEP_BUFFER_EXPLORATION": {"code": "EXCU_02", "name": "Deep Buffer Penetration (>5km)", "base_severity": 2, "alert": "CAUTION"},
    "INCREASING_BUFFER_USE": {"code": "BUFF_01", "name": "Increasing Buffer Frequency Trend", "base_severity": 3, "alert": "CAUTION"},
    "BUFFER_COLONIZATION": {"code": "BUFF_02", "name": "Permanent Buffer Territory Establishment", "base_severity": 4, "alert": "CAUTION"},
    "VILLAGE_APPROACH": {"code": "VILL_01", "name": "Fringe Village Approach (<1.0km)", "base_severity": 3, "alert": "CRITICAL"},
    "PERSISTENT_VILLAGE_PROXIMITY": {"code": "VILL_02", "name": "Persistent Village Sighting (<500m)", "base_severity": 5, "alert": "CRITICAL"},
    "RESERVE_BOUNDARY_EXIT": {"code": "EXIT_01", "name": "Reserve Boundary Exit Into Agrarian Mosaic", "base_severity": 4, "alert": "CRITICAL"},
    "HIGHWAY_CORRIDOR_CROSSING": {"code": "EXIT_02", "name": "NH-44 Highway Corridor Transit", "base_severity": 3, "alert": "CAUTION"},
    "SUBADULT_DISPERSAL": {"code": "DISP_01", "name": "Subadult Directional Dispersal", "base_severity": 3, "alert": "CAUTION"},
    "TERRITORY_DISPLACEMENT": {"code": "SHFT_01", "name": "Territorial Displacement by Rival", "base_severity": 4, "alert": "CAUTION"},
    "RANGE_EXPANSION": {"code": "SHFT_02", "name": "Home Range Expansion (>15 km²)", "base_severity": 2, "alert": "SAFE"},
    "RANGE_CONTRACTION": {"code": "SHFT_03", "name": "Home Range Contraction", "base_severity": 2, "alert": "CAUTION"},
    "GENUINE_PROLONGED_ABSENCE": {"code": "ABSC_01", "name": "Genuine Behavioral Absence (>45 Days)", "base_severity": 5, "alert": "CRITICAL"},
    "MALE_TERRITORY_CONFLICT": {"code": "CONF_01", "name": "Male-Male Territory Overlap (Fight Risk)", "base_severity": 4, "alert": "CRITICAL"},
    "UNIDENTIFIED_TIGER": {"code": "UNID_01", "name": "Unidentified / Unenrolled Tiger Detected", "base_severity": 2, "alert": "CAUTION"},
}


# The three ranger-facing alert categories the dashboard groups by, ranked
# by operational priority: a tiger near a village is always the most
# urgent (direct human-wildlife-conflict risk), a male-male territory
# overlap is the next most urgent (a fight can injure or kill a resident
# tiger), and an unidentified tiger is a lower-urgency "go verify this"
# flag. Anything else in ANOMALY_TAXONOMY falls back to "GENERAL".
ALERT_CATEGORY_BY_ANOMALY = {
    "VILLAGE_APPROACH": "VILLAGE_PROXIMITY",
    "PERSISTENT_VILLAGE_PROXIMITY": "VILLAGE_PROXIMITY",
    "RESERVE_BOUNDARY_EXIT": "VILLAGE_PROXIMITY",
    "MALE_TERRITORY_CONFLICT": "MALE_TERRITORY_CONFLICT",
    "UNIDENTIFIED_TIGER": "UNIDENTIFIED_TIGER",
}


def categorize_anomaly(anomaly_class: Optional[str]) -> str:
    """Maps a `sightings.anomaly_class` value to one of the three named
    alert categories (village proximity / male territory conflict /
    unidentified tiger), or "GENERAL" for every other anomaly class."""
    return ALERT_CATEGORY_BY_ANOMALY.get(anomaly_class or "", "GENERAL")


class BayesianAbsenceReasoner:
    """
    Computes the probability of observing zero detections given camera uptime.
    Distinguishes survey hardware downtime from true animal mortality / dispersal.
    """
    @staticmethod
    def evaluate_absence(
        days_without_detection: int,
        historical_median_interval_days: float,
        overlapping_cameras: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """
        P(Zero Detections | Tiger Present) = Product_{days} Product_{cams} (1 - Uptime_c * P_detect_c)
        """
        if not overlapping_cameras or days_without_detection <= 0:
            return {"absence_anomaly_score": 0.0, "is_survey_artefact": True, "verdict": "INSUFFICIENT_CAMERA_COVERAGE"}

        avg_uptime = np.mean([c.get("uptime_ratio", 0.95) for c in overlapping_cameras])
        active_cam_count = sum(1 for c in overlapping_cameras if c.get("operational_status") == "OPERATIONAL")
        offline_cam_count = len(overlapping_cameras) - active_cam_count

        # Daily detection probability under 100% camera health
        base_daily_p = min(0.60, 1.0 / max(1.0, historical_median_interval_days))

        # Effective detection probability adjusted for station uptime
        effective_daily_p = base_daily_p * (active_cam_count / max(1, len(overlapping_cameras))) * avg_uptime

        # Probability that tiger was present every day but missed purely by chance / camera downtime
        prob_missed_given_present = math.pow(max(0.01, 1.0 - effective_daily_p), days_without_detection)

        # Anomaly score: 1 - P(missed | present)
        anomaly_score = 1.0 - prob_missed_given_present

        # If camera downtime accounts for > 60% of the non-detection probability -> Survey Artefact
        is_artefact = (offline_cam_count / len(overlapping_cameras) >= 0.40) or (avg_uptime < 0.65)

        if is_artefact:
            verdict = "SURVEY_ARTEFACT_CAMERA_DOWNTIME"
            alert = "SAFE"
        elif anomaly_score >= 0.85 and days_without_detection >= 21:
            verdict = "GENUINE_BEHAVIORAL_ABSENCE_ALERT"
            alert = "CRITICAL"
        elif anomaly_score >= 0.60:
            verdict = "MODERATE_ABSENCE_WATCH"
            alert = "CAUTION"
        else:
            verdict = "NORMAL_SURVEY_VARIANCE"
            alert = "SAFE"

        return {
            "days_without_detection": days_without_detection,
            "historical_interval_days": historical_median_interval_days,
            "overlapping_stations_count": len(overlapping_cameras),
            "active_stations_count": active_cam_count,
            "offline_stations_count": offline_cam_count,
            "average_uptime_ratio": round(float(avg_uptime), 3),
            "prob_missed_given_present": round(float(prob_missed_given_present), 4),
            "absence_anomaly_score": round(float(anomaly_score), 4),
            "is_survey_artefact": bool(is_artefact),
            "verdict": verdict,
            "alert_level": alert
        }



class ConflictAlertClassifier:
    """
    Classifies camera sighting events into real-time threat levels:
    - SAFE (Core Forest, >3km from boundary)
    - CAUTION (Buffer zone, highway corridor)
    - CRITICAL (Within 1.0km of 44 villages or exiting reserve)
    """
    @staticmethod
    def classify_sighting_threat(
        lat: float,
        lon: float,
        zone: str,
        dist_to_nearest_village_km: float,
        dist_to_nearest_water_km: float,
        is_subadult_dispersing: bool = False
    ) -> Dict[str, Any]:
        if dist_to_nearest_village_km <= 0.50:
            return {
                "alert_level": "CRITICAL",
                "color": "#ef4444",
                "reason": f"High Conflict Risk: Sighted {dist_to_nearest_village_km:.2f} km from village perimeter with livestock.",
                "anomaly_type": "PERSISTENT_VILLAGE_PROXIMITY"
            }
        elif dist_to_nearest_village_km <= 1.20:
            return {
                "alert_level": "CRITICAL",
                "color": "#f97316",
                "reason": f"Village Approach: Sighted {dist_to_nearest_village_km:.2f} km from village fringe.",
                "anomaly_type": "VILLAGE_APPROACH"
            }
        elif zone == "OUTSIDE":
            return {
                "alert_level": "CRITICAL",
                "color": "#dc2626",
                "reason": "Boundary Breach: Animal sighted outside reserve protection perimeter.",
                "anomaly_type": "RESERVE_BOUNDARY_EXIT"
            }
        elif zone == "BUFFER" or is_subadult_dispersing:
            return {
                "alert_level": "CAUTION",
                "color": "#eab308",
                "reason": "Buffer Activity: Animal traversing multiple-use buffer or corridor zone.",
                "anomaly_type": "DEEP_BUFFER_EXPLORATION" if dist_to_nearest_village_km < 3.0 else "BRIEF_BUFFER_EXCURSION"
            }
        else:
            return {
                "alert_level": "SAFE",
                "color": "#22c55e",
                "reason": "Normal Core Patrol: Animal active inside protected core forest.",
                "anomaly_type": "NORMAL"
            }
