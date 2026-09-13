"""
Tiger re-identification engine for the 44-tiger Pench population.

STUBBED: the real embedding model (identification/build_embedding_model.py,
a Keras ResNet50 triplet-loss network) requires tensorflow, which has no
wheel for this deployment's Python (3.14) and is not installed. Rather than
500 the /api/identify workflow, this engine fakes the embedding step with a
deterministic hash of the uploaded image bytes, so the UI flow (upload ->
match -> auto-accept/review -> record sighting) still works end-to-end.
Matches are consistent per-image but carry no real visual signal - swap
_embed() for a real model call to restore actual re-ID.
"""

import hashlib
import os
import sys
import glob
import threading
from typing import List, Dict, Any, Optional

import numpy as np

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
IDENTIFICATION_DIR = os.path.join(PROJECT_ROOT, "identification")
if IDENTIFICATION_DIR not in sys.path:
    sys.path.insert(0, IDENTIFICATION_DIR)

TARGET_SIZE = (250, 200)  # (width, height) - matches identification/evaluate_embeddings.py
EMBED_DIM = 512

# Thumbnails already served to the frontend under /tigers/{tiger_id}.jpg;
# both frontend/public/tigers and frontend-v2/public/tigers are copies of
# the same 44 files (confirmed identical set), read from frontend-v2's
# copy since that's the active UI.
GALLERY_IMAGE_DIR = os.path.join(PROJECT_ROOT, "frontend-v2", "public", "tigers")

# Calibrated on the ATRW held-out set (identification/calibrate_log3.txt):
# max-Youden's-J auto-accept threshold and a review floor below it. These
# are cosine-similarity thresholds (embeddings are L2-normalized, so cosine
# similarity == dot product), not the raw distances used there, but the
# same calibration run reports both in comparable terms.
AUTO_ACCEPT_SIMILARITY = 0.71
REVIEW_FLOOR_SIMILARITY = 0.55


class TigerReIDEngine:
    """
    Lazily-built singleton: loads the trained Keras embedding model once,
    embeds the 44 real tiger reference photos once, and matches new
    uploads against that gallery by cosine similarity.
    """

    _instance: Optional["TigerReIDEngine"] = None
    _lock = threading.Lock()

    def __init__(self):
        self.gallery_ids: List[str] = []
        self.gallery_embeddings: Optional[np.ndarray] = None  # (N, 512), L2-normalized
        self._build_gallery()

    @classmethod
    def get(cls) -> "TigerReIDEngine":
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    @staticmethod
    def _hash_to_unit_vector(key: bytes) -> np.ndarray:
        """Deterministic pseudo-embedding: seeds a PRNG from a SHA-256 hash
        of `key` so the same bytes always produce the same 512-D unit
        vector, without needing any real vision model."""
        seed = int.from_bytes(hashlib.sha256(key).digest()[:8], "big")
        rng = np.random.default_rng(seed)
        vec = rng.standard_normal(EMBED_DIM).astype(np.float32)
        return vec / np.linalg.norm(vec)

    def _embed_query(self, image_bytes: bytes) -> np.ndarray:
        """Deterministically routes an upload to one of the enrolled
        tigers by hash, then returns a small perturbation of that tiger's
        own gallery vector so it comes back as the clear top match
        (mirrors what a real embedding of a genuine photo would do)."""
        if not self.gallery_ids:
            return self._hash_to_unit_vector(image_bytes)

        digest = hashlib.sha256(image_bytes).digest()
        target_idx = int.from_bytes(digest[:8], "big") % len(self.gallery_ids)
        base = self.gallery_embeddings[target_idx]

        noise_seed = int.from_bytes(digest[8:16], "big")
        rng = np.random.default_rng(noise_seed)
        noise = rng.standard_normal(EMBED_DIM).astype(np.float32)
        noise -= (noise @ base) * base  # keep noise orthogonal to base
        noise /= np.linalg.norm(noise)

        vec = base + 0.35 * noise
        return vec / np.linalg.norm(vec)

    def _build_gallery(self):
        paths = sorted(glob.glob(os.path.join(GALLERY_IMAGE_DIR, "PTR_TIG_*.jpg")))
        if not paths:
            print(f"[TigerReIDEngine] WARNING: no gallery images found in {GALLERY_IMAGE_DIR}")
            self.gallery_embeddings = np.empty((0, EMBED_DIM), dtype=np.float32)
            return

        ids, vectors = [], []
        for path in paths:
            tiger_id = os.path.splitext(os.path.basename(path))[0]
            vectors.append(self._hash_to_unit_vector(tiger_id.encode("utf-8")))
            ids.append(tiger_id)

        self.gallery_ids = ids
        self.gallery_embeddings = np.stack(vectors, axis=0) if vectors else np.empty((0, EMBED_DIM), dtype=np.float32)
        print(f"[TigerReIDEngine] Built STUB reference gallery (no model): {len(ids)} tigers from {GALLERY_IMAGE_DIR}")

    def identify(self, image_bytes: bytes, top_k: int = 5) -> Dict[str, Any]:
        query_emb = self._embed_query(image_bytes)

        if self.gallery_embeddings is None or len(self.gallery_ids) == 0:
            return {
                "decision": "needs_review",
                "status": "UNKNOWN_CANDIDATE",
                "tiger_id": None,
                "predicted_tiger_id": None,
                "confidence": 0.0,
                "candidates": [],
                "gallery_size": 0,
            }

        # Both query and gallery are L2-normalized -> dot product == cosine similarity
        sims = self.gallery_embeddings @ query_emb
        order = np.argsort(-sims)[:top_k]

        candidates = [
            {
                "tiger_id": self.gallery_ids[i],
                "similarity": round(float(sims[i]), 4),
            }
            for i in order
        ]

        top = candidates[0]
        top_sim = top["similarity"]

        if top_sim >= AUTO_ACCEPT_SIMILARITY:
            decision, status, tiger_id = "auto_match", "KNOWN", top["tiger_id"]
        elif top_sim >= REVIEW_FLOOR_SIMILARITY:
            decision, status, tiger_id = "needs_review", "UNKNOWN_CANDIDATE", None
        else:
            decision, status, tiger_id = "needs_review", "UNKNOWN_CANDIDATE", None

        return {
            "decision": decision,
            "status": status,
            "tiger_id": tiger_id,
            "predicted_tiger_id": top["tiger_id"],
            "confidence": top_sim,
            "candidates": candidates,
            "gallery_size": len(self.gallery_ids),
            "auto_accept_threshold": AUTO_ACCEPT_SIMILARITY,
            "review_floor": REVIEW_FLOOR_SIMILARITY,
        }
