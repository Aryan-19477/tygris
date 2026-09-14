"""Persistent, queryable gallery of known tiger identities.

Each entry stores one or more embeddings per individual plus metadata
(station, timestamp, GPS) for every capture. New images are matched by
cosine similarity against the gallery centroid/nearest neighbors:

  - similarity >= AUTO_ACCEPT_THRESHOLD -> confident match, auto-applied
  - REVIEW_THRESHOLD <= similarity < AUTO_ACCEPT_THRESHOLD -> ambiguous,
    queued for human review
  - similarity < REVIEW_THRESHOLD -> no known match, enroll as a new individual
"""
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Tuple

import numpy as np

# Fallback values used until calibrate_thresholds.py has been run against
# the current model; prefer models/gallery_thresholds.json (auto-loaded
# below) since these fixed numbers aren't derived from real embedding
# separation and won't track model/data changes.
AUTO_ACCEPT_THRESHOLD = 0.74
REVIEW_THRESHOLD = 0.55

_THRESHOLDS_PATH = Path(__file__).parent / "models" / "gallery_thresholds.json"
if _THRESHOLDS_PATH.exists():
    _calibrated = json.loads(_THRESHOLDS_PATH.read_text())
    AUTO_ACCEPT_THRESHOLD = _calibrated["auto_accept_threshold"]
    REVIEW_THRESHOLD = _calibrated["review_threshold"]


@dataclass
class Capture:
    image_path: str
    station: Optional[str] = None
    timestamp: Optional[str] = None
    gps: Optional[Tuple[float, float]] = None


@dataclass
class Identity:
    tiger_id: str
    embeddings: list = field(default_factory=list)  # list[np.ndarray]
    captures: list = field(default_factory=list)     # list[Capture]

    def centroid(self):
        return np.mean(np.stack(self.embeddings), axis=0)


