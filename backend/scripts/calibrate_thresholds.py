"""
Calibrates the "confident match" auto-accept similarity threshold used by
the live app (REAL_AUTO_ACCEPT_SIMILARITY in backend/app/ml/reid_embedding.py)
against real held-out data, replacing the placeholder guess (0.60) that
predates any trained model.

Reuses the exact same held-out setup as evaluate_on_test_set.py: a gallery
built only from train_items, queried with val_items the model never
backpropagated on. For a sweep of candidate thresholds, reports:
  - Coverage: fraction of queries that would be auto-matched
  - Precision: of those auto-matched, fraction actually correct
  - False-ID Rate: 1 - precision (wrong tiger shown as "confident match")

Run with the venv that has torch installed:
    D:/tygris_venv/Scripts/python.exe -u backend/scripts/calibrate_thresholds.py
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
    list_dataset, split_train_val, TigerImageDataset,
)

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
CHECKPOINT = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "convnext_metric_best.pth")
IMG_SIZE = 160

# Target false-ID rate we want the auto-accept threshold to guarantee.
TARGET_FALSE_ID_RATE = 0.10  # accept at most ~10% wrong among auto-matches
# Below this similarity, treat as "no real match" -> reject as unknown.
# Chosen as the point below which almost no correct match occurs (see sweep).


def embed_all(model, items, class_to_idx, transform):
    ds = TigerImageDataset(items, class_to_idx, transform, img_size=IMG_SIZE)
    loader = DataLoader(ds, batch_size=32, shuffle=False, num_workers=0)
    embs, tids = [], []
    with torch.no_grad():
        for x, y, p, t in loader:
            x = x.to(DEVICE)
            e = model.extract_normalized_embeddings(x).cpu().numpy()
            embs.append(e)
            tids.extend(t)
    return np.concatenate(embs, axis=0), tids


def main():
    print(f"Device: {DEVICE}", flush=True)
    tiger_ids, images_by_tiger = list_dataset()
    class_to_idx = {tid: i for i, tid in enumerate(tiger_ids)}
    train_items, val_items = split_train_val(images_by_tiger)
    print(f"Gallery (train-only): {len(train_items)}  Test queries (val): {len(val_items)}", flush=True)

    model = get_metric_model(name="ConvNeXt-small", embedding_dim=64, pretrained=False)
    model.load_state_dict(torch.load(CHECKPOINT, map_location=DEVICE, weights_only=True))
    model.to(DEVICE).eval()
    transform = get_paper_reid_transforms((IMG_SIZE, IMG_SIZE), is_training=False)

    t0 = time.time()
    gallery_emb, gallery_tids = embed_all(model, train_items, class_to_idx, transform)
    query_emb, query_tids = embed_all(model, val_items, class_to_idx, transform)
    print(f"Embedded gallery+queries in {time.time()-t0:.0f}s", flush=True)

    sims_all = query_emb @ gallery_emb.T
    top1_sims, top1_correct = [], []
    for i, true_tid in enumerate(query_tids):
        sims = sims_all[i]
        best_per_tiger = {}
        for tid, sim in zip(gallery_tids, sims):
            if tid not in best_per_tiger or sim > best_per_tiger[tid]:
                best_per_tiger[tid] = float(sim)
        top1_tid, top1_sim = max(best_per_tiger.items(), key=lambda kv: kv[1])
        top1_sims.append(top1_sim)
        top1_correct.append(top1_tid == true_tid)

    top1_sims = np.array(top1_sims)
    top1_correct = np.array(top1_correct)
    n = len(query_tids)

    print("\n" + "=" * 78)
    print(f"{'Threshold':>10} {'Coverage':>10} {'AutoMatched':>12} {'Correct':>9} {'Precision':>10} {'FalseIDRate':>12}")
    print("=" * 78)

    sweep = [round(x, 2) for x in np.arange(0.30, 0.96, 0.02)]
    results = []
    chosen = None
    for t in sweep:
        mask = top1_sims >= t
        matched = int(mask.sum())
        correct = int(top1_correct[mask].sum()) if matched else 0
        precision = correct / matched if matched else float("nan")
        false_id_rate = 1 - precision if matched else float("nan")
        coverage = matched / n
        results.append({
            "threshold": t, "coverage": coverage, "auto_matched": matched,
            "correct": correct, "precision": precision, "false_id_rate": false_id_rate,
        })
        marker = ""
        if matched and false_id_rate <= TARGET_FALSE_ID_RATE and chosen is None:
            chosen = t
            marker = "  <- meets target"
        print(f"{t:>10.2f} {coverage:>9.1%} {matched:>12} {correct:>9} "
              f"{precision if matched else 0:>9.1%} {false_id_rate if matched else 0:>11.1%}{marker}")

    print("=" * 78)

    if chosen is None:
        print(f"\nNo threshold in the sweep achieves a false-ID rate <= {TARGET_FALSE_ID_RATE:.0%}.")
        print("Using the highest threshold tested as the most conservative fallback.")
        chosen = sweep[-1]

    chosen_row = next(r for r in results if r["threshold"] == chosen)
    print(f"\nRECOMMENDED auto-accept threshold: {chosen}")
    print(f"  Coverage (queries auto-matched): {chosen_row['coverage']:.1%}")
    print(f"  Precision among auto-matched: {chosen_row['precision']:.1%}")
    print(f"  False-ID Rate: {chosen_row['false_id_rate']:.1%}")

    # Review floor: lowest threshold where at least some correct matches
    # still occur - below this, it's essentially never right, so reject
    # outright as unknown rather than asking a human to review noise.
    review_floor = None
    for r in sorted(results, key=lambda r: r["threshold"]):
        if r["auto_matched"] > 0 and r["correct"] > 0:
            review_floor = r["threshold"]
            break
    if review_floor is None:
        review_floor = sweep[0]
    print(f"\nRECOMMENDED review floor (below = reject as unknown): {review_floor}")

    out_path = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "threshold_calibration.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "target_false_id_rate": TARGET_FALSE_ID_RATE,
            "recommended_auto_accept_threshold": chosen,
            "recommended_review_floor": review_floor,
            "sweep": results,
        }, f, indent=2)
    print(f"\nSaved full sweep -> {out_path}")


if __name__ == "__main__":
    main()
