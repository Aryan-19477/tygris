"""
Tiger 15-Point Anatomical Pose & Flank Orientation Module
Extracts, formats, and validates 15-point tiger skeletal pose keypoints and determines flank orientation (Left vs. Right).
"""

from .pose_extractor import (
    POSE_KEYPOINTS_15,
    SKELETON_CONNECTIONS,
    TigerPoseKeypoints,
    TigerPoseManager,
    determine_flank_orientation
)

__all__ = [
    "POSE_KEYPOINTS_15",
    "SKELETON_CONNECTIONS",
    "TigerPoseKeypoints",
    "TigerPoseManager",
    "determine_flank_orientation"
]
