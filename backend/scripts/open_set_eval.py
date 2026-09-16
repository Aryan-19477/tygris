"""
Open-set (unknown-rejection) evaluation - distinct from the closed-set
top-1/top-5 accuracy measured by evaluate_on_test_set.py.

That evaluation only ever asked "of these 62 known tigers, which one is
this?" - it never tested whether the model can recognize a photo that
ISN'T any of them, which is exactly the failure a user found manually
(an AI-generated tiger image, never in the dataset, got matched as a
"70% similarity confident match" to a real enrolled tiger).

Simulates true unknowns without needing external images: holds several
real tiger identities OUT of the gallery entirely, then queries with
their photos. Since the model has zero gallery entries for them, the
only correct behavior is REJECTION (low similarity to everything) -
any high similarity score here is a false accept, exactly like the
AI-image case.

Sweeps review-floor thresholds to find one that actually separates:
  - known queries (real photos of gallery tigers) that SHOULD match
  - unknown queries (held-out tiger identities) that SHOULD be rejected

Run with the venv that has torch installed:
    D:/tygris_venv/Scripts/python.exe -u backend/scripts/open_set_eval.py
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
from backend.scripts.train_reid_models import (
    list_dataset, split_train_val, TigerImageDataset,
)

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
CHECKPOINT = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "convnext_metric_best.pth")
IMG_SIZE = 192
N_HOLDOUT_IDENTITIES = 10  # tigers removed entirely from the gallery to act as "unknowns"


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


def best_per_tiger_sim(sims, gallery_tids):
    best = {}
    for tid, sim in zip(gallery_tids, sims):
        if tid not in best or sim > best[tid]:
            best[tid] = float(sim)
    return max(best.values()) if best else 0.0


def main():
    print(f"Device: {DEVICE}", flush=True)
    tiger_ids, images_by_tiger = list_dataset()

    rng = random.Random(SEED + 1)
    holdout_ids = set(rng.sample(tiger_ids, N_HOLDOUT_IDENTITIES))
    known_ids = [t for t in tiger_ids if t not in holdout_ids]
    print(f"Held-out (simulated unknown) tigers: {sorted(holdout_ids)}", flush=True)

    known_images = {t: v for t, v in images_by_tiger.items() if t in known_ids}
    class_to_idx = {tid: i for i, tid in enumerate(known_ids)}
    train_items, val_items = split_train_val(known_images)

    unknown_items = []
    for t in holdout_ids:
        unknown_items += [(f, t) for f in images_by_tiger[t]]

    print(f"Gallery (train-only, known tigers): {len(train_items)}", flush=True)
    print(f"Known test queries (val, held-out from gallery but same identity known): {len(val_items)}", flush=True)
    print(f"Unknown test queries (entirely unseen identities): {len(unknown_items)}", flush=True)

    model = get_metric_model(name="ConvNeXt-small", embedding_dim=64, pretrained=False)
    model.load_state_dict(torch.load(CHECKPOINT, map_location=DEVICE, weights_only=True))
    model.to(DEVICE).eval()
    transform = get_paper_reid_transforms((IMG_SIZE, IMG_SIZE), is_training=False)

    gallery_emb, gallery_tids = embed_all(model, train_items, class_to_idx, transform)

    # dummy class_to_idx for unknown items - identity label unused for embedding
    unk_class_to_idx = {t: 0 for t in holdout_ids}
    known_query_emb, known_query_tids = embed_all(model, val_items, class_to_idx, transform)
    unknown_query_emb, unknown_query_tids = embed_all(model, unknown_items, unk_class_to_idx, transform)

    known_sims_all = known_query_emb @ gallery_emb.T
    unknown_sims_all = unknown_query_emb @ gallery_emb.T

    known_top1 = np.array([best_per_tiger_sim(known_sims_all[i], gallery_tids) for i in range(len(known_query_tids))])
    unknown_top1 = np.array([best_per_tiger_sim(unknown_sims_all[i], gallery_tids) for i in range(len(unknown_query_tids))])

    print("\nKnown-query top1 similarity: "
          f"mean={known_top1.mean():.3f} min={known_top1.min():.3f} max={known_top1.max():.3f}", flush=True)
    print("Unknown-query top1 similarity (should be LOW - these tigers aren't in the gallery at all): "
          f"mean={unknown_top1.mean():.3f} min={unknown_top1.min():.3f} max={unknown_top1.max():.3f}", flush=True)

    print("\n" + "=" * 80)
    print(f"{'ReviewFloor':>12} {'KnownRecall':>12} {'UnknownFalseAcceptRate':>24} {'Verdict':>10}")
    print("=" * 80)
    sweep = [round(x, 2) for x in np.arange(0.30, 0.96, 0.02)]
    results = []
    for t in sweep:
        known_recall = float((known_top1 >= t).mean())        # known queries correctly NOT rejected
        unknown_far = float((unknown_top1 >= t).mean())        # unknown queries WRONGLY accepted
        results.append({"threshold": t, "known_recall": known_recall, "unknown_false_accept_rate": unknown_far})
        print(f"{t:>12.2f} {known_recall:>11.1%} {unknown_far:>23.1%}")
    print("=" * 80)

    # Recommend: smallest threshold where unknown false-accept rate drops to <= 15%
    chosen = None
    for r in results:
        if r["unknown_false_accept_rate"] <= 0.15:
            chosen = r
            break
    if chosen is None:
        chosen = results[-1]

    print(f"\nRECOMMENDED review floor: {chosen['threshold']}")
    print(f"  Known-tiger recall at this floor (fraction NOT wrongly rejected): {chosen['known_recall']:.1%}")
    print(f"  Unknown false-accept rate at this floor: {chosen['unknown_false_accept_rate']:.1%}")

    out_path = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "open_set_calibration.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "holdout_identities": sorted(holdout_ids),
            "known_top1_stats": {"mean": float(known_top1.mean()), "min": float(known_top1.min()), "max": float(known_top1.max())},
            "unknown_top1_stats": {"mean": float(unknown_top1.mean()), "min": float(unknown_top1.min()), "max": float(unknown_top1.max())},
            "recommended_review_floor": chosen["threshold"],
            "sweep": results,
        }, f, indent=2)
    print(f"\nSaved -> {out_path}")


if __name__ == "__main__":
    main()
