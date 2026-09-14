"""FastAPI server exposing the tiger identification pipeline for the frontend.

Endpoints:
  GET  /api/gallery                    -> list all enrolled individuals
  GET  /api/gallery/{tiger_id}         -> detail for one individual
  POST /api/identify                   -> upload an image, get match decision
  GET  /api/review-queue               -> list pending ambiguous captures
  POST /api/review-queue/{item_id}/resolve  -> reviewer confirms/enrolls
  GET  /api/stats                      -> summary counts for the dashboard
  GET  /api/embedding-space            -> 2D PCA projection of gallery embeddings
"""
import base64
import io
import sys
import uuid
from pathlib import Path
from typing import Optional

import numpy as np
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
from pydantic import BaseModel

sys.path.insert(0, str(Path(__file__).parent))
from build_embedding_model import build_embedding_model, FINETUNED_WEIGHTS
from gallery import TigerGallery, Capture

GALLERY_PATH = Path(__file__).parent / "gallery" / "demo_gallery.json"
STATIONS = ["Station-A", "Station-B", "Station-C", "Station-D"]

app = FastAPI(title="Tiger Identification API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

print("Loading fine-tuned embedding model...")
model = build_embedding_model(finetuned_weights_path=FINETUNED_WEIGHTS)
print("Loading gallery...")
gallery = TigerGallery.load(GALLERY_PATH) if GALLERY_PATH.exists() else TigerGallery()
print(f"Gallery ready: {len(gallery.identities)} individuals")

review_queue = {}  # item_id -> {embedding, capture, candidates}


def load_and_preprocess(pil_image, target_size=(250, 200)):
    im = pil_image.convert("RGB").resize(target_size)
    arr = np.array(im, dtype=np.uint8)
    # background_suppress (GrabCut) currently over-segments tight Re-ID crops,
    # deleting head/legs/tail along with real background - disabled until
    # that's fixed. See bg_check.jpg for the failure case.
    return arr.astype(np.float32)


def embed_image(pil_image):
    arr = load_and_preprocess(pil_image)[None, ...]
    return model.predict(arr, verbose=0)[0]


def image_to_data_uri(path):
    try:
        with open(path, "rb") as f:
            b64 = base64.b64encode(f.read()).decode()
        return f"data:image/jpeg;base64,{b64}"
    except FileNotFoundError:
        return None


class ReviewResolution(BaseModel):
    tiger_id: Optional[str] = None  # None = enroll as new


@app.get("/api/stats")
def get_stats():
    total_captures = sum(len(i.captures) for i in gallery.identities.values())
    return {
        "total_individuals": len(gallery.identities),
        "total_captures": total_captures,
        "pending_review": len(review_queue),
        "stations": STATIONS,
    }


@app.get("/api/gallery")
def list_gallery():
    items = []
    for tiger_id, identity in gallery.identities.items():
        last_capture = identity.captures[-1] if identity.captures else None
        stations = sorted({c.station for c in identity.captures if c.station})
        items.append({
            "tiger_id": tiger_id,
            "num_captures": len(identity.captures),
            "stations": stations,
            "last_seen": last_capture.timestamp if last_capture else None,
            "thumbnail": image_to_data_uri(identity.captures[0].image_path) if identity.captures else None,
        })
    items.sort(key=lambda x: x["tiger_id"])
    return {"individuals": items}


@app.get("/api/embedding-space")
def embedding_space():
    from sklearn.decomposition import PCA

    tiger_ids, embeddings = [], []
    for tiger_id, identity in gallery.identities.items():
        for emb in identity.embeddings:
            tiger_ids.append(tiger_id)
            embeddings.append(emb)

    if len(embeddings) < 3:
        return {"points": []}

    X = np.stack(embeddings)
    coords = PCA(n_components=2, random_state=0).fit_transform(X)
    coords = coords / (np.abs(coords).max() + 1e-8)  # normalize to [-1, 1]

    points = [
        {"tiger_id": tid, "x": float(x), "y": float(y)}
        for tid, (x, y) in zip(tiger_ids, coords)
    ]
    return {"points": points}


@app.get("/api/gallery/{tiger_id}")
def gallery_detail(tiger_id: str):
    identity = gallery.identities.get(tiger_id)
    if identity is None:
        return {"error": "not found"}
    captures = [
        {
            "image": image_to_data_uri(c.image_path),
            "station": c.station,
            "timestamp": c.timestamp,
        }
        for c in identity.captures
    ]
    return {"tiger_id": tiger_id, "captures": captures}


@app.post("/api/identify")
async def identify(file: UploadFile = File(...), station: Optional[str] = None):
    contents = await file.read()
    pil_image = Image.open(io.BytesIO(contents))
    emb = embed_image(pil_image)

    capture = Capture(
        image_path=f"upload:{file.filename}",
        station=station or STATIONS[0],
        timestamp="2026-08-16T12:00:00",
    )

    result = gallery.match(emb, capture)

    response = {
        "decision": result["decision"],
        "tiger_id": result["tiger_id"],
        "similarity": result["similarity"],
        "candidates": [{"tiger_id": tid, "similarity": sim} for tid, sim in result["candidates"]],
        "uploaded_image": f"data:image/jpeg;base64,{base64.b64encode(contents).decode()}",
    }

    if result["decision"] == "needs_review":
        item_id = str(uuid.uuid4())
        review_queue[item_id] = {
            "embedding": emb,
            "capture": capture,
            "candidates": result["candidates"],
            "uploaded_image": response["uploaded_image"],
        }
        response["review_item_id"] = item_id

    return response


@app.post("/api/identify-burst")
async def identify_burst(files: list[UploadFile] = File(...), station: Optional[str] = None):
    """Identify from several frames of the same sighting at once (e.g. a
    burst of consecutive camera-trap frames), fusing evidence across frames
    via weighted voting rather than judging a single frame in isolation -
    the paper found this fusion step reduced sensitivity to any one frame's
    blur, angle, or occlusion.
    """
    contents_list = [await f.read() for f in files]
    embeddings = [embed_image(Image.open(io.BytesIO(c))) for c in contents_list]

    capture = Capture(
        image_path=f"upload:{files[0].filename}",
        station=station or STATIONS[0],
        timestamp="2026-08-16T12:00:00",
    )

    result = gallery.match_burst(embeddings, capture)

    response = {
        "decision": result["decision"],
        "tiger_id": result["tiger_id"],
        "similarity": result["similarity"],
        "candidates": [{"tiger_id": tid, "similarity": sim} for tid, sim in result["candidates"]],
        "num_frames": len(embeddings),
        "uploaded_image": f"data:image/jpeg;base64,{base64.b64encode(contents_list[0]).decode()}",
    }

    if result["decision"] == "needs_review":
        item_id = str(uuid.uuid4())
        review_queue[item_id] = {
            "embedding": embeddings[0],
            "capture": capture,
            "candidates": result["candidates"],
            "uploaded_image": response["uploaded_image"],
        }
        response["review_item_id"] = item_id

    return response


@app.get("/api/review-queue")
def get_review_queue():
    items = []
    for item_id, entry in review_queue.items():
        items.append({
            "item_id": item_id,
            "candidates": [{"tiger_id": tid, "similarity": sim} for tid, sim in entry["candidates"]],
            "uploaded_image": entry["uploaded_image"],
        })
    return {"items": items}


@app.post("/api/review-queue/{item_id}/resolve")
def resolve_review(item_id: str, resolution: ReviewResolution):
    entry = review_queue.pop(item_id, None)
    if entry is None:
        return {"error": "not found"}

    tiger_id = gallery.resolve_review(
        entry["embedding"], entry["capture"], tiger_id=resolution.tiger_id
    )
    gallery.save(GALLERY_PATH)
    return {"tiger_id": tiger_id, "is_new": resolution.tiger_id is None}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8420)
