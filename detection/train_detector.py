"""Train a YOLOv8n tiger detector on the NTLNP voc_day/voc_night subset
converted by prepare_voc_data.py.

This is the missing first stage ahead of identification/: that pipeline
assumes a tiger is already isolated in the frame, but camera-trap captures
arrive as full scenes that may contain no tiger, a distant/partial tiger,
or another species entirely (17 other classes are annotated in the same
source dataset). A dedicated detector can localize the tiger before
anything reaches the re-ID embedder, and its box can also stand in for the
segmentation-layer background removal the research paper found most
impactful, without training a full pixel-level segmenter.

YOLOv8n (nano) is used for a fast first run - small enough to iterate on
quickly, upgradeable to yolov8s/m later once this baseline is validated.
"""
from pathlib import Path

from ultralytics import YOLO

DATA_YAML = Path(__file__).parent / "data" / "data.yaml"
EPOCHS = 60
IMG_SIZE = 640
BATCH = 16
RUN_NAME = "tiger_yolov8n"


def main():
    model = YOLO("yolov8n.pt")
    model.train(
        data=str(DATA_YAML),
        epochs=EPOCHS,
        imgsz=IMG_SIZE,
        batch=BATCH,
        name=RUN_NAME,
        project=str(Path(__file__).parent / "runs"),
        patience=15,
        exist_ok=True,
        # This environment's installed cuDNN doesn't match the version
        # torch/cu130 expects, which crashes ultralytics' AMP sanity check
        # (CUDNN_STATUS_SUBLIBRARY_VERSION_MISMATCH) before training even
        # starts. Disabling AMP avoids that broken check path entirely;
        # training still runs on GPU, just in FP32.
        amp=False,
    )

    metrics = model.val()
    print("\nValidation metrics:")
    print(f"  mAP50:    {metrics.box.map50:.4f}")
    print(f"  mAP50-95: {metrics.box.map:.4f}")


if __name__ == "__main__":
    main()
