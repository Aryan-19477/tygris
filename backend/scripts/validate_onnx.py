"""Validates exported ONNX (fp32 + fp16) models against the original PyTorch models."""
import os
import sys

import numpy as np
import torch
import onnxruntime as ort
from PIL import Image

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE_DIR)

from app.ml.representation import get_representation_model, get_paper_reid_transforms
from app.ml.metric_learning import get_metric_model

ONNX_DIR = os.path.join(BASE_DIR, "onnx_export")
IMG_PATH = os.path.join(BASE_DIR, "data", "captures", "EVT_LIVE_18DB04.jpg")

transform = get_paper_reid_transforms(input_size=(224, 224), is_training=False)
img = Image.open(IMG_PATH).convert("RGB")
x = transform(img).unsqueeze(0)
x_np = x.numpy().astype(np.float32)


def cos_sim(a, b):
    a, b = a.flatten(), b.flatten()
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-8))


def check(name, torch_model, forward_fn, onnx_base):
    torch_model.eval()
    with torch.no_grad():
        torch_out = forward_fn(torch_model, x).numpy()

    for suffix in ["", "_fp16"]:
        path = os.path.join(ONNX_DIR, f"{onnx_base}{suffix}.onnx")
        sess = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
        onnx_out = sess.run(None, {"input": x_np})[0]
        sim = cos_sim(torch_out, onnx_out)
        max_abs_diff = float(np.max(np.abs(torch_out.astype(np.float32) - onnx_out.astype(np.float32))))
        label = f"{name}{suffix or ' (fp32)'}"
        print(f"{label:35s} cos_sim={sim:.6f}  max_abs_diff={max_abs_diff:.6f}")


rep_model = get_representation_model(num_classes=62, name="ConvNeXt-small", pretrained=False)
rep_model.load_state_dict(torch.load(os.path.join(BASE_DIR, "checkpoints", "convnext_representation_best.pth"), map_location="cpu", weights_only=True))
check("representation", rep_model, lambda m, x: m(x), "convnext_representation")

metric_model = get_metric_model(name="ConvNeXt-small", embedding_dim=64, pretrained=False)
metric_model.load_state_dict(torch.load(os.path.join(BASE_DIR, "checkpoints", "convnext_metric_best.pth"), map_location="cpu", weights_only=True))
check("metric", metric_model, lambda m, x: m.extract_normalized_embeddings(x), "convnext_metric")

# Top-1 class agreement check for representation model (fp16)
sess = ort.InferenceSession(os.path.join(ONNX_DIR, "convnext_representation_fp16.onnx"), providers=["CPUExecutionProvider"])
onnx_logits = sess.run(None, {"input": x_np})[0]
with torch.no_grad():
    torch_logits = rep_model(x).numpy()
print("torch top1:", int(np.argmax(torch_logits)), " onnx_fp16 top1:", int(np.argmax(onnx_logits)))
