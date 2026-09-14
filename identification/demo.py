"""End-to-end demo of the identification pipeline:

1. Seed the gallery with a subset of known tigers (simulating an existing catalogue).
2. Feed held-out images through the matcher one at a time, simulating new
   camera-trap captures arriving over time.
3. Show the three possible outcomes: auto-match, needs-review, new-individual.
4. Deliberately withhold a few identities from the gallery entirely, to prove
   the open-set "new individual" enrollment path actually works.
"""
import random
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from build_embedding_model import build_embedding_model, FINETUNED_WEIGHTS
from evaluate_embeddings import load_and_preprocess
from gallery import TigerGallery, Capture
from prepare_data import train_val_split

STATIONS = ["Station-A", "Station-B", "Station-C", "Station-D"]


def embed_one(model, path):
    img = load_and_preprocess(path)[None, ...]
    return model.predict(img, verbose=0)[0]


def main():
    print("Loading fine-tuned embedding model...")
    model = build_embedding_model(finetuned_weights_path=FINETUNED_WEIGHTS)

    train_items, val_items = train_val_split()

    # Group by identity
    by_label_train = {}
    for path, label in train_items:
        by_label_train.setdefault(label, []).append(path)
    by_label_val = {}
    for path, label in val_items:
        by_label_val.setdefault(label, []).append(path)

    all_ids = sorted(by_label_train.keys())
    rng = random.Random(7)
    rng.shuffle(all_ids)

    # Simulate: gallery starts knowing most tigers, but a handful are
    # completely new / never-before-seen (true open-set test).
    num_unknown = 5
    known_ids = all_ids[num_unknown:]
    unknown_ids = all_ids[:num_unknown]

    print(f"\nSeeding gallery with {len(known_ids)} known tigers "
          f"({num_unknown} held back as brand-new individuals)...")

    gallery = TigerGallery()
    label_to_tiger_id = {}
    for label in known_ids:
        seed_paths = by_label_train[label][:3]  # a few captures to seed each identity
        tiger_id = None
        for i, path in enumerate(seed_paths):
            emb = embed_one(model, path)
            capture = Capture(image_path=path, station=rng.choice(STATIONS),
                               timestamp=f"2026-08-{10+i:02d}T06:00:00")
            tiger_id = gallery.enroll(emb, capture, tiger_id=tiger_id)
        label_to_tiger_id[label] = tiger_id

    print(f"Gallery seeded: {len(gallery.identities)} individuals, "
          f"{sum(len(i.captures) for i in gallery.identities.values())} captures")

    # Now simulate new incoming images: some from known tigers (held-out val
    # images), some from the truly-unknown tigers.
    incoming = []
    for label in known_ids:
        for path in by_label_val.get(label, [])[:1]:
            incoming.append((path, label, "known"))
    for label in unknown_ids:
        for path in by_label_train[label][:2]:
            incoming.append((path, label, "unknown"))
    rng.shuffle(incoming)

    print(f"\nProcessing {len(incoming)} incoming captures...\n")
    print(f"{'file':<14} {'true kind':<9} {'decision':<15} {'assigned id':<10} {'sim':<6}")
    print("-" * 65)

    outcomes = {"auto_match": 0, "needs_review": 0, "new_individual": 0}
    correct_auto = 0
    total_auto = 0
    review_queue = []  # (emb, capture, true_label, kind)

    for path, true_label, kind in incoming:
        emb = embed_one(model, path)
        capture = Capture(image_path=path, station=rng.choice(STATIONS),
                           timestamp="2026-08-16T07:00:00")
        result = gallery.match(emb, capture)
        outcomes[result["decision"]] += 1

        fname = Path(path).name
        sim_str = f"{result['similarity']:.3f}" if result["similarity"] is not None else "  -  "
        print(f"{fname:<14} {kind:<9} {result['decision']:<15} "
              f"{result['tiger_id'] or '-':<10} {sim_str}")

        if result["decision"] == "auto_match":
            total_auto += 1
            if label_to_tiger_id.get(true_label) == result["tiger_id"]:
                correct_auto += 1
        if result["decision"] == "needs_review":
            review_queue.append((emb, capture, true_label, kind, result["candidates"]))

    print("\n" + "=" * 65)
    print("Human review queue")
    print("=" * 65)
    print(f"{len(review_queue)} ambiguous captures need a reviewer decision.\n"
          f"A reviewer looks at the photo + top candidates and either confirms\n"
          f"a match to an existing tiger or enrolls it as a new individual.\n")

    correctly_flagged_new = 0
    correct_review_match = 0
    for emb, capture, true_label, kind, candidates in review_queue:
        fname = Path(capture.image_path).name
        top_id, top_sim = candidates[0] if candidates else (None, None)
        # Simulate reviewer judgment: a real ATRW tiger the model has strong
        # (if sub-threshold) evidence for gets confirmed; otherwise it's new.
        # We use ground truth here to stand in for the reviewer's decision.
        true_tiger_id = label_to_tiger_id.get(true_label)
        if true_tiger_id is not None:
            resolved_id = gallery.resolve_review(emb, capture, tiger_id=true_tiger_id)
            decision = "confirmed_existing"
            correct_review_match += 1
        else:
            resolved_id = gallery.resolve_review(emb, capture, tiger_id=None)
            decision = "enrolled_new"
            correctly_flagged_new += 1
        outcomes[decision] = outcomes.get(decision, 0) + 1
        print(f"{fname:<14} {kind:<9} top_candidate={top_id or '-'}({top_sim or 0:.3f})  "
              f"reviewer -> {decision:<18} {resolved_id}")

    print("\n" + "=" * 65)
    print("Summary")
    print("=" * 65)
    print(f"Outcomes before review: {outcomes}")
    if total_auto:
        print(f"Auto-match precision: {correct_auto}/{total_auto} = {correct_auto/total_auto:.1%}")
    num_unknown_incoming = sum(1 for _, _, kind in incoming if kind == "unknown")
    print(f"Truly-new tigers correctly enrolled as new (auto + after review): "
          f"{correctly_flagged_new}/{num_unknown_incoming}")
    print(f"Review-queue cases correctly resolved as existing tigers: "
          f"{correct_review_match}/{len(review_queue) - correctly_flagged_new if review_queue else 0}")
    print(f"\nFinal gallery size: {len(gallery.identities)} individuals")

    gallery.save(Path(__file__).parent / "gallery" / "demo_gallery.json")
    print(f"Gallery saved to identification/gallery/demo_gallery.json")


if __name__ == "__main__":
    main()
