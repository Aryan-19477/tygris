const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? "http://127.0.0.1:8420";

/** Capture Log image_url values are backend-relative paths (e.g.
 * "/captures/EVT_xxx.jpg") — must be joined with the API origin, not the
 * frontend's own, since they're served by FastAPI's static mount. */
export function captureImageSrc(path: string | null): string | null {
  return path ? `${API_BASE}${path}` : null;
}

export type Decision = "auto_match" | "needs_review";

export interface Candidate {
  tiger_id: string;
  similarity: number;
}

/**
 * Real 44-tiger reference-gallery match: the uploaded photo's embedding
 * (ResNet50, triplet-loss fine-tuned) is compared by cosine similarity
 * against one real reference photo per enrolled tiger. predicted_tiger_id
 * is always one of the 44 real IDs in tiger_profiles — never a class index
 * outside the actual population.
 */
export interface IdentifyResult {
  decision: Decision;
  status: "KNOWN" | "UNKNOWN_CANDIDATE";
  tiger_id: string | null;
  predicted_tiger_id: string | null;
  confidence: number;
  candidates: Candidate[];
  gallery_size: number;
  auto_accept_threshold?: number;
  review_floor?: number;
  uploaded_image: string;
  station_id?: string | null;
  recorded_event_id?: string;
  recorded_status?: "SAVED_TO_GRAPH";
}

export interface GalleryIndividual {
  tiger_id: string;
  name?: string;
  sex?: string;
  age_years?: number;
  life_stage?: string;
  territorial_status?: string;
  mcp_area_km2?: number;
  num_captures: number;
  stations: string[];
  last_seen: string | null;
  thumbnail: string | null;
}

export interface GalleryDetail {
  profile?: {
    tiger_id: string;
    name: string;
    sex: string;
    age_years: number;
    life_stage: string;
    territorial_status: string;
    home_range_target_km2: number;
    mcp_area_km2: number;
    core_centroid_lat: number;
    core_centroid_lon: number;
    thumbnail?: string | null;
    total_captures?: number;
  };
  tiger_id?: string;
  captures: {
    event_id?: string;
    image?: string | null;
    station?: string | null;
    camera_id?: string | null;
    latitude?: number;
    longitude?: number;
    zone?: string;
    flank_side?: string;
    timestamp: string | null;
    alert_level?: string;
    speed_kmh?: number;
  }[];
  pose_analysis?: {
    image?: string;
    keypoints?: unknown;
    flank?: string;
    confidence?: number;
  };
  trajectory?: [number, number][];
  embedding?: {
    available: boolean;
    metric_model_trained: boolean;
    vector?: number[] | null;
    dim?: number;
    num_source_entries?: number;
    l2_norm?: number;
    reason?: string;
    detail?: string;
  } | null;
}

export interface ReviewQueueItem {
  item_id: string;
  timestamp?: string;
  station_id?: string;
  zone?: string;
  candidates: Candidate[];
  uploaded_image?: string;
  reason?: string;
  nearest_distance?: number;
}

export interface Stats {
  total_individuals: number;
  total_stations?: number;
  active_stations?: number;
  total_captures: number;
  pending_review: number;
  critical_alerts?: number;
  caution_alerts?: number;
  trap_nights_simulated?: number;
  core_area_km2?: number;
  buffer_area_km2?: number;
  stations?: string[];
}

export interface CaptureLogItem {
  event_id: string;
  tiger_id: string | null;
  tiger_name: string | null;
  camera_id: string;
  zone?: string;
  timestamp: string;
  flank_side?: string;
  alert_level?: string;
  image_url: string | null;
}

export interface Sighting {
  event_id?: string;
  tiger_id: string;
  image?: string | null;
  station?: string | null;
  camera_id?: string | null;
  latitude?: number;
  longitude?: number;
  zone?: string;
  timestamp: string | null;
  alert_level?: string;
  threat_reason?: string;
  speed_kmh?: number;
}

