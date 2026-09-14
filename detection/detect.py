"""Run the trained tiger detector on one or more images and save annotated
output. Usage:

  python3 detect.py path/to/image.jpg [more images...]
  python3 detect.py path/to/a/folder/

Writes annotated copies (bounding boxes drawn) to detection/runs/predict/.
"""
import sys
from pathlib import Path

from ultralytics import YOLO

WEIGHTS = Path(__file__).parent / "runs" / "tiger_yolov8n" / "weights" / "best.pt"


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 detect.py <image_or_folder> [more...]")
        sys.exit(1)

    model = YOLO(str(WEIGHTS))
    results = model.predict(
        source=sys.argv[1:],
        conf=0.25,
        save=True,
        project=str(Path(__file__).parent / "runs"),
        name="predict",
        exist_ok=True,
    )
    for r in results:
        print(f"{r.path}: {len(r.boxes)} tiger(s) detected")
        for box in r.boxes:
            conf = float(box.conf[0])
            xyxy = box.xyxy[0].tolist()
            print(f"  confidence={conf:.3f}  box={[round(v) for v in xyxy]}")


if __name__ == "__main__":
    main()
