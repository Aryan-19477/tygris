"""
Pass 1 Cheap Screening: Blank/Empty Rejection + YOLOv8 Animal Detection + Best-Frame Selection.

Standalone pre-filter for camera-trap video clips. Runs before any deep
Re-ID model: strips blank/IR-glitch frames, rejects person/vehicle triggers
and non-target wildlife, then quality-ranks the remaining candidate frames
to pick the single best representative frame of the animal.

Does not perform tiger identification - this is a screening/best-frame-
selection utility only. No model training required; YOLOv8n-seg runs with
its stock COCO-pretrained weights (auto-downloaded by ultralytics on first
use).
"""

import base64
import io
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import cv2
import numpy as np
from PIL import Image

# COCO class ids
NON_ANIMAL_CLASSES = {0, 1, 2, 3, 5, 7}  # person, bicycle, car, motorcycle, bus, truck
ANIMAL_CLASSES = {14, 15, 16, 17, 18, 19, 20, 21, 22, 23}  # bird..giraffe

BLANK_STD_THRESHOLD = 5.0
BLANK_RANGE_THRESHOLD = 12

# Warm tawny/orange tiger coat hue band (OpenCV HSV: H in [0,180])
COAT_HUE_RANGE = (3, 32)
COAT_SAT_MIN = 20
COAT_VAL_MIN = 35
COAT_MIN_FRACTION = 0.06  # min fraction of bbox pixels that must look coat-like


@dataclass
class FrameResult:
    index: int
    timestamp_sec: float
    status: str  # "KEPT" | "REJECTED"
    reason: str  # BLANK_IMAGE | NO_ANIMAL | NON_ANIMAL | NON_TARGET_WILDLIFE | TIGER_CANDIDATE
    quality_score: float = 0.0
    detection_class: Optional[str] = None
    detection_conf: float = 0.0
    thumbnail: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "index": self.index,
            "timestamp_sec": round(self.timestamp_sec, 2),
            "status": self.status,
            "reason": self.reason,
            "quality_score": round(self.quality_score, 4),
            "detection_class": self.detection_class,
            "detection_conf": round(self.detection_conf, 4),
            "thumbnail": self.thumbnail,
        }


