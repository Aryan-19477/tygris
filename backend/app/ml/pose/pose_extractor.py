"""
15-Point Anatomical Keypoint Extractor & Pose Topology Definition
Reference: ATRW (Amur Tiger Re-identification in the Wild) Keypoint Benchmark.

Keypoints (15 points):
 0: Nose
 1: Left Eye
 2: Right Eye
 3: Left Ear
 4: Right Ear
 5: Neck
 6: Left Shoulder
 7: Right Shoulder
 8: Left Front Paw
 9: Right Front Paw
10: Left Hip
11: Right Hip
12: Left Back Paw
13: Right Back Paw
14: Tail Base
"""

import os
import json
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass
import numpy as np


POSE_KEYPOINTS_15 = [
    {"id": 0, "name": "Nose", "category": "head"},
    {"id": 1, "name": "Left Eye", "category": "head"},
    {"id": 2, "name": "Right Eye", "category": "head"},
    {"id": 3, "name": "Left Ear", "category": "head"},
    {"id": 4, "name": "Right Ear", "category": "head"},
    {"id": 5, "name": "Neck", "category": "torso"},
    {"id": 6, "name": "Left Shoulder", "category": "limbs_front"},
    {"id": 7, "name": "Right Shoulder", "category": "limbs_front"},
    {"id": 8, "name": "Left Front Paw", "category": "limbs_front"},
    {"id": 9, "name": "Right Front Paw", "category": "limbs_front"},
    {"id": 10, "name": "Left Hip", "category": "limbs_back"},
    {"id": 11, "name": "Right Hip", "category": "limbs_back"},
    {"id": 12, "name": "Left Back Paw", "category": "limbs_back"},
    {"id": 13, "name": "Right Back Paw", "category": "limbs_back"},
    {"id": 14, "name": "Tail Base", "category": "torso"}
]

# Anatomical bone connections (start_id, end_id)
SKELETON_CONNECTIONS = [
    (0, 1), (0, 2),        # Nose to Eyes
    (1, 3), (2, 4),        # Eyes to Ears
    (1, 5), (2, 5),        # Head to Neck
    (5, 6), (5, 7),        # Neck to Shoulders
    (6, 8), (7, 9),        # Shoulders to Front Paws
    (5, 14),               # Spine: Neck to Tail Base
    (14, 10), (14, 11),    # Tail Base to Hips
    (10, 12), (11, 13)     # Hips to Back Paws
]


@dataclass
class Keypoint:
    x: float
    y: float
    visibility: int  # 0: unannotated/occluded, 1: occluded but labeled, 2: visible


@dataclass
class TigerPoseKeypoints:
    image_id: str
    keypoints: List[Dict[str, Any]]
    flank: str  # "Left", "Right", or "Frontal"
    confidence: float
    bbox: Optional[List[float]] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "image_id": self.image_id,
            "keypoints": self.keypoints,
            "flank": self.flank,
            "confidence": self.confidence,
            "bbox": self.bbox,
            "skeleton_connections": SKELETON_CONNECTIONS,
            "keypoint_names": [kp["name"] for kp in POSE_KEYPOINTS_15]
        }


def determine_flank_orientation(keypoints: List[Dict[str, Any]]) -> Tuple[str, float]:
    """
    Determines whether a tiger's visible flank is Left or Right based on
    anatomical keypoint coordinates and visibility scores.
    """
    # Keypoint indices:
    # Left side: 1 (L. Eye), 3 (L. Ear), 6 (L. Shoulder), 8 (L. Front Paw), 10 (L. Hip), 12 (L. Back Paw)
    # Right side: 2 (R. Eye), 4 (R. Ear), 7 (R. Shoulder), 9 (R. Front Paw), 11 (R. Hip), 13 (R. Back Paw)
    left_indices = [1, 3, 6, 8, 10, 12]
    right_indices = [2, 4, 7, 9, 11, 13]

    left_vis_count = sum(1 for idx in left_indices if idx < len(keypoints) and keypoints[idx].get("visibility", 0) > 0)
    right_vis_count = sum(1 for idx in right_indices if idx < len(keypoints) and keypoints[idx].get("visibility", 0) > 0)

    # Check horizontal vector between Head (Nose/Neck) and Tail Base
    nose = keypoints[0] if len(keypoints) > 0 else None
    neck = keypoints[5] if len(keypoints) > 5 else None
    tail = keypoints[14] if len(keypoints) > 14 else None

    head_x = nose.get("x", 0) if nose and nose.get("visibility", 0) > 0 else (neck.get("x", 0) if neck else 0)
    tail_x = tail.get("x", 0) if tail and tail.get("visibility", 0) > 0 else 0

    if left_vis_count > right_vis_count:
        flank = "Left"
        conf = float(left_vis_count / (left_vis_count + right_vis_count + 1e-5))
    elif right_vis_count > left_vis_count:
        flank = "Right"
        conf = float(right_vis_count / (left_vis_count + right_vis_count + 1e-5))
    else:
        # Fallback to head-to-tail orientation
        if head_x < tail_x:
            flank = "Left" # Walking left-to-right typically exposes left flank or right depending on camera
            conf = 0.65
        else:
            flank = "Right"
            conf = 0.65

    return flank, min(0.99, max(0.50, conf))


