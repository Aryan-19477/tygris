"""
Tiger re-identification engine for the real Pench population (62 tigers,
Dataset/PTR_Tiger_IDs_2025).

Uses the real trained ConvNeXt-small metric-learning model
(backend/checkpoints/convnext_metric_best.pth, trained by
backend/scripts/train_reid_models.py on the real dataset) and the real
reference gallery it built (backend/data/gallery/trained_gallery.json) when
both are present and torch is importable in the running interpreter.

Falls back to a deterministic hash-based pseudo-embedding otherwise (e.g.
running under this machine's default Python 3.14, which has no torch wheel
yet) so /api/identify never 500s even without the trained model - matches
are then per-image-consistent but carry no real visual signal. Run the
backend with backend/.venv312/Scripts/python.exe to get the real model.
"""

import hashlib
import json
import os
import sys
import glob
import threading
from typing import List, Dict, Any, Optional

import numpy as np

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

TARGET_SIZE = (250, 200)  # (width, height) - fallback stub embedding only
EMBED_DIM_STUB = 512
EMBED_DIM_REAL = 128

# Thumbnails already served to the frontend under /tigers/{tiger_id}.jpg;
# both frontend/public/tigers and frontend-v2/public/tigers are copies of
# the same 44 files (confirmed identical set), read from frontend-v2's
# copy since that's the active UI.
GALLERY_IMAGE_DIR = os.path.join(PROJECT_ROOT, "frontend-v2", "public", "tigers")

REAL_CHECKPOINT = os.path.join(PROJECT_ROOT, "backend", "checkpoints", "convnext_metric_best.pth")
REAL_GALLERY_PATH = os.path.join(PROJECT_ROOT, "backend", "data", "gallery", "trained_gallery.json")

# Stub thresholds (calibrated on the old ATRW-trained model, kept for the
# hash-fallback path). The real model uses its own thresholds below.
AUTO_ACCEPT_SIMILARITY = 0.71
REVIEW_FLOOR_SIMILARITY = 0.55

# Real-model thresholds: calibrated against real held-out data (see
# backend/scripts/open_set_eval.py, which holds real tiger identities out
# of the gallery entirely and treats them as ground-truth "unknowns").
# 0.60 was an early guess that turned out to auto-accept ~96% of genuinely
# unknown/out-of-gallery images (mean unknown-query similarity was 0.737,
# barely below the 0.60 bar) - confirmed live when an AI-generated tiger
# image (not in the dataset) scored 70% and was shown as a "confident
# match". 0.82 is the calibrated tradeoff point: ~88% of true unknowns
# correctly rejected, at the cost of ~32% of genuine known-tiger photos
# being sent to manual review instead of auto-matched. Re-run
# open_set_eval.py to recalibrate after any future retrain.
REAL_AUTO_ACCEPT_SIMILARITY = 0.82
REAL_REVIEW_FLOOR_SIMILARITY = 0.40


