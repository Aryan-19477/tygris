"""
Trains the representation (closed-set classifier) and metric-learning (64-D
embedding) branches of UnifiedTigerReIDEngine on the real Pench dataset
(Dataset/PTR_Tiger_IDs_2025/*/: one folder per real tiger identity, real
camera-trap photos). Neither backend/app/ml/representation/trainer.py nor
metric_learning/trainer.py contain an actual training loop (only metrics
calculators), so this script provides the missing loop.

Runs a real hyperparameter sweep per branch (input resolution, batch size,
learning rate, frozen-vs-unfrozen backbone) rather than one fixed config -
a benchmark on this machine (CPU-only torch build, no CUDA wheel fit in the
available disk space) showed resolution alone is a ~5x cost lever
(10.6 min/epoch at 224px vs 2.2 min/epoch at 128px on the full ~1700-image
train split), so sweeping it is both a real accuracy/speed tradeoff
exploration and what keeps this feasible on CPU at all. The single best
checkpoint across all configs (by held-out validation metric) is saved as
the production convnext_{representation,metric}_best.pth; every config's
result is recorded in backend/checkpoints/sweep_results.json.

Run with the venv that has torch installed:
    backend/.venv312/Scripts/python.exe -u backend/scripts/train_reid_models.py
"""

import os
import sys
import json
import random
import time
from dataclasses import dataclass, asdict
from typing import List, Tuple, Dict, Optional

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from PIL import Image

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.ml.representation.models import get_representation_model
from backend.app.ml.representation.augmentations import get_paper_reid_transforms
from backend.app.ml.representation.trainer import RepresentationMetricsCalculator
from backend.app.ml.metric_learning.models import get_metric_model
from backend.app.ml.metric_learning.losses import MultiSimilarityLoss
from backend.app.ml.metric_learning.trainer import MetricRetrievalEvaluator
from backend.app.ml.fusion.gallery import TigerGallery, GalleryEntry

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

DATASET_DIR = os.path.join(PROJECT_ROOT, "Dataset", "PTR_Tiger_IDs_2025", "PTR_Tiger_IDs_2025")
CHECKPOINTS_DIR = os.path.join(PROJECT_ROOT, "backend", "checkpoints")
GALLERY_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gallery", "trained_gallery.json")
CLASS_LIST_PATH = os.path.join(CHECKPOINTS_DIR, "tiger_classes.json")
SWEEP_RESULTS_PATH = os.path.join(CHECKPOINTS_DIR, "sweep_results.json")

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
SMOKE_TEST = os.environ.get("SMOKE_TEST") == "1"


@dataclass
class RepConfig:
    name: str
    img_size: int
    batch_size: int
    lr: float
    epochs: int
    freeze_backbone: bool
    weight_decay: float = 1e-4


@dataclass
class MetricConfig:
    name: str
    img_size: int
    p: int  # identities per batch
    k: int  # images per identity per batch
    lr: float
    epochs: int
    freeze_backbone: bool
    weight_decay: float = 1e-4
    embedding_dim: int = 64


REP_CONFIGS: List[RepConfig] = [
    RepConfig(name="rep_160_unfrozen_lr1e-4", img_size=160, batch_size=16, lr=1e-4, epochs=6, freeze_backbone=False),
    RepConfig(name="rep_160_unfrozen_lr3e-4_bs32", img_size=160, batch_size=32, lr=3e-4, epochs=6, freeze_backbone=False),
    RepConfig(name="rep_128_frozen_fast", img_size=128, batch_size=32, lr=1e-3, epochs=8, freeze_backbone=True),
]

METRIC_CONFIGS: List[MetricConfig] = [
    MetricConfig(name="metric_160_unfrozen_p8k2", img_size=160, p=8, k=2, lr=1e-4, epochs=6, freeze_backbone=False),
    MetricConfig(name="metric_160_unfrozen_p16k2_lr3e-4", img_size=160, p=16, k=2, lr=3e-4, epochs=6, freeze_backbone=False),
    MetricConfig(name="metric_128_frozen_p8k4_fast", img_size=128, p=8, k=4, lr=1e-3, epochs=8, freeze_backbone=True),
]

if SMOKE_TEST:
    for c in REP_CONFIGS + METRIC_CONFIGS:
        c.epochs = 1


def list_dataset() -> Tuple[List[str], Dict[str, List[str]]]:
    tiger_ids = sorted([
        d for d in os.listdir(DATASET_DIR)
        if os.path.isdir(os.path.join(DATASET_DIR, d))
    ])
    images_by_tiger = {}
    for tid in tiger_ids:
        folder = os.path.join(DATASET_DIR, tid)
        files = sorted([
            os.path.join(folder, f) for f in os.listdir(folder)
            if f.lower().endswith((".jpg", ".jpeg", ".png"))
        ])
        images_by_tiger[tid] = files
    return tiger_ids, images_by_tiger


