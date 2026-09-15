"""
Held-out evaluation of the trained re-ID model against real test queries.

The production gallery (backend/data/gallery/trained_gallery.json) is built
from ALL images (train + val), so it can't be used to fairly measure
accuracy - every image already sits in it. This script instead:

  1. Reproduces the exact same train/val split train_reid_models.py used
     (same seed, same split_train_val), so val_items were never touched by
     backprop.
  2. Builds a *temporary* gallery from train_items only.
  3. Treats each val_item as an incoming test photo: embeds it with the
     frozen best metric checkpoint, searches the train-only gallery, and
     checks whether the top-1 (and top-5) match is the correct tiger.
  4. Also reports what the app's live decision thresholds
     (REAL_AUTO_ACCEPT_SIMILARITY / REAL_REVIEW_FLOOR_SIMILARITY in
     reid_embedding.py) would have done with these same queries -
     auto-match rate, and how many of those auto-matches were wrong
     (False-ID Rate), since that's what actually reaches the UI.

Run with the venv that has torch installed:
    D:/tygris_venv/Scripts/python.exe -u backend/scripts/evaluate_on_test_set.py
"""

import os
import sys
import json
import random
import time

import numpy as np
import torch
from torch.utils.data import DataLoader

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.ml.metric_learning.models import get_metric_model
from backend.app.ml.representation.augmentations import get_paper_reid_transforms
from backend.scripts.train_reid_models import (
    list_dataset, split_train_val, TigerImageDataset, DATASET_DIR,
)

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
CHECKPOINT = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "convnext_metric_best.pth")
IMG_SIZE = 192

# Same thresholds the live app uses (backend/app/ml/reid_embedding.py)
REAL_AUTO_ACCEPT_SIMILARITY = 0.60
REAL_REVIEW_FLOOR_SIMILARITY = 0.40


def embed_all(model, items, class_to_idx, transform):
    ds = TigerImageDataset(items, class_to_idx, transform, img_size=IMG_SIZE)
    loader = DataLoader(ds, batch_size=32, shuffle=False, num_workers=0)
    embs, tids, paths = [], [], []
    with torch.no_grad():
        for x, y, p, t in loader:
            x = x.to(DEVICE)
            e = model.extract_normalized_embeddings(x).cpu().numpy()
            embs.append(e)
            tids.extend(t)
            paths.extend(p)
    return np.concatenate(embs, axis=0), tids, paths


