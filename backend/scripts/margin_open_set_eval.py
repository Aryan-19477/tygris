"""
Fast alternative to retraining: tests whether a MARGIN-based decision rule
(top1_similarity - top2_similarity, i.e. how much the best match beats the
second-best) separates known vs unknown tigers better than raw top1
similarity alone (the current app logic).

Intuition: a genuine known tiger should have one clear best match in the
gallery. An unknown/fake image tends to score similarly against several
different tigers - no strong single "winner" - even when the absolute
scores are all high (which is what let the AI-generated image through
at 70% similarity in the raw-similarity approach).

No retraining - reuses the same checkpoint and the same known/unknown
holdout setup as open_set_eval.py, just computes one extra number and
compares both decision rules head-to-head.

Run with the venv that has torch installed:
    D:/tygris_venv/Scripts/python.exe -u backend/scripts/margin_open_set_eval.py
"""

import os
import sys
import json
import random

import numpy as np
import torch
from torch.utils.data import DataLoader

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from backend.app.ml.metric_learning.models import get_metric_model
from backend.app.ml.representation.augmentations import get_paper_reid_transforms
from backend.scripts.train_reid_models import list_dataset, split_train_val, TigerImageDataset

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
CHECKPOINT = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "convnext_metric_best.pth")
IMG_SIZE = 192
N_HOLDOUT_IDENTITIES = 10


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


def top1_top2(sims, gallery_tids):
    best = {}
    for tid, sim in zip(gallery_tids, sims):
        if tid not in best or sim > best[tid]:
            best[tid] = float(sim)
    ranked = sorted(best.values(), reverse=True)
    top1 = ranked[0] if ranked else 0.0
    top2 = ranked[1] if len(ranked) > 1 else 0.0
    return top1, top2


def main():
    print(f"Device: {DEVICE}", flush=True)
    tiger_ids, images_by_tiger = list_dataset()
    rng = random.Random(SEED + 1)
    holdout_ids = set(rng.sample(tiger_ids, N_HOLDOUT_IDENTITIES))
    known_ids = [t for t in tiger_ids if t not in holdout_ids]

    known_images = {t: v for t, v in images_by_tiger.items() if t in known_ids}
    class_to_idx = {tid: i for i, tid in enumerate(known_ids)}
    train_items, val_items = split_train_val(known_images)
    unknown_items = []
    for t in holdout_ids:
        unknown_items += [(f, t) for f in images_by_tiger[t]]

    model = get_metric_model(name="ConvNeXt-small", embedding_dim=128, pretrained=False)
    model.load_state_dict(torch.load(CHECKPOINT, map_location=DEVICE, weights_only=True))
    model.to(DEVICE).eval()
    transform = get_paper_reid_transforms((IMG_SIZE, IMG_SIZE), is_training=False)

    gallery_emb, gallery_tids = embed_all(model, train_items, class_to_idx, transform)
    unk_class_to_idx = {t: 0 for t in holdout_ids}
    known_query_emb, known_query_tids = embed_all(model, val_items, class_to_idx, transform)
    unknown_query_emb, unknown_query_tids = embed_all(model, unknown_items, unk_class_to_idx, transform)

    known_sims_all = known_query_emb @ gallery_emb.T
    unknown_sims_all = unknown_query_emb @ gallery_emb.T

    known_top1, known_top2, known_margin = [], [], []
    for i in range(len(known_query_tids)):
        t1, t2 = top1_top2(known_sims_all[i], gallery_tids)
        known_top1.append(t1); known_top2.append(t2); known_margin.append(t1 - t2)

    unknown_top1, unknown_top2, unknown_margin = [], [], []
    for i in range(len(unknown_query_tids)):
        t1, t2 = top1_top2(unknown_sims_all[i], gallery_tids)
        unknown_top1.append(t1); unknown_top2.append(t2); unknown_margin.append(t1 - t2)

    known_margin = np.array(known_margin)
    unknown_margin = np.array(unknown_margin)
    known_top1 = np.array(known_top1)
    unknown_top1 = np.array(unknown_top1)

    print(f"\nKnown-query margin (top1-top2):   mean={known_margin.mean():.4f} "
          f"min={known_margin.min():.4f} max={known_margin.max():.4f}", flush=True)
    print(f"Unknown-query margin (top1-top2): mean={unknown_margin.mean():.4f} "
          f"min={unknown_margin.min():.4f} max={unknown_margin.max():.4f}", flush=True)

    print("\n" + "=" * 90)
    print(f"{'MarginFloor':>12} {'KnownRecall':>12} {'UnknownFalseAcceptRate':>24}   vs raw-sim at same recall")
    print("=" * 90)
    sweep = [round(x, 3) for x in np.arange(0.00, 0.25, 0.01)]
    results = []
    for m in sweep:
        known_recall = float((known_margin >= m).mean())
        unknown_far = float((unknown_margin >= m).mean())
        results.append({"margin_floor": m, "known_recall": known_recall, "unknown_false_accept_rate": unknown_far})
        print(f"{m:>12.3f} {known_recall:>11.1%} {unknown_far:>23.1%}")
    print("=" * 90)

    # Best margin-only operating point at target known-recall ~ match raw-sim's 0.82 floor recall (67.9%)
    target_recall = 0.679
    closest = min(results, key=lambda r: abs(r["known_recall"] - target_recall))
    print(f"\nAt matched known-recall (~{closest['known_recall']:.1%}, margin_floor={closest['margin_floor']}):")
    print(f"  Unknown false-accept rate (margin rule): {closest['unknown_false_accept_rate']:.1%}")
    print("  (compare to raw-similarity rule at same recall: 12.1% false-accept, from open_set_eval.py)")

    # Combined rule: require BOTH sim>=0.60 (current auto-accept) AND margin>=some floor
    print("\n" + "=" * 90)
    print("COMBINED RULE: sim >= 0.60 AND margin >= X (no other changes to existing threshold)")
    print("=" * 90)
    for m in [0.02, 0.04, 0.06, 0.08, 0.10, 0.12]:
        k_mask = (known_top1 >= 0.60) & (known_margin >= m)
        u_mask = (unknown_top1 >= 0.60) & (unknown_margin >= m)
        print(f"  margin>={m:.2f}: known_recall={k_mask.mean():.1%}  unknown_false_accept={u_mask.mean():.1%}")

    out_path = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "margin_calibration.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "known_margin_stats": {"mean": float(known_margin.mean()), "min": float(known_margin.min()), "max": float(known_margin.max())},
            "unknown_margin_stats": {"mean": float(unknown_margin.mean()), "min": float(unknown_margin.min()), "max": float(unknown_margin.max())},
            "sweep": results,
        }, f, indent=2)
    print(f"\nSaved -> {out_path}")


if __name__ == "__main__":
    main()