def split_train_val(images_by_tiger: Dict[str, List[str]], val_frac: float = 0.2):
    train_items, val_items = [], []
    rng = random.Random(SEED)
    for tid, files in images_by_tiger.items():
        shuffled = files[:]
        rng.shuffle(shuffled)
        if len(shuffled) >= 4:
            n_val = max(1, int(round(len(shuffled) * val_frac)))
            val_items += [(f, tid) for f in shuffled[:n_val]]
            train_items += [(f, tid) for f in shuffled[n_val:]]
        else:
            train_items += [(f, tid) for f in shuffled]
    return train_items, val_items


class TigerImageDataset(Dataset):
    def __init__(self, items: List[Tuple[str, str]], class_to_idx: Dict[str, int], transform, img_size: int = 160):
        self.items = items
        self.class_to_idx = class_to_idx
        self.transform = transform
        self.img_size = img_size

    def __len__(self):
        return len(self.items)

    def __getitem__(self, idx):
        path, tid = self.items[idx]
        try:
            img = Image.open(path).convert("RGB")
        except Exception:
            img = Image.new("RGB", (self.img_size, self.img_size), (0, 0, 0))
        tensor = self.transform(img)
        return tensor, self.class_to_idx[tid], path, tid


class PKBatchSampler(torch.utils.data.Sampler):
    """Samples P identities x K images each per batch, so every batch has
    guaranteed positive pairs for MultiSimilarityLoss - plain random
    shuffling over 62 sparsely-populated classes usually would not."""

    def __init__(self, items: List[Tuple[str, str]], p: int, k: int, num_batches: int):
        self.p, self.k, self.num_batches = p, k, num_batches
        self.by_class: Dict[str, List[int]] = {}
        for i, (_, tid) in enumerate(items):
            self.by_class.setdefault(tid, []).append(i)
        self.eligible = [c for c, idxs in self.by_class.items() if len(idxs) >= 2]

    def __iter__(self):
        rng = random.Random()
        for _ in range(self.num_batches):
            classes = rng.sample(self.eligible, min(self.p, len(self.eligible)))
            batch = []
            for c in classes:
                idxs = self.by_class[c]
                chosen = rng.sample(idxs, min(self.k, len(idxs)))
                while len(chosen) < self.k:
                    chosen.append(rng.choice(idxs))
                batch += chosen
            yield batch

    def __len__(self):
        return self.num_batches


def run_rep_config(cfg: RepConfig, tiger_ids, class_to_idx, train_items, val_items) -> Tuple[float, str]:
    print(f"\n--- [rep:{cfg.name}] {asdict(cfg)} ---", flush=True)
    size = (cfg.img_size, cfg.img_size)
    train_tf = get_paper_reid_transforms(size, is_training=True)
    val_tf = get_paper_reid_transforms(size, is_training=False)

    train_ds = TigerImageDataset(train_items, class_to_idx, train_tf, img_size=cfg.img_size)
    val_ds = TigerImageDataset(val_items, class_to_idx, val_tf, img_size=cfg.img_size)
    train_loader = DataLoader(train_ds, batch_size=cfg.batch_size, shuffle=True, num_workers=0)
    val_loader = DataLoader(val_ds, batch_size=cfg.batch_size, shuffle=False, num_workers=0)

    model = get_representation_model(
        num_classes=len(tiger_ids), name="ConvNeXt-small", pretrained=True, freeze_backbone=cfg.freeze_backbone
    )
    model.to(DEVICE)

    criterion = nn.CrossEntropyLoss(label_smoothing=0.1)
    trainable = [p for p in model.parameters() if p.requires_grad]
    optimizer = torch.optim.AdamW(trainable, lr=cfg.lr, weight_decay=cfg.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=cfg.epochs)

    best_top1 = -1.0
    ckpt_path = os.path.join(CHECKPOINTS_DIR, f"rep_{cfg.name}.pth")

    for epoch in range(cfg.epochs):
        model.train()
        t0 = time.time()
        running_loss = 0.0
        for x, y, _, _ in train_loader:
            x, y = x.to(DEVICE), y.to(DEVICE)
            optimizer.zero_grad()
            logits = model(x)
            loss = criterion(logits, y)
            loss.backward()
            optimizer.step()
            running_loss += loss.item() * x.size(0)
        scheduler.step()
        train_loss = running_loss / max(1, len(train_ds))

        model.eval()
        calc = RepresentationMetricsCalculator(num_classes=len(tiger_ids))
        with torch.no_grad():
            for x, y, _, _ in val_loader:
                x, y = x.to(DEVICE), y.to(DEVICE)
                calc.update(model(x), y)
        metrics = calc.compute() if len(val_ds) > 0 else {"Top-1": float("nan")}
        top1 = metrics.get("Top-1", float("nan"))
        dt = time.time() - t0
        print(f"[rep:{cfg.name}] epoch {epoch+1}/{cfg.epochs} loss={train_loss:.4f} val_top1={top1:.4f} ({dt:.0f}s)", flush=True)

        if not np.isnan(top1) and top1 >= best_top1:
            best_top1 = top1
            torch.save(model.state_dict(), ckpt_path)

    print(f"[rep:{cfg.name}] done. best val top1={max(best_top1, 0):.4f}", flush=True)
    return max(best_top1, 0.0), ckpt_path