class TigerPoseManager:
    """
    Manages loading and querying anatomical pose keypoints for the dataset.
    """
    def __init__(self, keypoints_files: Optional[List[str]] = None):
        self.database: Dict[str, Dict[str, Any]] = {}
        if keypoints_files:
            for fpath in keypoints_files:
                if os.path.exists(fpath):
                    self.load_keypoints_json(fpath)

    def load_keypoints_json(self, fpath: str):
        """Loads ATRW / COCO formatted keypoint annotation JSON."""
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                data = json.load(f)

            # Support list format or dict format
            if isinstance(data, list):
                for item in data:
                    img_id = str(item.get("image_id", item.get("id", "")))
                    self.database[img_id] = item
            elif isinstance(data, dict):
                if "annotations" in data:
                    for item in data["annotations"]:
                        img_id = str(item.get("image_id", ""))
                        self.database[img_id] = item
                else:
                    self.database.update(data)
        except Exception as e:
            print(f"[PoseManager] Failed to load keypoint file {fpath}: {e}")

    def get_pose_for_image(self, image_id: str, image_width: int = 1920, image_height: int = 1080) -> TigerPoseKeypoints:
        """Retrieves or synthesizes 15-point pose keypoints for a given image."""
        raw = self.database.get(image_id)
        if raw and "keypoints" in raw:
            kps_raw = raw["keypoints"]
            formatted_kps = []
            if isinstance(kps_raw, list) and len(kps_raw) >= 45:
                for i in range(15):
                    x = float(kps_raw[i * 3])
                    y = float(kps_raw[i * 3 + 1])
                    v = int(kps_raw[i * 3 + 2])
                    formatted_kps.append({"id": i, "name": POSE_KEYPOINTS_15[i]["name"], "x": x, "y": y, "visibility": v})
            elif isinstance(kps_raw, list) and len(kps_raw) == 15 and isinstance(kps_raw[0], dict):
                formatted_kps = kps_raw
            else:
                formatted_kps = self._generate_canonical_pose(image_width, image_height)
        else:
            formatted_kps = self._generate_canonical_pose(image_width, image_height)

        flank, conf = determine_flank_orientation(formatted_kps)
        return TigerPoseKeypoints(
            image_id=image_id,
            keypoints=formatted_kps,
            flank=flank,
            confidence=conf,
            bbox=[0.15 * image_width, 0.2 * image_height, 0.85 * image_width, 0.8 * image_height]
        )

    def _generate_canonical_pose(self, width: int, height: int) -> List[Dict[str, Any]]:
        """Generates realistic anatomical proportions when exact annotation is missing."""
        cx = width * 0.5
        cy = height * 0.55
        scale_x = width * 0.35
        scale_y = height * 0.25

        # Canonical left-facing tiger pose coordinates
        canonical_relative = [
            (0, -0.9, -0.1, 2),   # Nose
            (1, -0.75, -0.25, 2), # Left Eye
            (2, -0.72, -0.3, 1),  # Right Eye (partially occluded)
            (3, -0.6, -0.45, 2),  # Left Ear
            (4, -0.55, -0.48, 1), # Right Ear
            (5, -0.45, -0.1, 2),  # Neck
            (6, -0.25, 0.1, 2),   # Left Shoulder
            (7, -0.2, 0.05, 1),   # Right Shoulder
            (8, -0.28, 0.75, 2),  # Left Front Paw
            (9, -0.18, 0.72, 2),  # Right Front Paw
            (10, 0.45, 0.15, 2),  # Left Hip
            (11, 0.5, 0.1, 1),    # Right Hip
            (12, 0.42, 0.8, 2),   # Left Back Paw
            (13, 0.52, 0.78, 2),  # Right Back Paw
            (14, 0.65, 0.0, 2)    # Tail Base
        ]

        formatted = []
        for kid, rx, ry, v in canonical_relative:
            px = cx + rx * scale_x
            py = cy + ry * scale_y
            formatted.append({
                "id": kid,
                "name": POSE_KEYPOINTS_15[kid]["name"],
                "x": round(px, 1),
                "y": round(py, 1),
                "visibility": v
            })
        return formatted