class Pass1Screener:
    """Lazily loads YOLOv8n-seg (COCO pretrained) and runs the screening pass."""

    _model = None

    def _get_model(self):
        if Pass1Screener._model is None:
            from ultralytics import YOLO

            Pass1Screener._model = YOLO("yolov8n-seg.pt")
        return Pass1Screener._model

    @staticmethod
    def _is_blank(frame_bgr: np.ndarray) -> bool:
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        std = float(np.std(gray))
        rng = float(np.max(gray)) - float(np.min(gray))
        return std < BLANK_STD_THRESHOLD or rng < BLANK_RANGE_THRESHOLD

    @staticmethod
    def _coat_gate_passes(frame_bgr: np.ndarray, box: List[int]) -> bool:
        x1, y1, x2, y2 = box
        crop = frame_bgr[max(0, y1):max(0, y2), max(0, x1):max(0, x2)]
        if crop.size == 0:
            return False
        hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
        mask = (
            (h >= COAT_HUE_RANGE[0]) & (h <= COAT_HUE_RANGE[1])
            & (s >= COAT_SAT_MIN) & (v >= COAT_VAL_MIN)
        )
        fraction = float(np.mean(mask))
        return fraction >= COAT_MIN_FRACTION

    @staticmethod
    def _quality_score(frame_bgr: np.ndarray, box: List[int], frame_w: int, frame_h: int) -> float:
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        sharpness = min(1.0, laplacian_var / 500.0)

        contrast = min(1.0, float(np.std(gray)) / 80.0)

        x1, y1, x2, y2 = box
        box_w, box_h = max(1, x2 - x1), max(1, y2 - y1)
        cx, cy = x1 + box_w / 2.0, y1 + box_h / 2.0
        center_dist = ((cx - frame_w / 2.0) ** 2 + (cy - frame_h / 2.0) ** 2) ** 0.5
        max_dist = ((frame_w / 2.0) ** 2 + (frame_h / 2.0) ** 2) ** 0.5
        centeredness = 1.0 - min(1.0, center_dist / max(1.0, max_dist))
        clipped = (x1 <= 2 or y1 <= 2 or x2 >= frame_w - 2 or y2 >= frame_h - 2)
        body_score = centeredness * (0.6 if clipped else 1.0)

        return 0.45 * sharpness + 0.35 * contrast + 0.20 * body_score

    @staticmethod
    def _to_thumbnail_b64(frame_bgr: np.ndarray, max_width: int = 320) -> str:
        h, w = frame_bgr.shape[:2]
        if w > max_width:
            scale = max_width / w
            frame_bgr = cv2.resize(frame_bgr, (max_width, int(h * scale)))
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        img = Image.fromarray(rgb)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=80)
        b64 = base64.b64encode(buf.getvalue()).decode("utf-8")
        return f"data:image/jpeg;base64,{b64}"

    def screen(self, video_path: str, sample_fps: float = 3.0, conf_threshold: float = 0.10) -> Dict[str, Any]:
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise ValueError(f"Could not open video file: {video_path}")

        native_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        frame_interval = max(1, round(native_fps / sample_fps))

        model = self._get_model()
        frames: List[FrameResult] = []
        counts = {
            "BLANK_IMAGE": 0,
            "NON_ANIMAL": 0,
            "NO_ANIMAL": 0,
            "NON_TARGET_WILDLIFE": 0,
            "TIGER_CANDIDATE": 0,
        }

        frame_idx = 0
        sampled_idx = 0
        best_frame: Optional[FrameResult] = None
        best_frame_full_b64: Optional[str] = None

        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            if frame_idx % frame_interval != 0:
                frame_idx += 1
                continue

            timestamp = frame_idx / native_fps
            h, w = frame_bgr.shape[:2]
            thumb = self._to_thumbnail_b64(frame_bgr)

            if self._is_blank(frame_bgr):
                counts["BLANK_IMAGE"] += 1
                frames.append(FrameResult(
                    index=sampled_idx, timestamp_sec=timestamp, status="REJECTED",
                    reason="BLANK_IMAGE", thumbnail=thumb,
                ))
                frame_idx += 1
                sampled_idx += 1
                continue

            results = model.predict(frame_bgr, conf=conf_threshold, verbose=False)[0]
            boxes = results.boxes

            best_box_cls = None
            best_box_conf = 0.0
            best_box_xyxy = None
            saw_non_animal = False

            if boxes is not None and len(boxes) > 0:
                for b in boxes:
                    cls_id = int(b.cls[0])
                    conf = float(b.conf[0])
                    if cls_id in NON_ANIMAL_CLASSES:
                        saw_non_animal = True
                    if cls_id in ANIMAL_CLASSES and conf > best_box_conf:
                        best_box_cls = cls_id
                        best_box_conf = conf
                        best_box_xyxy = [int(v) for v in b.xyxy[0].tolist()]

            if best_box_xyxy is not None:
                if self._coat_gate_passes(frame_bgr, best_box_xyxy):
                    q = self._quality_score(frame_bgr, best_box_xyxy, w, h)
                    fr = FrameResult(
                        index=sampled_idx, timestamp_sec=timestamp, status="KEPT",
                        reason="TIGER_CANDIDATE", quality_score=q,
                        detection_class=model.names.get(best_box_cls, str(best_box_cls)),
                        detection_conf=best_box_conf, thumbnail=thumb,
                    )
                    counts["TIGER_CANDIDATE"] += 1
                    if best_frame is None or q > best_frame.quality_score:
                        best_frame = fr
                        best_frame_full_b64 = self._to_thumbnail_b64(frame_bgr, max_width=1280)
                else:
                    counts["NON_TARGET_WILDLIFE"] += 1
                    frames.append(FrameResult(
                        index=sampled_idx, timestamp_sec=timestamp, status="REJECTED",
                        reason="NON_TARGET_WILDLIFE",
                        detection_class=model.names.get(best_box_cls, str(best_box_cls)),
                        detection_conf=best_box_conf, thumbnail=thumb,
                    ))
                    frame_idx += 1
                    sampled_idx += 1
                    continue
            elif saw_non_animal:
                counts["NON_ANIMAL"] += 1
                frames.append(FrameResult(
                    index=sampled_idx, timestamp_sec=timestamp, status="REJECTED",
                    reason="NON_ANIMAL", thumbnail=thumb,
                ))
                frame_idx += 1
                sampled_idx += 1
                continue
            else:
                counts["NO_ANIMAL"] += 1
                frames.append(FrameResult(
                    index=sampled_idx, timestamp_sec=timestamp, status="REJECTED",
                    reason="NO_ANIMAL", thumbnail=thumb,
                ))
                frame_idx += 1
                sampled_idx += 1
                continue

            frames.append(fr)
            frame_idx += 1
            sampled_idx += 1

        cap.release()

        total = len(frames)
        return {
            "total_frames_sampled": total,
            "sample_fps": sample_fps,
            "counts": counts,
            "frames": [f.to_dict() for f in frames],
            "best_frame": (
                {**best_frame.to_dict(), "full_image": best_frame_full_b64}
                if best_frame is not None else None
            ),
        }


_screener_singleton: Optional[Pass1Screener] = None


def screen_video(video_path: str, sample_fps: float = 3.0) -> Dict[str, Any]:
    global _screener_singleton
    if _screener_singleton is None:
        _screener_singleton = Pass1Screener()
    return _screener_singleton.screen(video_path, sample_fps=sample_fps)