def run_metric_config(cfg: MetricConfig, tiger_ids, class_to_idx, train_items, val_items) -> Tuple[float, str]:
    print(f"\n--- [metric:{cfg.name}] {asdict(cfg)} ---", flush=True)
    size = (cfg.img_size, cfg.img_size)
    train_tf = get_paper_reid_transforms(size, is_training=True)
    val_tf = get_paper_reid_transforms(size, is_training=False)

    train_ds = TigerImageDataset(train_items, class_to_idx, train_tf, img_size=cfg.img_size)
    val_ds = TigerImageDataset(val_items, class_to_idx, val_tf, img_size=cfg.img_size)

    batch_size = cfg.p * cfg.k
    num_batches_per_epoch = max(1, len(train_ds) // batch_size)
    sampler = PKBatchSampler(train_items, p=cfg.p, k=cfg.k, num_batches=num_batches_per_epoch)
    train_loader = DataLoader(train_ds, batch_sampler=sampler, num_workers=0)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False, num_workers=0)

    model = get_metric_model(
        name="ConvNeXt-small", embedding_dim=cfg.embedding_dim, pretrained=True, freeze_backbone=cfg.freeze_backbone
    )
    model.to(DEVICE)

    criterion = MultiSimilarityLoss()
    trainable = [p for p in model.parameters() if p.requires_grad]
    optimizer = torch.optim.AdamW(trainable, lr=cfg.lr, weight_decay=cfg.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=cfg.epochs)
    evaluator = MetricRetrievalEvaluator(k=7)

    best_p1 = -1.0
    ckpt_path = os.path.join(CHECKPOINTS_DIR, f"metric_{cfg.name}.pth")

    for epoch in range(cfg.epochs):
        model.train()
        t0 = time.time()
        running_loss, n_batches = 0.0, 0
        for x, y, _, _ in train_loader:
            x, y = x.to(DEVICE), y.to(DEVICE)
            optimizer.zero_grad()
            emb = model.extract_normalized_embeddings(x)
            loss = criterion(emb, y)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
            n_batches += 1
        scheduler.step()
        train_loss = running_loss / max(1, n_batches)

        model.eval()
        all_emb, all_lbl = [], []
        with torch.no_grad():
            for x, y, _, _ in val_loader:
                x = x.to(DEVICE)
                emb = model.extract_normalized_embeddings(x).cpu().numpy()
                all_emb.append(emb)
                all_lbl.append(y.numpy())
        dt = time.time() - t0
        if all_emb:
            all_emb = np.concatenate(all_emb, axis=0)
            all_lbl = np.concatenate(all_lbl, axis=0)
            p1 = evaluator.evaluate(all_emb, all_lbl).get("Precision@1", 0.0)
        else:
            p1 = 0.0
        print(f"[metric:{cfg.name}] epoch {epoch+1}/{cfg.epochs} loss={train_loss:.4f} val_P@1={p1:.4f} ({dt:.0f}s)", flush=True)

        if p1 >= best_p1:
            best_p1 = p1
            torch.save(model.state_dict(), ckpt_path)

    print(f"[metric:{cfg.name}] done. best val P@1={max(best_p1, 0):.4f}", flush=True)
    return max(best_p1, 0.0), ckpt_path


