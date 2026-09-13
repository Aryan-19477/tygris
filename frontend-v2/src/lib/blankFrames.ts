// Mock data + client-side state for the blank-frame quarantine/trash UI.
// No model is wired up here — classification results are simulated so the
// review/restore/purge workflow can be designed and tested end to end
// before a real blank-frame classifier exists.

export interface BlankFrameBatch {
  batch_id: string;
  station_id: string;
  ingested_at: string;
  total_frames: number;
}

export interface BlankFrame {
  frame_id: string;
  batch_id: string;
  station_id: string;
  filename: string;
  captured_at: string;
  confidence: number; // model confidence that the frame is blank, 0-1
  file_size_kb: number;
  thumbnail_src: string;
  is_actually_blank: boolean; // whether the frame really has no animal in it
  quarantined_at: string;
}

const STATIONS = ["PENCH-CAM-014", "PENCH-CAM-027", "PENCH-CAM-041", "PENCH-CAM-058", "PENCH-CAM-063"];

const BLANK_THUMBS = Array.from({ length: 12 }, (_, i) => `/blank-frames/blank_${String(i + 1).padStart(3, "0")}.jpg`);
const TIGER_THUMBS = Array.from({ length: 10 }, (_, i) => `/blank-frames/tiger_${String(i + 1).padStart(3, "0")}.jpg`);

function seededRandom(seed: number) {
  let s = seed;
  return () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
}

function buildMockFrames(): BlankFrame[] {
  const rand = seededRandom(42);
  const frames: BlankFrame[] = [];
  const now = Date.now();

  for (let b = 0; b < 4; b++) {
    const batchId = `BATCH-${1000 + b}`;
    const station = STATIONS[b % STATIONS.length];
    const ingestedAt = new Date(now - (4 - b) * 86400000);
    const frameCount = 6 + Math.floor(rand() * 6);

    for (let i = 0; i < frameCount; i++) {
      const confidence = 0.55 + rand() * 0.44;
      const capturedAt = new Date(ingestedAt.getTime() - Math.floor(rand() * 3600000));
      // ~12% of "blank" classifications are actually a tiger frame the
      // classifier got wrong — the case a ranger needs to catch on review.
      const isMisclassified = rand() < 0.12;
      const thumbnail_src = isMisclassified
        ? TIGER_THUMBS[Math.floor(rand() * TIGER_THUMBS.length)]
        : BLANK_THUMBS[Math.floor(rand() * BLANK_THUMBS.length)];
      frames.push({
        frame_id: `${batchId}-F${String(i + 1).padStart(3, "0")}`,
        batch_id: batchId,
        station_id: station,
        filename: `IMG_${4000 + b * 100 + i}.JPG`,
        captured_at: capturedAt.toISOString(),
        confidence: Math.min(0.99, confidence),
        file_size_kb: 1800 + Math.floor(rand() * 2600),
        thumbnail_src,
        is_actually_blank: !isMisclassified,
        quarantined_at: ingestedAt.toISOString(),
      });
    }
  }

  return frames;
}

export const MOCK_BATCHES: BlankFrameBatch[] = [
  { batch_id: "BATCH-1000", station_id: STATIONS[0], ingested_at: new Date(Date.now() - 4 * 86400000).toISOString(), total_frames: 214 },
  { batch_id: "BATCH-1001", station_id: STATIONS[1], ingested_at: new Date(Date.now() - 3 * 86400000).toISOString(), total_frames: 168 },
  { batch_id: "BATCH-1002", station_id: STATIONS[2], ingested_at: new Date(Date.now() - 2 * 86400000).toISOString(), total_frames: 302 },
  { batch_id: "BATCH-1003", station_id: STATIONS[3], ingested_at: new Date(Date.now() - 1 * 86400000).toISOString(), total_frames: 121 },
];

export const MOCK_FRAMES: BlankFrame[] = buildMockFrames();

export const DEFAULT_CONFIDENCE_THRESHOLD = 0.8;

export function estimateProcessingSeconds(frameCount: number): number {
  // Rough stand-in for "time saved not manually reviewing these frames" —
  // assumes ~4s of ranger review time per frame avoided.
  return frameCount * 4;
}

export function formatBytes(kb: number): string {
  if (kb >= 1024) return `${(kb / 1024).toFixed(1)} MB`;
  return `${Math.round(kb)} KB`;
}

export function formatDuration(seconds: number): string {
  if (seconds >= 3600) return `${(seconds / 3600).toFixed(1)} hr`;
  if (seconds >= 60) return `${Math.round(seconds / 60)} min`;
  return `${Math.round(seconds)} sec`;
}
