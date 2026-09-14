"""Analyze the actual distribution of same-identity vs different-identity
cosine similarities, so gallery thresholds are set from real data rather
than guessed. Uses open_world_split() so "different-identity" pairs include
tigers held out of training entirely, not just held-out images of identities
the backbone has already memorized - otherwise the diff-identity similarity
distribution is measured on the easy case and the resulting threshold will
be too permissive for genuinely new individuals in the field.
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from build_embedding_model import build_embedding_model, FINETUNED_WEIGHTS
from evaluate_embeddings import compute_embeddings
from prepare_data import open_world_split

THRESHOLDS_PATH = Path(__file__).parent / "models" / "gallery_thresholds.json"


def main(use_finetuned=False):
    print("Loading embedding model...", "(fine-tuned)" if use_finetuned else "(baseline)")
    model = build_embedding_model(
        finetuned_weights_path=FINETUNED_WEIGHTS if use_finetuned else None)

    train_items, known_val_items, unseen_items = open_world_split()
    all_items = train_items + known_val_items + unseen_items
    print(f"Computing embeddings for {len(all_items)} images "
          f"({len(unseen_items)} from {len(set(l for _, l in unseen_items))} identities "
          f"held out of training entirely)...")
    emb, labels = compute_embeddings(model, all_items, batch_size=32)

    sims = emb @ emb.T
    n = len(labels)
    same_mask = (labels[:, None] == labels[None, :]) & ~np.eye(n, dtype=bool)
    diff_mask = (labels[:, None] != labels[None, :])

    same_sims = sims[same_mask]
    diff_sims = sims[diff_mask]

    print(f"\nSame-identity pairs: {len(same_sims)}")
    print(f"  mean={same_sims.mean():.3f} std={same_sims.std():.3f} "
          f"p5={np.percentile(same_sims,5):.3f} p50={np.percentile(same_sims,50):.3f}")
    print(f"\nDifferent-identity pairs: {len(diff_sims)}")
    print(f"  mean={diff_sims.mean():.3f} std={diff_sims.std():.3f} "
          f"p95={np.percentile(diff_sims,95):.3f} p99={np.percentile(diff_sims,99):.3f} "
          f"max={diff_sims.max():.3f}")

    # Find a threshold that maximizes separation (Youden's J / simple sweep)
    print("\nThreshold sweep (as auto-accept cutoff):")
    print(f"{'thresh':<8}{'TPR (same>=t)':<16}{'FPR (diff>=t)':<16}")
    best_t, best_j = None, -1
    for t in np.arange(0.5, 1.0, 0.02):
        tpr = (same_sims >= t).mean()
        fpr = (diff_sims >= t).mean()
        j = tpr - fpr
        marker = ""
        if j > best_j:
            best_j = j
            best_t = t
            marker = "  <- best J"
        print(f"{t:<8.2f}{tpr:<16.4f}{fpr:<16.4f}{marker}")

    print(f"\nSuggested auto-accept threshold (max Youden's J): {best_t:.2f}")

    # For a stricter operating point, find threshold with FPR ~1%.
    # This becomes AUTO_ACCEPT_THRESHOLD: gallery.py should only auto-enroll
    # without review when we're this confident, since an unreviewed false
    # match silently corrupts an identity's centroid going forward.
    sorted_diff = np.sort(diff_sims)[::-1]
    fpr_1pct_idx = int(0.01 * len(sorted_diff))
    auto_accept_t = float(sorted_diff[fpr_1pct_idx])
    print(f"Threshold for ~1% false-accept rate on different identities: {auto_accept_t:.3f}")

    # REVIEW_THRESHOLD (the floor below which we stop asking a human and
    # just enroll as new): the paper's Table 7 tradeoff pushed toward
    # catching new individuals rather than convenience, since a missed
    # review costs a silent duplicate identity while an extra review costs
    # a few seconds - so this should sit as low as same-identity pairs
    # still meaningfully occur, NOT the same-identity p5 in isolation:
    # when same-identity similarities cluster tightly near the top (as
    # here), that p5 can land above auto_accept_t and invert the intended
    # auto_accept > review > reject ordering. Clamp below auto_accept_t so
    # the three-way ordering always holds.
    review_t = float(np.percentile(same_sims, 5))
    review_t = min(review_t, auto_accept_t - 0.01)
    print(f"Suggested review-floor threshold (same-identity p5, clamped below auto-accept): {review_t:.3f}")

    print(f"\ngallery.py constants to update:")
    print(f"  AUTO_ACCEPT_THRESHOLD = {auto_accept_t:.2f}")
    print(f"  REVIEW_THRESHOLD = {review_t:.2f}")

    THRESHOLDS_PATH.parent.mkdir(parents=True, exist_ok=True)
    THRESHOLDS_PATH.write_text(json.dumps({
        "auto_accept_threshold": round(auto_accept_t, 4),
        "review_threshold": round(review_t, 4),
        "used_finetuned_model": use_finetuned,
    }, indent=2))
    print(f"\nWrote thresholds to {THRESHOLDS_PATH} - gallery.py loads this automatically.")


if __name__ == "__main__":
    main(use_finetuned="--finetuned" in sys.argv)