def main():
    print(f"Device: {DEVICE}", flush=True)
    tiger_ids, images_by_tiger = list_dataset()
    class_to_idx = {tid: i for i, tid in enumerate(tiger_ids)}
    train_items, val_items = split_train_val(images_by_tiger)
    print(f"Gallery (train-only) images: {len(train_items)}  Test queries (val): {len(val_items)}", flush=True)

    model = get_metric_model(name="ConvNeXt-small", embedding_dim=128, pretrained=False)
    model.load_state_dict(torch.load(CHECKPOINT, map_location=DEVICE, weights_only=True))
    model.to(DEVICE).eval()

    transform = get_paper_reid_transforms((IMG_SIZE, IMG_SIZE), is_training=False)

    print("\nEmbedding train-only gallery...", flush=True)
    t0 = time.time()
    gallery_emb, gallery_tids, _ = embed_all(model, train_items, class_to_idx, transform)
    print(f"  {len(gallery_tids)} embeddings in {time.time()-t0:.0f}s", flush=True)

    print("Embedding held-out test queries...", flush=True)
    t0 = time.time()
    query_emb, query_tids, query_paths = embed_all(model, val_items, class_to_idx, transform)
    print(f"  {len(query_tids)} embeddings in {time.time()-t0:.0f}s", flush=True)

    # Dedupe gallery to best-per-tiger similarity per query, same as the live engine
    sims_all = query_emb @ gallery_emb.T  # (n_query, n_gallery)

    top1_correct = 0
    top5_correct = 0
    auto_matched = 0
    auto_correct = 0
    needs_review = 0
    unknown_rejected = 0
    per_tiger_correct = {}
    per_tiger_total = {}
    confusions = []

    for i, true_tid in enumerate(query_tids):
        sims = sims_all[i]
        best_per_tiger = {}
        for tid, sim in zip(gallery_tids, sims):
            if tid not in best_per_tiger or sim > best_per_tiger[tid]:
                best_per_tiger[tid] = float(sim)
        ranked = sorted(best_per_tiger.items(), key=lambda kv: -kv[1])
        top1_tid, top1_sim = ranked[0]
        top5_tids = [t for t, _ in ranked[:5]]

        per_tiger_total[true_tid] = per_tiger_total.get(true_tid, 0) + 1
        if top1_tid == true_tid:
            top1_correct += 1
            per_tiger_correct[true_tid] = per_tiger_correct.get(true_tid, 0) + 1
        else:
            confusions.append((true_tid, top1_tid, round(top1_sim, 4)))
        if true_tid in top5_tids:
            top5_correct += 1

        if top1_sim >= REAL_AUTO_ACCEPT_SIMILARITY:
            auto_matched += 1
            if top1_tid == true_tid:
                auto_correct += 1
        elif top1_sim >= REAL_REVIEW_FLOOR_SIMILARITY:
            needs_review += 1
        else:
            unknown_rejected += 1

    n = len(query_tids)
    print("\n" + "=" * 60)
    print("RETRIEVAL ACCURACY (query vs train-only gallery)")
    print("=" * 60)
    print(f"Test queries: {n}")
    print(f"Top-1 accuracy: {top1_correct}/{n} = {top1_correct/n:.4f}")
    print(f"Top-5 accuracy: {top5_correct}/{n} = {top5_correct/n:.4f}")

    print("\n" + "=" * 60)
    print("LIVE-APP DECISION SIMULATION (thresholds from reid_embedding.py)")
    print(f"auto_accept >= {REAL_AUTO_ACCEPT_SIMILARITY}, review_floor >= {REAL_REVIEW_FLOOR_SIMILARITY}")
    print("=" * 60)
    print(f"Auto-matched: {auto_matched}/{n} = {auto_matched/n:.4f}")
    if auto_matched:
        false_id_rate = 1 - auto_correct / auto_matched
        print(f"  Of those, CORRECT: {auto_correct}/{auto_matched} = {auto_correct/auto_matched:.4f}")
        print(f"  False-ID Rate (wrong tiger labeled 'confident match'): {false_id_rate:.4f}")
    print(f"Needs review (ambiguous): {needs_review}/{n} = {needs_review/n:.4f}")
    print(f"Rejected as unknown/low-sim: {unknown_rejected}/{n} = {unknown_rejected/n:.4f}")

    print("\n" + "=" * 60)
    print("WORST 10 CONFUSIONS (true -> predicted, similarity)")
    print("=" * 60)
    for true_tid, pred_tid, sim in sorted(confusions, key=lambda c: -c[2])[:10]:
        print(f"  {true_tid} -> {pred_tid}  (sim={sim})")

    per_tiger_acc = {
        tid: round(per_tiger_correct.get(tid, 0) / total, 3)
        for tid, total in per_tiger_total.items()
    }
    worst_tigers = sorted(per_tiger_acc.items(), key=lambda kv: kv[1])[:10]
    print("\n" + "=" * 60)
    print("10 WORST-PERFORMING TIGERS (top-1 acc, min 1 test image)")
    print("=" * 60)
    for tid, acc in worst_tigers:
        print(f"  {tid}: {acc:.3f}  ({per_tiger_correct.get(tid,0)}/{per_tiger_total[tid]})")

    out_path = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "test_set_evaluation.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "test_queries": n,
            "gallery_size": len(gallery_tids),
            "top1_accuracy": top1_correct / n,
            "top5_accuracy": top5_correct / n,
            "auto_accept_threshold": REAL_AUTO_ACCEPT_SIMILARITY,
            "review_floor_threshold": REAL_REVIEW_FLOOR_SIMILARITY,
            "auto_matched_rate": auto_matched / n,
            "auto_matched_correct_rate": (auto_correct / auto_matched) if auto_matched else None,
            "false_id_rate": (1 - auto_correct / auto_matched) if auto_matched else None,
            "needs_review_rate": needs_review / n,
            "rejected_rate": unknown_rejected / n,
            "per_tiger_top1_accuracy": per_tiger_acc,
        }, f, indent=2)
    print(f"\nSaved full results -> {out_path}")


if __name__ == "__main__":
    main()
