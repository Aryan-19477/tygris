import type { ReviewQueueItem, Sighting } from "./api";

/**
 * Unified Attention Queue item: merges real conflict alerts (village
 * proximity, from /api/alerts) with ID-ambiguity review items (from
 * /api/review-queue) into one ranked inbox, per the "one queue, not two"
 * decision in the UX plan. Urgency order: village-proximity conflicts
 * first, then ambiguous IDs, then routine candidates.
 */
export type UrgencyLevel = "CRITICAL" | "CAUTION" | "ROUTINE";

/**
 * The three ranger-facing alert categories, ranked by operational
 * priority: a tiger near a village is always the top-priority trigger
 * (direct human-wildlife-conflict risk), a male-male territory overlap is
 * next (fight risk between residents), and an unidentified tiger is a
 * lower-urgency "go verify this" flag. "GENERAL" covers anything else
 * (buffer excursions, etc.) that isn't one of the three named triggers.
 */
export type AlertCategory =
  | "VILLAGE_PROXIMITY"
  | "MALE_TERRITORY_CONFLICT"
  | "UNIDENTIFIED_TIGER"
  | "GENERAL";

export interface AttentionItem {
  id: string;
  kind: "conflict" | "identification";
  urgency: UrgencyLevel;
  category: AlertCategory;
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

function headlineForConflict(s: Sighting): string {
  switch (s.alert_category) {
    case "VILLAGE_PROXIMITY":
      return `${s.tiger_id} near a village boundary`;
    case "MALE_TERRITORY_CONFLICT":
      return `Possible fight risk: ${s.tiger_id} near another male's territory`;
    case "UNIDENTIFIED_TIGER":
      return `Unidentified tiger detected${s.camera_id ? ` at ${s.camera_id}` : ""}`;
    default:
      return s.alert_level === "CRITICAL"
        ? `${s.tiger_id} near a village boundary`
        : `${s.tiger_id} moved into the buffer zone`;
  }
}

// Category ranking within the same urgency tier: village proximity is
// always the most important trigger to see first, male-conflict next,
// unidentified tigers last, everything else after that.
const CATEGORY_RANK: Record<AlertCategory, number> = {
  VILLAGE_PROXIMITY: 0,
  MALE_TERRITORY_CONFLICT: 1,
  UNIDENTIFIED_TIGER: 2,
  GENERAL: 3,
};

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
      category: (s.alert_category as AlertCategory) || "GENERAL",
      timestamp: s.timestamp || "",
      station_id: s.camera_id || s.station || undefined,
      zone: s.zone,
      tiger_id: s.tiger_id,
      headline: headlineForConflict(s),
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
      category: "UNIDENTIFIED_TIGER",
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
    const catDiff = CATEGORY_RANK[a.category] - CATEGORY_RANK[b.category];
    if (catDiff !== 0) return catDiff;
    return (b.timestamp || "").localeCompare(a.timestamp || "");
  });
}