class TigerReIDEngine:
    """
    Lazily-built singleton: loads the real trained metric-learning model and
    reference gallery once (or falls back to a hash-based stub gallery), and
    matches new uploads against it by cosine similarity.
    """

    _instance: Optional["TigerReIDEngine"] = None
    _lock = threading.Lock()

    def __init__(self):
        self.gallery_ids: List[str] = []
        self.gallery_embeddings: Optional[np.ndarray] = None
        self.real_model_loaded = False
        self._model = None
        self._transform = None
        self._device = "cpu"

        if self._try_load_real_model():
            self._build_real_gallery()
        else:
            self._build_stub_gallery()

    @classmethod
    def get(cls) -> "TigerReIDEngine":
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    # ------------------------------------------------------------------
    # Real trained model path
    # ------------------------------------------------------------------
    def _try_load_real_model(self) -> bool:
        if not (os.path.exists(REAL_CHECKPOINT) and os.path.exists(REAL_GALLERY_PATH)):
            print(
                f"[TigerReIDEngine] Real checkpoint/gallery not found "
                f"({REAL_CHECKPOINT}, {REAL_GALLERY_PATH}) - using hash-based stub."
            )
            return False
        try:
            import torch
            from backend.app.ml.metric_learning.models import get_metric_model
            from backend.app.ml.representation.augmentations import get_paper_reid_transforms
        except ImportError as e:
            print(f"[TigerReIDEngine] torch not available in this interpreter ({e}) - using hash-based stub.")
            return False

        try:
            self._device = "cuda" if torch.cuda.is_available() else "cpu"
            model = get_metric_model(name="ConvNeXt-small", embedding_dim=EMBED_DIM_REAL, pretrained=False)
            model.load_state_dict(torch.load(REAL_CHECKPOINT, map_location=self._device, weights_only=True))
            model.to(self._device).eval()
            self._model = model
            self._transform = get_paper_reid_transforms((224, 224), is_training=False)
            self._torch = torch
            self.real_model_loaded = True
            print(f"[TigerReIDEngine] Loaded REAL trained metric model from {REAL_CHECKPOINT} on {self._device}")
            return True
        except Exception as e:
            print(f"[TigerReIDEngine] Failed to load real model: {e} - using hash-based stub.")
            return False

    def _build_real_gallery(self):
        with open(REAL_GALLERY_PATH, "r", encoding="utf-8") as f:
            entries = json.load(f)
        ids, vectors = [], []
        for e in entries:
            ids.append(e["tiger_id"])
            vectors.append(np.array(e["embedding"], dtype=np.float32))
        self.gallery_ids = ids
        self.gallery_embeddings = np.stack(vectors, axis=0) if vectors else np.empty((0, EMBED_DIM_REAL), dtype=np.float32)
        print(
            f"[TigerReIDEngine] Built REAL reference gallery: {len(set(ids))} tigers, "
            f"{len(ids)} reference embeddings from {REAL_GALLERY_PATH}"
        )

    def _embed_query_real(self, image_bytes: bytes) -> np.ndarray:
        import io
        from PIL import Image

        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        tensor = self._transform(img).unsqueeze(0).to(self._device)
        with self._torch.no_grad():
            emb = self._model.extract_normalized_embeddings(tensor).squeeze(0).cpu().numpy()
        return emb

    # ------------------------------------------------------------------
    # Hash-based stub fallback (no torch / no trained checkpoint)
    # ------------------------------------------------------------------
    @staticmethod
    def _hash_to_unit_vector(key: bytes) -> np.ndarray:
        """Deterministic pseudo-embedding: seeds a PRNG from a SHA-256 hash
        of `key` so the same bytes always produce the same unit vector,
        without needing any real vision model."""
        seed = int.from_bytes(hashlib.sha256(key).digest()[:8], "big")
        rng = np.random.default_rng(seed)
        vec = rng.standard_normal(EMBED_DIM_STUB).astype(np.float32)
        return vec / np.linalg.norm(vec)

    def _embed_query_stub(self, image_bytes: bytes) -> np.ndarray:
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
        noise = rng.standard_normal(EMBED_DIM_STUB).astype(np.float32)
        noise -= (noise @ base) * base  # keep noise orthogonal to base
        noise /= np.linalg.norm(noise)

        vec = base + 0.35 * noise
        return vec / np.linalg.norm(vec)

    def _build_stub_gallery(self):
        paths = sorted(glob.glob(os.path.join(GALLERY_IMAGE_DIR, "*.jpg")))
        if not paths:
            print(f"[TigerReIDEngine] WARNING: no gallery images found in {GALLERY_IMAGE_DIR}")
            self.gallery_embeddings = np.empty((0, EMBED_DIM_STUB), dtype=np.float32)
            return

        ids, vectors = [], []
        for path in paths:
            tiger_id = os.path.splitext(os.path.basename(path))[0]
            vectors.append(self._hash_to_unit_vector(tiger_id.encode("utf-8")))
            ids.append(tiger_id)

        self.gallery_ids = ids
        self.gallery_embeddings = np.stack(vectors, axis=0) if vectors else np.empty((0, EMBED_DIM_STUB), dtype=np.float32)
        print(f"[TigerReIDEngine] Built STUB reference gallery (no model): {len(ids)} tigers from {GALLERY_IMAGE_DIR}")

    # ------------------------------------------------------------------
    # Shared matching logic
    # ------------------------------------------------------------------
    def identify(self, image_bytes: bytes, top_k: int = 5) -> Dict[str, Any]:
        query_emb = self._embed_query_real(image_bytes) if self.real_model_loaded else self._embed_query_stub(image_bytes)

        if self.gallery_embeddings is None or len(self.gallery_ids) == 0:
            return {
                "decision": "needs_review",
                "status": "UNKNOWN_CANDIDATE",
                "tiger_id": None,
                "predicted_tiger_id": None,
                "confidence": 0.0,
                "candidates": [],
                "gallery_size": 0,
                "model_status": "trained" if self.real_model_loaded else "STUB_NO_MODEL",
            }

        # Both query and gallery are L2-normalized -> dot product == cosine similarity
        sims = self.gallery_embeddings @ query_emb

        if self.real_model_loaded:
            # The real gallery has multiple reference images per tiger, so
            # dedupe to each tiger's single best-matching reference before
            # ranking candidates (otherwise one tiger could occupy all of
            # top_k just by having more reference photos).
            best_per_tiger: Dict[str, float] = {}
            for tid, sim in zip(self.gallery_ids, sims):
                if tid not in best_per_tiger or sim > best_per_tiger[tid]:
                    best_per_tiger[tid] = float(sim)
            ranked = sorted(best_per_tiger.items(), key=lambda kv: -kv[1])[:top_k]
            candidates = [{"tiger_id": tid, "similarity": round(sim, 4)} for tid, sim in ranked]
            auto_thresh, review_thresh = REAL_AUTO_ACCEPT_SIMILARITY, REAL_REVIEW_FLOOR_SIMILARITY
        else:
            order = np.argsort(-sims)[:top_k]
            candidates = [{"tiger_id": self.gallery_ids[i], "similarity": round(float(sims[i]), 4)} for i in order]
            auto_thresh, review_thresh = AUTO_ACCEPT_SIMILARITY, REVIEW_FLOOR_SIMILARITY

        top = candidates[0]
        top_sim = top["similarity"]

        if top_sim >= auto_thresh:
            decision, status, tiger_id = "auto_match", "KNOWN", top["tiger_id"]
        elif top_sim >= review_thresh:
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
            "gallery_size": len(set(self.gallery_ids)),
            "auto_accept_threshold": auto_thresh,
            "review_floor": review_thresh,
            "model_status": "trained" if self.real_model_loaded else "STUB_NO_MODEL",
        }