class TigerGallery:
    def __init__(self):
        self.identities = {}  # dict[str, Identity]
        self._next_id = 1

    def _new_id(self):
        tid = f"TIG-{self._next_id:03d}"
        self._next_id += 1
        return tid

    def enroll(self, embedding, capture: Capture, tiger_id=None):
        tiger_id = tiger_id or self._new_id()
        if tiger_id not in self.identities:
            self.identities[tiger_id] = Identity(tiger_id=tiger_id)
        self.identities[tiger_id].embeddings.append(np.asarray(embedding))
        self.identities[tiger_id].captures.append(capture)
        return tiger_id

    def _similarities(self, embedding):
        embedding = np.asarray(embedding)
        sims = {}
        for tid, identity in self.identities.items():
            centroid = identity.centroid()
            sim = float(np.dot(embedding, centroid))  # cosine sim, both L2-normalized
            sims[tid] = sim
        return sims

    def match(self, embedding, capture: Capture, top_k=5):
        """Match a new embedding against the gallery and decide the outcome.

        Returns a dict describing the decision: auto_match, needs_review, or new_individual.
        """
        if not self.identities:
            tiger_id = self.enroll(embedding, capture)
            return {
                "decision": "new_individual",
                "tiger_id": tiger_id,
                "similarity": None,
                "candidates": [],
            }

        sims = self._similarities(embedding)
        ranked = sorted(sims.items(), key=lambda kv: -kv[1])
        top_id, top_sim = ranked[0]
        candidates = ranked[:top_k]

        if top_sim >= AUTO_ACCEPT_THRESHOLD:
            self.enroll(embedding, capture, tiger_id=top_id)
            return {
                "decision": "auto_match",
                "tiger_id": top_id,
                "similarity": top_sim,
                "candidates": candidates,
            }
        elif top_sim >= REVIEW_THRESHOLD:
            return {
                "decision": "needs_review",
                "tiger_id": None,
                "similarity": top_sim,
                "candidates": candidates,
            }
        else:
            tiger_id = self.enroll(embedding, capture)
            return {
                "decision": "new_individual",
                "tiger_id": tiger_id,
                "similarity": top_sim,
                "candidates": candidates,
            }

    def match_burst(self, embeddings, capture: Capture, top_k=5,
                     dis_thres=0.4, vote_const=0.1):
        """Match several frames from the same sighting (e.g. consecutive
        camera-trap frames of one passing tiger) as a single query, instead
        of judging each frame in isolation.

        A single frame can be blurred, poorly lit, or catch an awkward
        angle; the paper found fusing evidence across all frames of a video
        materially outperformed any single-frame decision, using inverse-
        distance-weighted voting per candidate identity (Eq. 1: w = 1/(const
        + distance), only counting neighbors within Dis-thres). This mirrors
        that for the metric-learning space here: each frame casts a vote for
        every identity within dis_thres of it (in cosine distance = 1 - sim),
        weighted by closeness, and votes are summed across frames. A single
        embedding behaves the same as match() but reduces to a vote of one.
        """
        embeddings = [np.asarray(e) for e in embeddings]
        if not embeddings:
            raise ValueError("match_burst requires at least one embedding")

        if not self.identities:
            tiger_id = self.enroll(embeddings[0], capture)
            for e in embeddings[1:]:
                self.enroll(e, capture, tiger_id=tiger_id)
            return {
                "decision": "new_individual",
                "tiger_id": tiger_id,
                "similarity": None,
                "candidates": [],
            }

        votes = {tid: 0.0 for tid in self.identities}
        best_sim_per_id = {tid: -1.0 for tid in self.identities}
        for embedding in embeddings:
            sims = self._similarities(embedding)
            for tid, sim in sims.items():
                best_sim_per_id[tid] = max(best_sim_per_id[tid], sim)
                distance = 1.0 - sim
                if distance <= dis_thres:
                    votes[tid] += 1.0 / (vote_const + distance)

        ranked = sorted(votes.items(), key=lambda kv: -kv[1])
        top_id, top_vote = ranked[0]
        # report the best single-frame similarity for the winning identity,
        # so the response stays comparable to match()'s "similarity" field.
        top_sim = best_sim_per_id[top_id]
        candidates = [(tid, best_sim_per_id[tid]) for tid, _ in ranked[:top_k]]

        representative = embeddings[0]
        if top_vote <= 0:
            tiger_id = self.enroll(representative, capture)
            for e in embeddings[1:]:
                self.enroll(e, capture, tiger_id=tiger_id)
            return {
                "decision": "new_individual",
                "tiger_id": tiger_id,
                "similarity": top_sim if top_sim >= 0 else None,
                "candidates": candidates,
            }

        if top_sim >= AUTO_ACCEPT_THRESHOLD:
            for e in embeddings:
                self.enroll(e, capture, tiger_id=top_id)
            return {
                "decision": "auto_match",
                "tiger_id": top_id,
                "similarity": top_sim,
                "candidates": candidates,
            }
        elif top_sim >= REVIEW_THRESHOLD:
            return {
                "decision": "needs_review",
                "tiger_id": None,
                "similarity": top_sim,
                "candidates": candidates,
            }
        else:
            tiger_id = self.enroll(representative, capture)
            for e in embeddings[1:]:
                self.enroll(e, capture, tiger_id=tiger_id)
            return {
                "decision": "new_individual",
                "tiger_id": tiger_id,
                "similarity": top_sim,
                "candidates": candidates,
            }

    def resolve_review(self, embedding, capture: Capture, tiger_id):
        """Human reviewer confirms an ambiguous match belongs to tiger_id
        (existing or brand new id)."""
        return self.enroll(embedding, capture, tiger_id=tiger_id)

    def summary(self):
        rows = []
        for tid, identity in self.identities.items():
            stations = sorted({c.station for c in identity.captures if c.station})
            rows.append({
                "tiger_id": tid,
                "num_captures": len(identity.captures),
                "stations": stations,
            })
        return rows

    def save(self, path):
        path = Path(path)
        data = {
            "next_id": self._next_id,
            "identities": {
                tid: {
                    "embeddings": [e.tolist() for e in identity.embeddings],
                    "captures": [
                        {"image_path": c.image_path, "station": c.station,
                         "timestamp": c.timestamp, "gps": c.gps}
                        for c in identity.captures
                    ],
                }
                for tid, identity in self.identities.items()
            },
        }
        path.write_text(json.dumps(data, indent=2))

    @classmethod
    def load(cls, path):
        data = json.loads(Path(path).read_text())
        gallery = cls()
        gallery._next_id = data["next_id"]
        for tid, entry in data["identities"].items():
            identity = Identity(tiger_id=tid)
            identity.embeddings = [np.array(e) for e in entry["embeddings"]]
            identity.captures = [Capture(**c) for c in entry["captures"]]
            gallery.identities[tid] = identity
        return gallery
