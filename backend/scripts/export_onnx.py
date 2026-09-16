"""
Exports the 3 inference models (YOLOv8n-seg, ConvNeXt-small representation,
ConvNeXt-small metric) to ONNX for client-side (browser) inference.
ConvNeXt models are additionally exported as fp16 for smaller download size.
"""
import os
import sys

import torch
import onnx
from onnxconverter_common import float16

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE_DIR)

from app.ml.representation import get_representation_model
from app.ml.metric_learning import get_metric_model

CHECKPOINTS_DIR = os.path.join(BASE_DIR, "checkpoints")
OUT_DIR = os.path.join(BASE_DIR, "onnx_export")
os.makedirs(OUT_DIR, exist_ok=True)


def export_yolo_seg():
    from ultralytics import YOLO
    model = YOLO(os.path.join(BASE_DIR, "yolov8n-seg.pt"))
    exported_path = model.export(format="onnx", opset=17, simplify=True, imgsz=640)
    dst = os.path.join(OUT_DIR, "yolov8n-seg.onnx")
    if os.path.abspath(exported_path) != os.path.abspath(dst):
        os.replace(exported_path, dst)
    print(f"[yolo] exported -> {dst}")


def export_convnext(model: torch.nn.Module, ckpt_name: str, out_name: str, forward_fn=None):
    ckpt_path = os.path.join(CHECKPOINTS_DIR, ckpt_name)
    state = torch.load(ckpt_path, map_location="cpu", weights_only=True)
    model.load_state_dict(state)
    model.eval()

    dummy = torch.randn(1, 3, 224, 224)
    fp32_path = os.path.join(OUT_DIR, out_name)

    class Wrapper(torch.nn.Module):
        def __init__(self, m, fn):
            super().__init__()
            self.m = m
            self.fn = fn

        def forward(self, x):
            return self.fn(self.m, x) if self.fn else self.m(x)

    wrapped = Wrapper(model, forward_fn)
    torch.onnx.export(
        wrapped,
        dummy,
        fp32_path,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        opset_version=17,
    )
    print(f"[{out_name}] fp32 exported -> {fp32_path}")

    onnx_model = onnx.load(fp32_path)
    onnx.checker.check_model(onnx_model)
    fp16_model = float16.convert_float_to_float16(onnx_model, keep_io_types=True)
    fp16_path = fp32_path.replace(".onnx", "_fp16.onnx")
    onnx.save(fp16_model, fp16_path)
    print(f"[{out_name}] fp16 exported -> {fp16_path}")


def main():
    export_yolo_seg()

    rep_model = get_representation_model(num_classes=62, name="ConvNeXt-small", pretrained=False)
    export_convnext(rep_model, "convnext_representation_best.pth", "convnext_representation.onnx")

    metric_model = get_metric_model(name="ConvNeXt-small", embedding_dim=64, pretrained=False)
    export_convnext(
        metric_model,
        "convnext_metric_best.pth",
        "convnext_metric.onnx",
        forward_fn=lambda m, x: m.extract_normalized_embeddings(x),
    )


if __name__ == "__main__":
    main()
