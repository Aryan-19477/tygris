"""Load ATRW Re-ID train split into (filepath, label) pairs.

The official test split (reid_list_test.csv) has no identity labels (held-out
competition set), so it's unusable for accuracy validation. Instead we carve
a held-out val/gallery-test set out of the labeled train split, per identity.
"""
import csv
import random
from collections import defaultdict
from pathlib import Path

REID_ROOT = Path(__file__).parent.parent / "reid_raw"
HELD_OUT_PER_IDENTITY = 3
SEED = 42
UNSEEN_IDENTITY_FRACTION = 0.15


def load_split(split):
    csv_path = REID_ROOT / f"reid_list_{split}.csv"
    img_dir = REID_ROOT / split
    items = []
    with open(csv_path) as f:
        for row in csv.reader(f):
            if len(row) != 2:
                continue
            label, filename = row
            items.append((str(img_dir / filename), int(label)))
    return items


def train_val_split(held_out_per_identity=HELD_OUT_PER_IDENTITY, seed=SEED):
    """Split the labeled train set into a training pool and a held-out
    per-identity validation set, used both for embedding-quality checks and
    as a stand-in gallery to demo enrollment/matching."""
    items = load_split("train")
    by_label = defaultdict(list)
    for path, label in items:
        by_label[label].append(path)

    rng = random.Random(seed)
    train_items, val_items = [], []
    for label, paths in by_label.items():
        paths = sorted(paths)
        rng.shuffle(paths)
        held = paths[:held_out_per_identity]
        rest = paths[held_out_per_identity:]
        val_items += [(p, label) for p in held]
        train_items += [(p, label) for p in rest]
    return train_items, val_items


def open_world_split(unseen_fraction=UNSEEN_IDENTITY_FRACTION, held_out_per_identity=HELD_OUT_PER_IDENTITY, seed=SEED):
    """Held-out-IDENTITY split for genuine open-world evaluation.

    train_val_split() holds out individual images per identity, so every
    identity it validates on was still seen during backbone pretraining
    (Tiger_Trace's 107-way closed-set head) and/or triplet fine-tuning -
    it can only measure within-identity generalization, never whether the
    model can tell a truly novel tiger apart from known ones (the paper's
    Table 7 concern, and the reason its representation-learning module was
    dropped for open-world use). This split instead removes entire
    identities from the training pool so they can stand in as "new"
    individuals never encountered in training, mirroring that evaluation.
    """
    items = load_split("train")
    by_label = defaultdict(list)
    for path, label in items:
        by_label[label].append(path)

    labels = sorted(by_label.keys())
    rng = random.Random(seed)
    rng.shuffle(labels)

    num_unseen = max(1, int(len(labels) * unseen_fraction))
    unseen_labels = set(labels[:num_unseen])
    known_labels = labels[num_unseen:]

    train_items, known_val_items = [], []
    for label in known_labels:
        paths = sorted(by_label[label])
        rng.shuffle(paths)
        held = paths[:held_out_per_identity]
        rest = paths[held_out_per_identity:]
        known_val_items += [(p, label) for p in held]
        train_items += [(p, label) for p in rest]

    unseen_items = [(p, label) for label in unseen_labels for p in sorted(by_label[label])]

    return train_items, known_val_items, unseen_items


if __name__ == "__main__":
    train_items, val_items = train_val_split()
    print(f"train pool: {len(train_items)} images, {len(set(l for _, l in train_items))} identities")
    print(f"held-out val/gallery: {len(val_items)} images, {len(set(l for _, l in val_items))} identities")

    train_items, known_val_items, unseen_items = open_world_split()
    print(f"\nopen-world split:")
    print(f"train pool: {len(train_items)} images, {len(set(l for _, l in train_items))} identities")
    print(f"known held-out: {len(known_val_items)} images, {len(set(l for _, l in known_val_items))} identities")
    print(f"unseen (never trained on): {len(unseen_items)} images, {len(set(l for _, l in unseen_items))} identities")
