"""
Extended training run: takes the winning metric-learning hyperparameters
from train_reid_models.py's sweep (metric_160_unfrozen_p16k2_lr3e-4) and
trains it for far more epochs on GPU, instead of splitting time across 6
short (6-8 epoch) sweep configs. The sweep runs had val accuracy still
climbing steeply when they stopped - this just gives the same setup room
to actually converge.

Overwrites backend/checkpoints/convnext_metric_best.pth and
backend/data/gallery/trained_gallery.json (the files the live app loads),
the same as train_reid_models.py's final step - only if this run beats
val_precision_at_1 recorded in sweep_results.json for the same config name.

Run with the venv that has torch installed:
    D:/tygris_venv/Scripts/python.exe -u backend/scripts/train_reid_extended.py
"""

import os
import sys
import json

import torch

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.scripts.train_reid_models import (
    MetricConfig, list_dataset, split_train_val, run_metric_config,
    build_gallery, CHECKPOINTS_DIR, GALLERY_PATH, SWEEP_RESULTS_PATH, DEVICE,
)

EPOCHS = int(os.environ.get("EXT_EPOCHS", "55"))
IMG_SIZE = int(os.environ.get("EXT_IMG_SIZE", "192"))
EMBED_DIM = int(os.environ.get("EXT_EMBED_DIM", "128"))
WEIGHT_DECAY = float(os.environ.get("EXT_WEIGHT_DECAY", "3e-4"))

CFG = MetricConfig(
    name=f"metric_extended_{IMG_SIZE}_d{EMBED_DIM}_p16k2_lr3e-4_e{EPOCHS}",
    img_size=IMG_SIZE, p=16, k=2, lr=3e-4, epochs=EPOCHS, freeze_backbone=False,
    weight_decay=WEIGHT_DECAY, embedding_dim=EMBED_DIM,
)


def main():
    print(f"Device: {DEVICE}  Extended run: {CFG.epochs} epochs @ {CFG.img_size}px, "
          f"embedding_dim={CFG.embedding_dim}, weight_decay={CFG.weight_decay}", flush=True)
    tiger_ids, images_by_tiger = list_dataset()
    class_to_idx = {tid: i for i, tid in enumerate(tiger_ids)}
    train_items, val_items = split_train_val(images_by_tiger)
    print(f"Train: {len(train_items)}  Val: {len(val_items)}", flush=True)

    best_p1, ckpt_path = run_metric_config(CFG, tiger_ids, class_to_idx, train_items, val_items)
    print(f"\nExtended run finished. best val P@1={best_p1:.4f}  checkpoint={ckpt_path}", flush=True)

    prior_best_p1 = 0.0
    if os.path.exists(SWEEP_RESULTS_PATH):
        with open(SWEEP_RESULTS_PATH, "r", encoding="utf-8") as f:
            sweep = json.load(f)
        prior_best_p1 = max((m["val_precision_at_1"] for m in sweep.get("results", {}).get("metric", [])), default=0.0)

    print(f"Prior sweep best val P@1={prior_best_p1:.4f}  this run={best_p1:.4f}", flush=True)
    if best_p1 <= prior_best_p1:
        print("This run did NOT beat the prior best - NOT overwriting the production checkpoint/gallery.", flush=True)
        return

    final_metric_path = os.path.join(CHECKPOINTS_DIR, "convnext_metric_best.pth")
    torch.save(torch.load(ckpt_path, map_location=DEVICE, weights_only=True), final_metric_path)
    print(f"New best - promoted {ckpt_path} -> {final_metric_path}", flush=True)

    build_gallery(tiger_ids, class_to_idx, train_items + val_items, final_metric_path, CFG.img_size, CFG.embedding_dim)

    if os.path.exists(SWEEP_RESULTS_PATH):
        with open(SWEEP_RESULTS_PATH, "r", encoding="utf-8") as f:
            sweep = json.load(f)
    else:
        sweep = {"results": {"representation": [], "metric": []}}
    sweep["results"]["metric"].append({
        "config": CFG.__dict__, "val_precision_at_1": best_p1, "checkpoint": ckpt_path,
    })
    sweep["best_metric"] = CFG.name
    with open(SWEEP_RESULTS_PATH, "w", encoding="utf-8") as f:
        json.dump(sweep, f, indent=2)
    print("Updated sweep_results.json", flush=True)


if __name__ == "__main__":
    main()
