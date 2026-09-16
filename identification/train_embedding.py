"""Fine-tune the embedding model with batch-hard triplet loss on ATRW Re-ID.

Backbone stays partly frozen (conv1-conv3) with conv4 and conv5 plus the
512-d embedding head trainable. The paper found *no* frozen layers beat a
frozen-early-layers transfer-learning setup, since the tiger-stripe task is
distinct enough from ImageNet/Tiger_Trace's original classification target
that early layers benefit from adapting too. We stop short of their fully
unfrozen setup: their dataset was 34,691 images across 16 individuals with
heavy augmentation, while this one is ~1,900 images across 107 identities,
and this backbone was already pretrained as a 107-way closed-set classifier
over these exact identities - fully unfreezing raises real memorization risk
here rather than the generic-ImageNet-mismatch risk the paper was fixing.
Widening from conv5-only to conv4+conv5 moves toward their finding while
keeping the lowest-level, most generic filters (conv1-conv3) stable. Batches
are identity-balanced (P identities x K images each) since triplet mining
needs multiple images per identity per batch to find valid positive/negative
pairs.
"""
import random
import sys
import time
from pathlib import Path

import numpy as np
import tensorflow as tf

for _gpu in tf.config.list_physical_devices("GPU"):
    tf.config.experimental.set_memory_growth(_gpu, True)

sys.path.insert(0, str(Path(__file__).parent))
from build_embedding_model import build_embedding_model
from evaluate_embeddings import compute_embeddings, load_and_preprocess, main as evaluate_main
from prepare_data import open_world_split, train_val_split
from triplet_loss import batch_hard_triplet_loss

P_IDENTITIES_PER_BATCH = 5
K_IMAGES_PER_IDENTITY = 4
EPOCHS = 40
STEPS_PER_EPOCH = 80
LEARNING_RATE = 1e-4
WEIGHT_DECAY = 1e-4
MARGIN = 0.3
UNFROZEN_STAGES = ("conv4_", "conv5_")
OUTPUT_PATH = Path(__file__).parent / "models" / "tiger_embedding_finetuned.weights.h5"
BEST_CHECKPOINT_PATH = Path(__file__).parent / "models" / "tiger_embedding_best.weights.h5"

# How often (in epochs) to run the open-world check during training. This is
# the metric that actually matters (see open_world_accuracy's docstring) —
# checkpointing/early-stopping on it, rather than only reporting it before
# and after training, is what prevents saving an overfit final-epoch model.
EVAL_EVERY_N_EPOCHS = 5
EARLY_STOP_PATIENCE = 4  # in units of EVAL_EVERY_N_EPOCHS checks, not epochs
OPEN_WORLD_DIS_THRES = 0.4  # the single threshold used to drive checkpointing/early-stopping


def unfreeze_top_of_backbone(model, unfrozen_stages=UNFROZEN_STAGES):
    """Freeze the backbone's earliest, most generic conv stages and leave
    the identity-relevant later stages (plus the embedding head) trainable.
    See module docstring for why this stops short of the paper's fully
    unfrozen setup."""
    resnet = model.get_layer("resnet50")
    resnet.trainable = True
    for layer in resnet.layers:
        layer.trainable = any(layer.name.startswith(stage) for stage in unfrozen_stages)

    for layer in model.layers:
        if layer.name == "resnet50":
            continue
        layer.trainable = True


def open_world_accuracy(model, dis_thres_values=(0.3, 0.4, 0.5)):
    """Report accuracy on identities the model has NEVER seen in training,
    the check that actually matters for catching memorization - unlike
    evaluate_main()'s rank-k accuracy, which reuses the same 107 identities
    the backbone was originally trained on as a closed-set classifier, so
    near-zero training loss there is consistent with pure memorization.
    For each dis_thres, an unseen-identity image is scored a "correct
    rejection" if its best similarity to any known-gallery centroid falls
    below (1 - dis_thres), mirroring the paper's Table 7 methodology.

    Returns the correct-rejection rate at OPEN_WORLD_DIS_THRES (or None if
    there are no held-out-identity images to evaluate), which is the single
    number the training loop checkpoints/early-stops on.
    """
    _, known_val_items, unseen_items = open_world_split()
    if not unseen_items:
        return None

    known_emb, known_labels = compute_embeddings(model, known_val_items)
    unseen_emb, _ = compute_embeddings(model, unseen_items)

    centroids = np.stack([
        known_emb[known_labels == label].mean(axis=0)
        for label in np.unique(known_labels)
    ])
    centroids /= np.linalg.norm(centroids, axis=1, keepdims=True)

    best_sim_to_known = (unseen_emb @ centroids.T).max(axis=1)
    print(f"unseen-identity images: {len(unseen_items)} "
          f"(from identities never in the training pool)")
    driving_metric = None
    for dis_thres in dis_thres_values:
        correctly_flagged_new = (best_sim_to_known < (1.0 - dis_thres)).mean()
        print(f"  dis_thres={dis_thres:.1f}  correctly recognized as new: "
              f"{correctly_flagged_new:.4f}")
        if abs(dis_thres - OPEN_WORLD_DIS_THRES) < 1e-9:
            driving_metric = float(correctly_flagged_new)
    return driving_metric