def build_gallery(tiger_ids, class_to_idx, all_items, metric_ckpt_path: str, img_size: int, embedding_dim: int = 64):
    print("\n=== Building reference gallery from best metric model ===", flush=True)
    model = get_metric_model(name="ConvNeXt-small", embedding_dim=embedding_dim, pretrained=False)
    model.load_state_dict(torch.load(metric_ckpt_path, map_location=DEVICE, weights_only=True))
    model.to(DEVICE).eval()

    val_tf = get_paper_reid_transforms((img_size, img_size), is_training=False)
    ds = TigerImageDataset(all_items, class_to_idx, val_tf, img_size=img_size)
    loader = DataLoader(ds, batch_size=32, shuffle=False, num_workers=0)

    gallery = TigerGallery(embedding_dim=embedding_dim)
    with torch.no_grad():
        for x, y, paths, tids in loader:
            x = x.to(DEVICE)
            emb = model.extract_normalized_embeddings(x).cpu().numpy()
            for vec, path, tid in zip(emb, paths, tids):
                entry = GalleryEntry(
                    entry_id=f"{tid}_{os.path.basename(path)}",
                    embedding=vec,
                    tiger_id=tid,
                    side="Unknown",
                    camera_id="",
                    video_id="",
                    timestamp="",
                    source_path=path,
                    extra_metadata={"source": "real_pench_dataset"},
                )
                gallery.add_entry(entry)

    gallery.save(GALLERY_PATH)
    print(f"[gallery] wrote {len(gallery.entries)} real reference embeddings for {len(tiger_ids)} tigers -> {GALLERY_PATH}", flush=True)


def main():
    print(f"Device: {DEVICE}  SMOKE_TEST={SMOKE_TEST}", flush=True)
    tiger_ids, images_by_tiger = list_dataset()
    class_to_idx = {tid: i for i, tid in enumerate(tiger_ids)}
    total = sum(len(v) for v in images_by_tiger.values())
    print(f"Found {len(tiger_ids)} real tigers, {total} real images in {DATASET_DIR}", flush=True)

    train_items, val_items = split_train_val(images_by_tiger)
    if SMOKE_TEST:
        train_items, val_items = train_items[:64], val_items[:32]
    print(f"Train: {len(train_items)}  Val: {len(val_items)}", flush=True)

    os.makedirs(CHECKPOINTS_DIR, exist_ok=True)
    with open(CLASS_LIST_PATH, "w", encoding="utf-8") as f:
        json.dump({"tiger_ids": tiger_ids, "class_to_idx": class_to_idx}, f, indent=2)

    results = {"representation": [], "metric": []}

    print(f"\n===== REPRESENTATION SWEEP ({len(REP_CONFIGS)} configs) =====", flush=True)
    best_rep = (-1.0, None, None)
    for cfg in REP_CONFIGS:
        score, ckpt = run_rep_config(cfg, tiger_ids, class_to_idx, train_items, val_items)
        results["representation"].append({"config": asdict(cfg), "val_top1": score, "checkpoint": ckpt})
        if score > best_rep[0]:
            best_rep = (score, ckpt, cfg.name)
    print(f"\nBest representation config: {best_rep[2]} (val_top1={best_rep[0]:.4f})", flush=True)
    if best_rep[1]:
        final_rep_path = os.path.join(CHECKPOINTS_DIR, "convnext_representation_best.pth")
        torch.save(torch.load(best_rep[1], map_location=DEVICE, weights_only=True), final_rep_path)

    print(f"\n===== METRIC LEARNING SWEEP ({len(METRIC_CONFIGS)} configs) =====", flush=True)
    best_metric = (-1.0, None, None, 160)
    for cfg in METRIC_CONFIGS:
        score, ckpt = run_metric_config(cfg, tiger_ids, class_to_idx, train_items, val_items)
        results["metric"].append({"config": asdict(cfg), "val_precision_at_1": score, "checkpoint": ckpt})
        if score > best_metric[0]:
            best_metric = (score, ckpt, cfg.name, cfg.img_size)
    print(f"\nBest metric config: {best_metric[2]} (val_P@1={best_metric[0]:.4f})", flush=True)
    final_metric_path = os.path.join(CHECKPOINTS_DIR, "convnext_metric_best.pth")
    if best_metric[1]:
        torch.save(torch.load(best_metric[1], map_location=DEVICE, weights_only=True), final_metric_path)

    with open(SWEEP_RESULTS_PATH, "w", encoding="utf-8") as f:
        json.dump({
            "results": results,
            "best_representation": best_rep[2],
            "best_metric": best_metric[2],
        }, f, indent=2)

    build_gallery(tiger_ids, class_to_idx, train_items + val_items, final_metric_path, best_metric[3])

    print("\nAll done. Best checkpoints in backend/checkpoints/, sweep_results.json has every config's metrics.", flush=True)


if __name__ == "__main__":
    main()
