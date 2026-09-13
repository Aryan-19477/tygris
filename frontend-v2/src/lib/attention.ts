import type { ReviewQueueItem, Sighting } from "./api";

/**
 * Unified Attention Queue item: merges real conflict alerts (village
 * proximity, from /api/alerts) with ID-ambiguity review items (from
 * /api/review-queue) into one ranked inbox, per the "one queue, not two"
 * decision in the UX plan. Urgency order: village-proximity conflicts
 * first, then ambiguous IDs, then routine candidates.
 */
export type UrgencyLevel = "CRITICAL" | "CAUTION" | "ROUTINE";

export interface AttentionItem {
  id: string;
  kind: "conflict" | "identification";
  urgency: UrgencyLevel;
  timestamp: string;
  station_id?: string;
  zone?: string;
  tiger_id?: string;
  headline: string;
  detail: string;
  image?: string | null;
  reviewItem?: ReviewQueueItem;
  sighting?: Sighting;
}

const URGENCY_RANK: Record<UrgencyLevel, number> = {
  CRITICAL: 0,
  CAUTION: 1,
  ROUTINE: 2,
};

function urgencyFromZone(zone: string | undefined): UrgencyLevel {
  if (zone === "VILLAGE_EDGE" || zone === "CRITICAL") return "CRITICAL";
  if (zone === "BUFFER") return "CAUTION";
  return "ROUTINE";
}

export function buildAttentionQueue(
  conflictAlerts: Sighting[],
  reviewItems: ReviewQueueItem[]
): AttentionItem[] {
  const fromConflicts: AttentionItem[] = conflictAlerts
    .filter((s) => s.alert_level === "CRITICAL" || s.alert_level === "CAUTION")
    .map((s) => ({
      id: s.event_id || `${s.tiger_id}-${s.timestamp}`,
      kind: "conflict",
      urgency: (s.alert_level as UrgencyLevel) || "CAUTION",
      timestamp: s.timestamp || "",
      station_id: s.camera_id || s.station || undefined,
      zone: s.zone,
      tiger_id: s.tiger_id,
      headline:
        s.alert_level === "CRITICAL"
          ? `${s.tiger_id} near a village boundary`
          : `${s.tiger_id} moved into the buffer zone`,
      detail: s.threat_reason || "Movement flagged by the anomaly classifier.",
      image: s.image,
      sighting: s,
    }));

  const fromReview: AttentionItem[] = reviewItems.map((item) => {
    const topSim = item.candidates[0]?.similarity ?? 0;
    return {
      id: item.item_id,
      kind: "identification",
      urgency: urgencyFromZone(item.zone),
      timestamp: item.timestamp || "",
      station_id: item.station_id,
      zone: item.zone,
      headline: "Ambiguous identity match",
      detail:
        item.reason ||
        `Closest candidate ${item.candidates[0]?.tiger_id ?? "unknown"} at ${Math.round(topSim * 100)}% similarity.`,
      image: item.uploaded_image,
      reviewItem: item,
    };
  });

  return [...fromConflicts, ...fromReview].sort((a, b) => {
    const rankDiff = URGENCY_RANK[a.urgency] - URGENCY_RANK[b.urgency];
    if (rankDiff !== 0) return rankDiff;
    return (b.timestamp || "").localeCompare(a.timestamp || "");
  });
}
