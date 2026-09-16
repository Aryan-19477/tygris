import * as ort from "onnxruntime-web";
import type { Candidate, IdentifyResult } from "./api";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? "http://127.0.0.1:8420";

// Hosted on Vercel Blob rather than bundled under public/ — the fp16 ONNX
// file is ~97MB, too close to GitHub's ~100MB per-file limit to commit to
// the repo Vercel deploys from, and it doesn't belong in Next.js's build
// output anyway. Override via env for local testing against a different copy.
const MODEL_URL =
  process.env.NEXT_PUBLIC_METRIC_MODEL_URL ??
  "https://hgcysmu7eh8tdwnb.public.blob.vercel-storage.com/models/convnext_metric_fp16-lPP7sSUfavpSRhwlIcglmIYwHCpGEq.onnx";
const EMBED_DIM = 64;
const INPUT_SIZE = 224;

// Mirrors REAL_AUTO_ACCEPT_SIMILARITY / REAL_REVIEW_FLOOR_SIMILARITY in
// backend/app/ml/reid_embedding.py — the client match must use the same
// calibrated thresholds as the server path it's standing in for.
const AUTO_ACCEPT_SIMILARITY = 0.82;
const REVIEW_FLOOR_SIMILARITY = 0.4;

const IMAGENET_MEAN = [0.485, 0.456, 0.406];
const IMAGENET_STD = [0.229, 0.224, 0.225];

// Served from jsDelivr rather than bundled locally — the standard way to
// use onnxruntime-web, and avoids checking ~42MB of WASM binaries into git.
ort.env.wasm.wasmPaths = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.30.0/dist/";
// Silences benign perf-info warnings (e.g. "node not assigned to preferred
// EP") that print by default and are easily mistaken for real errors.
ort.env.logLevel = "error";
if (typeof crossOriginIsolated === "undefined" || !crossOriginIsolated) {
  // Threaded wasm needs SharedArrayBuffer, which requires COOP/COEP
  // response headers this app doesn't set. Without it, force single
  // thread instead of letting onnxruntime-web hit a hard error.
  ort.env.wasm.numThreads = 1;
}

interface GalleryEntry {
  tiger_id: string;
  embedding: number[];
}

let sessionPromise: Promise<ort.InferenceSession> | null = null;
let galleryPromise: Promise<GalleryEntry[]> | null = null;

function loadSession(): Promise<ort.InferenceSession> {
  if (!sessionPromise) {
    sessionPromise = ort.InferenceSession.create(MODEL_URL, {
      executionProviders: typeof navigator !== "undefined" && "gpu" in navigator ? ["webgpu", "wasm"] : ["wasm"],
      graphOptimizationLevel: "all",
    }).catch((err) => {
      sessionPromise = null;
      throw err;
    });
  }
  return sessionPromise;
}

function loadGallery(): Promise<GalleryEntry[]> {
  if (!galleryPromise) {
    galleryPromise = fetch(`${API_BASE}/gallery-data/trained_gallery.json`)
      .then((res) => {
        if (!res.ok) throw new Error(`Failed to fetch reference gallery: ${res.status}`);
        return res.json();
      })
      .catch((err) => {
        galleryPromise = null;
        throw err;
      });
  }
  return galleryPromise;
}

/** Best-effort feature check before committing to the client path — actual
 * fallback still happens on any runtime failure in identifyClientSide. */
export function isClientInferenceLikelySupported(): boolean {
  return typeof window !== "undefined" && typeof WebAssembly !== "undefined";
}

/** Warms the model + gallery fetch ahead of the user's first upload so the
 * "identifying" spinner isn't dominated by the one-time ~100MB download. */
export function prewarmClientIdentify(): void {
  if (!isClientInferenceLikelySupported()) return;
  loadSession().catch(() => {});
  loadGallery().catch(() => {});
}

async function fileToImageBitmap(file: File): Promise<ImageBitmap> {
  return createImageBitmap(file);
}

function preprocess(bitmap: ImageBitmap): Float32Array {
  const canvas = document.createElement("canvas");
  canvas.width = INPUT_SIZE;
  canvas.height = INPUT_SIZE;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas 2D context unavailable");
  // Direct stretch to 224x224, matching torchvision's T.Resize((224, 224))
  // used server-side (backend/app/ml/representation/augmentations.py),
  // which does not preserve aspect ratio for a 2-tuple size.
  ctx.drawImage(bitmap, 0, 0, INPUT_SIZE, INPUT_SIZE);
  const { data } = ctx.getImageData(0, 0, INPUT_SIZE, INPUT_SIZE);

  const chw = new Float32Array(3 * INPUT_SIZE * INPUT_SIZE);
  const plane = INPUT_SIZE * INPUT_SIZE;
  for (let i = 0; i < plane; i++) {
    const r = data[i * 4] / 255;
    const g = data[i * 4 + 1] / 255;
    const b = data[i * 4 + 2] / 255;
    chw[i] = (r - IMAGENET_MEAN[0]) / IMAGENET_STD[0];
    chw[plane + i] = (g - IMAGENET_MEAN[1]) / IMAGENET_STD[1];
    chw[2 * plane + i] = (b - IMAGENET_MEAN[2]) / IMAGENET_STD[2];
  }
  return chw;
}

function fileToDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

/**
 * Runs the full tiger re-identification match entirely in the browser:
 * ConvNeXt-small metric embedding (ONNX, fp16) -> cosine similarity against
 * /gallery-data/trained_gallery.json. Mirrors TigerReIDEngine.identify() in
 * backend/app/ml/reid_embedding.py so results agree with the server path.
 */
export async function identifyClientSide(file: File, station?: string): Promise<IdentifyResult> {
  const [session, gallery, bitmap, uploadedImage] = await Promise.all([
    loadSession(),
    loadGallery(),
    fileToImageBitmap(file),
    fileToDataUrl(file),
  ]);

  const inputTensor = new ort.Tensor("float32", preprocess(bitmap), [1, 3, INPUT_SIZE, INPUT_SIZE]);
  const outputs = await session.run({ input: inputTensor });
  const outputName = session.outputNames[0];
  const embedding = outputs[outputName].data as Float32Array;
  if (embedding.length !== EMBED_DIM) {
    throw new Error(`Unexpected embedding size ${embedding.length}, expected ${EMBED_DIM}`);
  }

  if (gallery.length === 0) {
    return {
      decision: "needs_review",
      status: "UNKNOWN_CANDIDATE",
      tiger_id: null,
      predicted_tiger_id: null,
      confidence: 0,
      candidates: [],
      gallery_size: 0,
      uploaded_image: uploadedImage,
      station_id: station ?? null,
    };
  }

  // Both query and gallery embeddings are L2-normalized (the exported
  // model wraps extract_normalized_embeddings), so dot product == cosine
  // similarity — same shortcut TigerReIDEngine.identify() takes.
  const bestPerTiger = new Map<string, number>();
  for (const entry of gallery) {
    let dot = 0;
    for (let i = 0; i < EMBED_DIM; i++) dot += embedding[i] * entry.embedding[i];
    const prev = bestPerTiger.get(entry.tiger_id);
    if (prev === undefined || dot > prev) bestPerTiger.set(entry.tiger_id, dot);
  }

  const candidates: Candidate[] = Array.from(bestPerTiger.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([tiger_id, similarity]) => ({ tiger_id, similarity: Math.round(similarity * 10000) / 10000 }));

  const top = candidates[0];
  const decision = top.similarity >= AUTO_ACCEPT_SIMILARITY ? "auto_match" : "needs_review";
  const status = decision === "auto_match" ? "KNOWN" : "UNKNOWN_CANDIDATE";

  return {
    decision,
    status,
    tiger_id: decision === "auto_match" ? top.tiger_id : null,
    predicted_tiger_id: top.tiger_id,
    confidence: top.similarity,
    candidates,
    gallery_size: bestPerTiger.size,
    auto_accept_threshold: AUTO_ACCEPT_SIMILARITY,
    review_floor: REVIEW_FLOOR_SIMILARITY,
    uploaded_image: uploadedImage,
    station_id: station ?? null,
  };
}

/** Tells the server which sighting/review-queue bookkeeping to do for a
 * match that was computed client-side, so the Capture Log and review queue
 * stay consistent regardless of which path ran the inference. */
export async function finalizeClientIdentification(file: File, result: IdentifyResult, station?: string): Promise<IdentifyResult> {
  const form = new FormData();
  form.append("file", file);
  const params = new URLSearchParams({
    decision: result.decision,
    status: result.status,
    confidence: String(result.confidence),
    candidates_json: JSON.stringify(result.candidates),
    gallery_size: String(result.gallery_size),
  });
  if (result.tiger_id) params.set("tiger_id", result.tiger_id);
  if (result.predicted_tiger_id) params.set("predicted_tiger_id", result.predicted_tiger_id);
  if (result.auto_accept_threshold !== undefined) params.set("auto_accept_threshold", String(result.auto_accept_threshold));
  if (result.review_floor !== undefined) params.set("review_floor", String(result.review_floor));
  if (station) params.set("station", station);

  // Sighting/review-queue bookkeeping is best-effort: a network hiccup here
  // must not discard the identification result already computed on-device,
  // nor trigger the caller's server-side fallback (which would re-run the
  // whole match from scratch for no reason).
  try {
    const res = await fetch(`${API_BASE}/api/identify/finalize?${params.toString()}`, {
      method: "POST",
      body: form,
    });
    if (!res.ok) return result;
    return await res.json();
  } catch {
    return result;
  }
}
