"""
Unit & Integration Verification Test Suite for TYGRIS Platform
"""

import os
import sys
import json
import sqlite3


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.ml.pose import POSE_KEYPOINTS_15, SKELETON_CONNECTIONS, determine_flank_orientation, TigerPoseManager
from backend.app.simulation.anomaly_engine import ConflictAlertClassifier, BayesianAbsenceReasoner


def test_15_point_pose_topology():
    assert len(POSE_KEYPOINTS_15) == 15
    assert len(SKELETON_CONNECTIONS) >= 10
    mgr = TigerPoseManager()
    pose = mgr.get_pose_for_image("test_image.jpg")
    assert len(pose.keypoints) == 15
    assert pose.flank in ["Left", "Right", "Frontal"]
    assert pose.confidence >= 0.50


def test_conflict_alert_classifier():
    # Village fringe (< 0.5km) -> Critical
    res_crit = ConflictAlertClassifier.classify_sighting_threat(
        lat=21.612, lon=79.385, zone="BUFFER", dist_to_nearest_village_km=0.35, dist_to_nearest_water_km=0.8
    )
    assert res_crit["alert_level"] == "CRITICAL"

    # Buffer zone -> Caution
    res_caut = ConflictAlertClassifier.classify_sighting_threat(
        lat=21.575, lon=79.175, zone="BUFFER", dist_to_nearest_village_km=3.5, dist_to_nearest_water_km=0.5
    )
    assert res_caut["alert_level"] == "CAUTION"

    # Core forest -> Safe
    res_safe = ConflictAlertClassifier.classify_sighting_threat(
        lat=21.655, lon=79.255, zone="CORE", dist_to_nearest_village_km=6.0, dist_to_nearest_water_km=0.2
    )
    assert res_safe["alert_level"] == "SAFE"


def test_bayesian_absence_reasoner():
    # 40% cameras offline -> survey artefact
    cams_offline = [
        {"operational_status": "OFFLINE", "uptime_ratio": 0.30},
        {"operational_status": "OFFLINE", "uptime_ratio": 0.40},
        {"operational_status": "OPERATIONAL", "uptime_ratio": 0.95},
        {"operational_status": "OPERATIONAL", "uptime_ratio": 0.95},
    ]
    res_artefact = BayesianAbsenceReasoner.evaluate_absence(
        days_without_detection=25, historical_median_interval_days=4.0, overlapping_cameras=cams_offline
    )
    assert res_artefact["is_survey_artefact"] is True
    assert res_artefact["alert_level"] == "SAFE"

    # 100% cameras operational -> genuine absence alert
    cams_online = [
        {"operational_status": "OPERATIONAL", "uptime_ratio": 0.99},
        {"operational_status": "OPERATIONAL", "uptime_ratio": 0.98},
        {"operational_status": "OPERATIONAL", "uptime_ratio": 0.97},
    ]
    res_absence = BayesianAbsenceReasoner.evaluate_absence(
        days_without_detection=30, historical_median_interval_days=4.0, overlapping_cameras=cams_online
    )
    assert res_absence["is_survey_artefact"] is False
    assert res_absence["absence_anomaly_score"] >= 0.80


def test_database_and_gis_bundle():
    db_path = os.path.join(PROJECT_ROOT, "backend", "data", "pench_unified.db")
    bundle_path = os.path.join(PROJECT_ROOT, "backend", "data", "gis", "pench_web_bundle.json")

    assert os.path.exists(db_path)
    assert os.path.exists(bundle_path)

    # Check database counts
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM camera_stations")
    total_cams = cur.fetchone()[0]
    assert total_cams >= 300

    cur.execute("SELECT COUNT(*) FROM tiger_profiles")
    total_tigers = cur.fetchone()[0]
    assert total_tigers == 44

    cur.execute("SELECT COUNT(*) FROM sightings")
    total_sightings = cur.fetchone()[0]
    assert total_sightings > 0
    conn.close()

    # Check GIS bundle
    with open(bundle_path, "r", encoding="utf-8") as f:
        bundle = json.load(f)
    assert len(bundle["stations"]) >= 300
    assert len(bundle["villages"]) == 44
    assert len(bundle["sub_regions"]) == 11
    assert len(bundle["territories"]) == 44


if __name__ == "__main__":
    print("[Testing] Running Pose Topology Test...")
    test_15_point_pose_topology()
    print("[Testing] Running Conflict Threat Classifier Test...")
    test_conflict_alert_classifier()
    print("[Testing] Running Bayesian Absence Reasoner Test...")
    test_bayesian_absence_reasoner()
    print("[Testing] Running Database & GIS Bundle Test...")
    test_database_and_gis_bundle()
    print("\n[SUCCESS] All Backend & Simulation Unit Tests PASSED successfully!")
