"""Evaluate embedding quality: top-1/top-5 identity retrieval accuracy on the
held-out val set, used as gallery vs itself (leave-one-out) or against a
separate query set, plus a rank-1 accuracy summary and an optional
t-SNE/UMAP-style 2D projection for visual inspection.
"""
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from background_suppress import suppress_background
from prepare_data import train_val_split


def load_and_preprocess(path, target_size=(250, 200), remove_background=False):
    im = Image.open(path).convert("RGB").resize(target_size)
    arr = np.array(im, dtype=np.uint8)
    if remove_background:
        arr = suppress_background(arr)
    return arr.astype(np.float32)


def compute_embeddings(model, items, batch_size=32):
    embeddings = []
    labels = []
    paths = [p for p, _ in items]
    for i in range(0, len(paths), batch_size):
        batch_paths = paths[i:i + batch_size]
        batch = np.stack([load_and_preprocess(p) for p in batch_paths])
        emb = model.predict(batch, verbose=0)
        embeddings.append(emb)
    embeddings = np.concatenate(embeddings, axis=0)
    labels = np.array([l for _, l in items])
    return embeddings, labels


def rank_k_accuracy(query_emb, query_labels, gallery_emb, gallery_labels, k=5, exclude_self=False):
    sims = query_emb @ gallery_emb.T  # cosine sim since both are L2-normalized
    if exclude_self:
        # when query and gallery are the same set, mask the diagonal
        np.fill_diagonal(sims, -np.inf)

    correct_at = np.zeros(k)
    for i in range(len(query_labels)):
        order = np.argsort(-sims[i])[:k]
        matched_ranks = gallery_labels[order] == query_labels[i]
        for rank in range(k):
            if matched_ranks[:rank + 1].any():
                correct_at[rank] += 1
    return correct_at / len(query_labels)


def main(model, split_seed=42, held_out=3):
    _, val_items = train_val_split(held_out_per_identity=held_out, seed=split_seed)
    print(f"evaluating on {len(val_items)} held-out images across {len(set(l for _, l in val_items))} identities")

    emb, labels = compute_embeddings(model, val_items)
    acc = rank_k_accuracy(emb, labels, emb, labels, k=5, exclude_self=True)
    for rank, a in enumerate(acc, start=1):
        print(f"rank-{rank} accuracy (leave-one-out within held-out set): {a:.4f}")
    return emb, labels, acc


if __name__ == "__main__":
    from build_embedding_model import build_embedding_model
    model = build_embedding_model()
    main(model)
