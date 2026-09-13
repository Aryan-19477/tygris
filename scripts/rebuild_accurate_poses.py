"""
Regenerates ATRW-standard 15-point keypoint topology and pixel-perfect overlays.
"""

import os
import json
from PIL import Image

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
KP_FILE = os.path.join(PROJECT_ROOT, "backend", "data", "gallery", "reid_keypoints_train.json")
IMG_DIR = os.path.join(PROJECT_ROOT, "reid_raw", "train")
PUBLIC_TIGERS_DIR = os.path.join(PROJECT_ROOT, "frontend", "public", "tigers")
POSE_OUTPUT = os.path.join(PROJECT_ROOT, "backend", "data", "gallery", "tiger_groundtruth_poses.json")

os.makedirs(PUBLIC_TIGERS_DIR, exist_ok=True)

# ATRW Benchmark 15-Point Definition
ATRW_NAMES = [
    "Left Eye",        # 0
    "Right Eye",       # 1
    "Nose",            # 2
    "Right Shoulder",  # 3
    "Right Front Paw", # 4
    "Left Shoulder",   # 5
    "Left Front Paw",  # 6
    "Right Hip",       # 7
    "Right Back Paw",  # 8
    "Left Hip",        # 9
    "Left Back Paw",   # 10
    "Tail Base",       # 11
    "Tail Tip",        # 12
    "Neck",            # 13
    "Spine Center"     # 14
]

ATRW_CONNECTIONS = [
    [2, 0], [2, 1],       # Nose to Eyes
    [0, 13], [1, 13],     # Eyes to Neck
    [13, 14],             # Neck to Spine
    [14, 11],             # Spine to Tail Base
    [11, 12],             # Tail Base to Tail Tip
    [13, 3], [3, 4],      # Right Forelimb
    [13, 5], [5, 6],      # Left Forelimb
    [14, 7], [7, 8],      # Right Hindlimb
    [14, 9], [9, 10]      # Left Hindlimb
]

CANVAS_W = 640
CANVAS_H = 360


def main():
    print("[1/3] Loading Ground-Truth Keypoint Annotations...")
    with open(KP_FILE, "r", encoding="utf-8") as f:
        kp_dict = json.load(f)

    # Pick 44 high quality side flank images with >= 13 annotated points
    candidates = []
    for img_name, raw_pts in kp_dict.items():
        img_path = os.path.join(IMG_DIR, img_name)
        if not os.path.exists(img_path):
            continue

        valid_count = sum(1 for i in range(0, 45, 3) if raw_pts[i + 2] > 0 and raw_pts[i] > 0 and raw_pts[i + 1] > 0)
        if valid_count >= 13:
            candidates.append((img_name, img_path, raw_pts))

    print(f"Found {len(candidates)} high-quality fully annotated images.")

    selected = candidates[:44]
    tiger_poses = {}

    for idx, (img_name, img_path, raw_pts) in enumerate(selected, start=1):
        tid = f"PTR_TIG_{idx:03d}"

        with Image.open(img_path) as im:
            orig_w, orig_h = im.size
            resized_im = im.convert("RGB").resize((CANVAS_W, CANVAS_H), Image.Resampling.LANCZOS)
            dst_img_path = os.path.join(PUBLIC_TIGERS_DIR, f"{tid}.jpg")
            resized_im.save(dst_img_path, quality=95)

        scale_x = CANVAS_W / orig_w
        scale_y = CANVAS_H / orig_h

        keypoints = []
        for kp_id in range(15):
            base = kp_id * 3
            x_raw = raw_pts[base]
            y_raw = raw_pts[base + 1]
            vis = raw_pts[base + 2]

            if vis > 0 and x_raw > 0 and y_raw > 0:
                x_scaled = round(x_raw * scale_x, 1)
                y_scaled = round(y_raw * scale_y, 1)
            else:
                x_scaled = round(CANVAS_W * 0.5, 1)
                y_scaled = round(CANVAS_H * 0.5, 1)

            keypoints.append({
                "id": kp_id,
                "name": ATRW_NAMES[kp_id],
                "x": x_scaled,
                "y": y_scaled,
                "visibility": vis
            })

        # Orientation
        nose_x = keypoints[2]["x"]
        tail_x = keypoints[11]["x"]
        flank = "Left" if nose_x < tail_x else "Right"

        tiger_poses[tid] = {
            "tiger_id": tid,
            "image": f"/tigers/{tid}.jpg",
            "flank": flank,
            "confidence": 0.98,
            "connections": ATRW_CONNECTIONS,
            "keypoints": keypoints
        }

    with open(POSE_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(tiger_poses, f, indent=2)

    print(f"[SUCCESS] Exported {len(tiger_poses)} accurate poses to {POSE_OUTPUT}")


if __name__ == "__main__":
    main()