def build_identity_index(items):
    by_label = {}
    for path, label in items:
        by_label.setdefault(label, []).append(path)
    return by_label


def sample_batch(by_label, p, k, rng):
    labels = rng.sample(list(by_label.keys()), p)
    paths, batch_labels = [], []
    for label in labels:
        pool = by_label[label]
        chosen = rng.choices(pool, k=k) if len(pool) < k else rng.sample(pool, k)
        paths += chosen
        batch_labels += [label] * k
    images = np.stack([load_and_preprocess(p) for p in paths])
    return images, np.array(batch_labels, dtype=np.int32)


def main():
    print("Building embedding model from pretrained backbone...")
    model = build_embedding_model()
    unfreeze_top_of_backbone(model)

    trainable_count = sum(int(tf.size(w)) for w in model.trainable_weights)
    print(f"Trainable params: {trainable_count:,}")

    train_items, val_items = train_val_split()
    by_label = build_identity_index(train_items)
    print(f"Training pool: {len(train_items)} images across {len(by_label)} identities")

    # AdamW's decoupled weight decay acts as regularization across every
    # trainable weight (dense head + unfrozen conv4/conv5), which plain Adam
    # has no equivalent of — cheaper to add here than retrofitting
    # kernel_regularizer onto ResNet50's already-built conv layers (Keras
    # only applies a layer's regularizer at weight-creation time, so setting
    # one post-hoc on the pretrained backbone's layers would silently do
    # nothing).
    lr_schedule = tf.keras.optimizers.schedules.CosineDecay(
        initial_learning_rate=LEARNING_RATE, decay_steps=EPOCHS * STEPS_PER_EPOCH)
    optimizer = tf.keras.optimizers.AdamW(learning_rate=lr_schedule, weight_decay=WEIGHT_DECAY)
    rng = random.Random(123)

    print("\nBaseline (before fine-tune):")
    evaluate_main(model)
    print("\nBaseline open-world check (identities never in training pool):")
    open_world_accuracy(model)

    print(f"\nTraining for up to {EPOCHS} epochs x {STEPS_PER_EPOCH} steps "
          f"(batch = {P_IDENTITIES_PER_BATCH}x{K_IMAGES_PER_IDENTITY}), "
          f"checkpointing on open-world accuracy every {EVAL_EVERY_N_EPOCHS} epochs "
          f"with early stopping after {EARLY_STOP_PATIENCE} non-improving checks...\n")

    BEST_CHECKPOINT_PATH.parent.mkdir(parents=True, exist_ok=True)
    best_metric = -1.0
    checks_since_improvement = 0

    for epoch in range(1, EPOCHS + 1):
        epoch_start = time.time()
        losses = []
        for step in range(STEPS_PER_EPOCH):
            images, labels = sample_batch(by_label, P_IDENTITIES_PER_BATCH, K_IMAGES_PER_IDENTITY, rng)
            with tf.GradientTape() as tape:
                embeddings = model(images, training=True)
                loss = batch_hard_triplet_loss(labels, embeddings, margin=MARGIN)
            grads = tape.gradient(loss, model.trainable_weights)
            optimizer.apply_gradients(zip(grads, model.trainable_weights))
            losses.append(float(loss))

        elapsed = time.time() - epoch_start
        print(f"epoch {epoch:2d}/{EPOCHS}  loss={np.mean(losses):.4f}  "
              f"({elapsed:.1f}s, {elapsed/STEPS_PER_EPOCH:.2f}s/step)")

        if epoch % EVAL_EVERY_N_EPOCHS == 0 or epoch == EPOCHS:
            print(f"  [epoch {epoch}] open-world check:")
            metric = open_world_accuracy(model)
            if metric is not None:
                if metric > best_metric:
                    best_metric = metric
                    checks_since_improvement = 0
                    model.save_weights(str(BEST_CHECKPOINT_PATH))
                    print(f"  [epoch {epoch}] new best open-world accuracy "
                          f"({metric:.4f}) — checkpoint saved.")
                else:
                    checks_since_improvement += 1
                    print(f"  [epoch {epoch}] no improvement "
                          f"({checks_since_improvement}/{EARLY_STOP_PATIENCE})")
                    if checks_since_improvement >= EARLY_STOP_PATIENCE:
                        print(f"  Early stopping at epoch {epoch} "
                              f"(best open-world accuracy: {best_metric:.4f}).")
                        break

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    if best_metric >= 0.0:
        # Restore the best-open-world-accuracy checkpoint rather than
        # whatever the final epoch happened to land on — the final epoch is
        # not necessarily the least-overfit one (see module docstring).
        model.load_weights(str(BEST_CHECKPOINT_PATH))
        print(f"\nRestored best checkpoint (open-world accuracy {best_metric:.4f}).")
    model.save_weights(str(OUTPUT_PATH))
    print(f"Saved fine-tuned weights to {OUTPUT_PATH}")

    print("\nFinal (best-checkpoint) evaluation:")
    evaluate_main(model)
    print("\nFinal open-world check (identities never in training pool) — "
          "this is the number that matters, NOT the closed-set rank-k above:")
    open_world_accuracy(model)


if __name__ == "__main__":
    main()