export interface GISStation {
  camera_id: string;
  latitude: number;
  longitude: number;
  grid_id?: string;
  zone: string;
  sub_region?: string;
  habitat?: string;
  operational_status: string;
  uptime_ratio: number;
  nearest_water_km?: number;
  nearest_village_km?: number;
  trail_type?: string;
}

export interface GISMapBundle {
  version: string;
  metadata: {
    reserve: string;
    total_stations: number;
    total_tigers: number;
    total_villages: number;
    core_area_km2: number;
    buffer_area_km2: number;
    sampling_grid_size_km2: number;
  };
  core_boundary: [number, number][];
  buffer_boundary: [number, number][];
  sub_regions: {
    name: string;
    zone: string;
    center: [number, number];
    area_km2: number;
    habitat: string;
  }[];
  villages: {
    name: string;
    lat: number;
    lon: number;
    population: number;
    livestock: number;
  }[];
  water_sources: {
    name: string;
    lat: number;
    lon: number;
    type: string;
  }[];
  stations: GISStation[];
  territories: Record<
    string,
    {
      tiger_id: string;
      name: string;
      sex: string;
      life_stage: string;
      centroid: [number, number];
      area_km2: number;
      polygon: [number, number][];
    }
  >;
  recent_sightings: Sighting[];
}

export interface TigerAssociationPair {
  tiger_a: string;
  tiger_b: string;
  sex_a: string;
  sex_b: string;
  co_occurrences: number;
  shared_stations: string[];
}

export interface TigerAssociations {
  pairs: TigerAssociationPair[];
  window_hours: number;
}

export interface ScreeningFrame {
  index: number;
  timestamp_sec: number;
  status: "KEPT" | "REJECTED";
  reason:
    | "TIGER_CANDIDATE"
    | "BLANK_IMAGE"
    | "NO_ANIMAL"
    | "NON_ANIMAL"
    | "NON_TARGET_WILDLIFE";
  quality_score: number;
  detection_class: string | null;
  detection_conf: number;
  thumbnail: string;
}

export interface ScreeningResult {
  total_frames_sampled: number;
  sample_fps: number;
  counts: {
    BLANK_IMAGE: number;
    NON_ANIMAL: number;
    NO_ANIMAL: number;
    NON_TARGET_WILDLIFE: number;
    TIGER_CANDIDATE: number;
  };
  frames: ScreeningFrame[];
  best_frame: (ScreeningFrame & { full_image: string | null }) | null;
}

// ---------------------------------------------------------------------
// Ranger Ops: field reports written by the Ranger Flutter app into
// Supabase (see supabase/migrations/0001_ranger_ops.sql), read back here
// and cross-referenced against the camera-trap network by the backend's
// territory-check intelligence.
// ---------------------------------------------------------------------

export interface RangerObservation {
  observation_id: string;
  patrol_id: string | null;
  ranger_id: string;
  obs_type: string;
  species_category?: string | null;
  severity?: string | null;
  lat: number | null;
  lon: number | null;
  timestamp: string;
  structured_attrs?: Record<string, unknown> | null;
  remarks?: string | null;
  sync_status?: string;
  created_at?: string;
}

export interface RangerPatrol {
  patrol_id: string;
  ranger_id: string;
  team_id?: string | null;
  beat_area?: string | null;
  patrol_type?: string | null;
  status?: string;
  start_time?: string | null;
  end_time?: string | null;
  distance_km?: number | null;
  created_at?: string;
}

export type TerritoryCheckStatus =
  | "confirmed_present"
  | "possible_move"
  | "no_recent_data"
  | "no_location";

export interface NearestCamera {
  camera_id: string;
  distance_km: number;
  zone?: string;
  sub_region?: string;
}

export interface TerritoryCheck {
  check_id: string;
  observation_id: string;
  resident_tiger_id: string | null;
  nearest_cameras: NearestCamera[];
  status: TerritoryCheckStatus;
  summary: string;
  computed_at: string;
}

export interface RangerReports {
  patrols: RangerPatrol[];
  observations: RangerObservation[];
  configured: boolean;
}

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, options);
  if (!res.ok) {
    throw new Error(`Request failed: ${res.status} ${res.statusText}`);
  }
  return res.json();
}

export const api = {
  stats: () => request<Stats>("/api/stats"),

  gallery: () => request<{ individuals: GalleryIndividual[] }>("/api/gallery"),

  galleryDetail: (tigerId: string) =>
    request<GalleryDetail>(`/api/gallery/${tigerId}`),

  tigerAssociations: (limit = 10, oppositeSexOnly = true, windowHours = 48) =>
    request<TigerAssociations>(
      `/api/tiger-associations?limit=${limit}&opposite_sex_only=${oppositeSexOnly}&window_hours=${windowHours}`
    ),

  gisBundle: async (): Promise<GISMapBundle> => {
    try {
      return await request<GISMapBundle>("/api/gis/bundle");
    } catch {
      const res = await fetch("/pench_web_bundle.json");
      if (res.ok) return res.json();
      throw new Error("Failed to load GIS map bundle.");
    }
  },

  stations: () => request<{ stations: GISStation[] }>("/api/stations"),

  alerts: (level?: string, limit = 50) => {
    const query = level ? `?level=${encodeURIComponent(level)}&limit=${limit}` : `?limit=${limit}`;
    return request<{ alerts: Sighting[]; total: number }>(`/api/alerts${query}`);
  },

  acknowledgeAlert: (eventId: string) =>
    request<{ status: string; event_id: string }>(`/api/alerts/${encodeURIComponent(eventId)}/acknowledge`, {
      method: "POST",
    }),

  identify: (file: File, station?: string) => {
    const form = new FormData();
    form.append("file", file);
    const query = station ? `?station=${encodeURIComponent(station)}` : "";
    return request<IdentifyResult>(`/api/identify${query}`, {
      method: "POST",
      body: form,
    });
  },

  screenVideo: (file: File, sampleFps = 3) => {
    const form = new FormData();
    form.append("file", file);
    return request<ScreeningResult>(
      `/api/screening/process-video?sample_fps=${sampleFps}`,
      { method: "POST", body: form }
    );
  },

  reviewQueue: () => request<{ items: ReviewQueueItem[] }>("/api/review-queue"),

  captures: (opts: { limit?: number; before?: string; cameraId?: string; tigerId?: string } = {}) => {
    const params = new URLSearchParams();
    if (opts.limit) params.set("limit", String(opts.limit));
    if (opts.before) params.set("before", opts.before);
    if (opts.cameraId) params.set("camera_id", opts.cameraId);
    if (opts.tigerId) params.set("tiger_id", opts.tigerId);
    const qs = params.toString();
    return request<{ items: CaptureLogItem[]; next_before: string | null }>(`/api/captures${qs ? `?${qs}` : ""}`);
  },

  resolveReview: (itemId: string, tigerId: string | null) =>
    request<{ status: string; item_id: string; assigned_tiger_id: string; is_new_individual: boolean }>(
      `/api/review-queue/${itemId}/resolve`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ assigned_tiger_id: tigerId }),
      }
    ),

  modelStatus: () =>
    request<{ is_fully_trained: boolean; weights_loaded: Record<string, boolean>; checkpoints_dir: string }>(
      "/api/model-status"
    ),

  rangerReports: () => request<RangerReports>("/api/ranger/reports"),

  runTerritoryCheck: (observationId: string) =>
    request<TerritoryCheck>(`/api/ranger/territory-check/${encodeURIComponent(observationId)}`, {
      method: "POST",
    }),

  runPendingTerritoryChecks: () =>
    request<{ processed: number; configured: boolean }>("/api/ranger/territory-check/run-pending", {
      method: "POST",
    }),
};
