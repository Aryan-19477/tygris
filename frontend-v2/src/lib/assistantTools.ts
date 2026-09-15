import type { FunctionDeclaration } from "@google/genai";
import { Type } from "@google/genai";
import { api } from "@/lib/api";

/**
 * Tool surface the field assistant (Gemini) can call to answer a ranger's
 * question with real data. Each tool is a thin wrapper around the existing
 * `api` client, which already talks to the live FastAPI backend.
 */
export const ASSISTANT_TOOLS: FunctionDeclaration[] = [
  {
    name: "get_reserve_stats",
    description:
      "Get reserve-wide KPI counts: total tigers tracked, total/active camera stations, total captures, pending reviews, critical/caution alert counts, core and buffer area size.",
    parameters: { type: Type.OBJECT, properties: {} },
  },
  {
    name: "get_alerts",
    description:
      "Get real-time conflict alerts and anomalous tiger movements (e.g. a tiger approaching a village boundary). Use this for questions about priority alerts, recent sightings, or which tiger needs attention right now.",
    parameters: {
      type: Type.OBJECT,
      properties: {
        level: {
          type: Type.STRING,
          description: "Optional filter: CRITICAL, CAUTION, or SAFE. Omit to get all alerts.",
          enum: ["CRITICAL", "CAUTION", "SAFE"],
        },
        limit: {
          type: Type.INTEGER,
          description: "Max number of alerts to return, default 10.",
        },
      },
    },
  },
  {
    name: "get_camera_stations",
    description:
      "Get camera station data. Omit camera_id to get a compact list of all stations (status, uptime, zone) for 'how many cameras are online' type questions. Pass camera_id to get the full detail for one specific station — habitat, exact coordinates, distance to nearest water/village, trail type.",
    parameters: {
      type: Type.OBJECT,
      properties: {
        camera_id: {
          type: Type.STRING,
          description: "Optional. A specific station's ID, e.g. 'PTR_CAM_026', to get its full detail.",
        },
      },
    },
  },
  {
    name: "get_tiger_gallery",
    description:
      "Get the list of all enrolled individual tigers with their last-seen time, home range size, and which stations have spotted them. Use this for 'how many tigers' or general tiger roster questions.",
    parameters: { type: Type.OBJECT, properties: {} },
  },
  {
    name: "get_tiger_detail",
    description:
      "Get the deep profile for one specific tiger by ID (e.g. 'T-052'): recent captures, home range, last known location. Use this when the ranger asks about a specific named/numbered tiger.",
    parameters: {
      type: Type.OBJECT,
      properties: {
        tiger_id: {
          type: Type.STRING,
          description: "The tiger's ID, e.g. 'T-052'.",
        },
      },
      required: ["tiger_id"],
    },
  },
  {
    name: "get_gis_context",
    description:
      "Get map context: reserve boundaries, villages, water sources, and tiger territories. Use this for questions about proximity to villages, water, or geographic/territory questions.",
    parameters: { type: Type.OBJECT, properties: {} },
  },
  {
    name: "get_tiger_associations",
    description:
      "Get pairs of tigers ranked by how often they were captured at the same camera station within a short time window of each other - i.e. tigers that are often seen together / share overlapping territory. Use this for questions about which tigers are seen together, overlapping territory, or which tigers could mate (opposite-sex pairs only by default).",
    parameters: {
      type: Type.OBJECT,
      properties: {
        opposite_sex_only: {
          type: Type.BOOLEAN,
          description: "Default true. Set false to include same-sex pairs too (for general 'seen together' questions, not mating).",
        },
      },
    },
  },
];

/**
 * Same tool surface, described in the OpenAI/Groq tool-calling schema
 * (`{ type: "function", function: { name, description, parameters } }`)
 * instead of Gemini's `FunctionDeclaration` shape. Kept as a parallel list
 * rather than converted at runtime so each provider's schema stays exactly
 * what its docs expect.
 */
export const ASSISTANT_TOOLS_OPENAI = [
  {
    type: "function" as const,
    function: {
      name: "get_reserve_stats",
      description:
        "Get reserve-wide KPI counts: total tigers tracked, total/active camera stations, total captures, pending reviews, critical/caution alert counts, core and buffer area size.",
      parameters: { type: "object", properties: {} },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_alerts",
      description:
        "Get real-time conflict alerts and anomalous tiger movements (e.g. a tiger approaching a village boundary). Use this for questions about priority alerts, recent sightings, or which tiger needs attention right now.",
      parameters: {
        type: "object",
        properties: {
          level: {
            type: "string",
            description: "Optional filter: CRITICAL, CAUTION, or SAFE. Omit to get all alerts.",
            enum: ["CRITICAL", "CAUTION", "SAFE"],
          },
          limit: {
            type: "integer",
            description: "Max number of alerts to return, default 10.",
          },
        },
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_camera_stations",
      description:
        "Get camera station data. Omit camera_id to get a compact list of all stations (status, uptime, zone) for 'how many cameras are online' type questions. Pass camera_id to get the full detail for one specific station — habitat, exact coordinates, distance to nearest water/village, trail type.",
      parameters: {
        type: "object",
        properties: {
          camera_id: {
            type: ["string", "null"],
            description: "A specific station's ID, e.g. 'PTR_CAM_026', to get its full detail. Pass null for a list of all stations.",
          },
        },
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_tiger_gallery",
      description:
        "Get the list of all enrolled individual tigers with their last-seen time, home range size, and which stations have spotted them. Use this for 'how many tigers' or general tiger roster questions.",
      parameters: { type: "object", properties: {} },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_tiger_detail",
      description:
        "Get the deep profile for one specific tiger by ID (e.g. 'T-052'): recent captures, home range, last known location. Use this when the ranger asks about a specific named/numbered tiger.",
      parameters: {
        type: "object",
        properties: {
          tiger_id: { type: "string", description: "The tiger's ID, e.g. 'T-052'." },
        },
        required: ["tiger_id"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_gis_context",
      description:
        "Get map context: reserve boundaries, villages, water sources, and tiger territories. Use this for questions about proximity to villages, water, or geographic/territory questions.",
      parameters: { type: "object", properties: {} },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_tiger_associations",
      description:
        "Get pairs of tigers ranked by how often they were captured at the same camera station within a short time window of each other - i.e. tigers that are often seen together / share overlapping territory. Use this for questions about which tigers are seen together, overlapping territory, or which tigers could mate (opposite-sex pairs only by default).",
      parameters: {
        type: "object",
        properties: {
          opposite_sex_only: {
            type: "boolean",
            description: "Default true. Set false to include same-sex pairs too (for general 'seen together' questions, not mating).",
          },
        },
      },
    },
  },
];

export async function runAssistantTool(name: string, args: Record<string, unknown>): Promise<unknown> {
  switch (name) {
    case "get_reserve_stats":
      return api.stats();

    case "get_alerts": {
      const level = typeof args.level === "string" ? args.level : undefined;
      const limit = typeof args.limit === "number" ? args.limit : 10;
      return api.alerts(level, limit);
    }

    case "get_camera_stations": {
      const { stations } = await api.stations();
      const cameraId = typeof args.camera_id === "string" ? args.camera_id : "";

      if (cameraId) {
        const match = stations.find((s) => s.camera_id.toLowerCase() === cameraId.toLowerCase());
        return match ?? { error: `No station found with camera_id ${cameraId}` };
      }

      // A full 300+ row list blows past Groq's free-tier tokens-per-minute
      // cap and isn't what "how many are online" needs anyway — return
      // aggregate counts instead. A single station requested by camera_id
      // above still gets every field.
      const byStatus: Record<string, number> = {};
      const byZone: Record<string, number> = {};
      let uptimeSum = 0;
      for (const s of stations) {
        byStatus[s.operational_status] = (byStatus[s.operational_status] ?? 0) + 1;
        byZone[s.zone] = (byZone[s.zone] ?? 0) + 1;
        uptimeSum += s.uptime_ratio ?? 0;
      }
      return {
        total_stations: stations.length,
        count_by_operational_status: byStatus,
        count_by_zone: byZone,
        average_uptime_ratio: stations.length ? uptimeSum / stations.length : 0,
      };
    }

    case "get_tiger_gallery": {
      const { individuals } = await api.gallery();
      const trimmed = individuals.map((t) => ({
        tiger_id: t.tiger_id,
        name: t.name,
        sex: t.sex,
        life_stage: t.life_stage,
        territorial_status: t.territorial_status,
        mcp_area_km2: t.mcp_area_km2,
        last_seen: t.last_seen,
        stations: t.stations,
      }));
      return { individuals: trimmed, total: trimmed.length };
    }

    case "get_tiger_detail": {
      const tigerId = typeof args.tiger_id === "string" ? args.tiger_id : "";
      if (!tigerId) return { error: "tiger_id is required" };
      const detail = await api.galleryDetail(tigerId);

      // Full detail carries every capture (some tigers have 100+) plus a
      // 512-D embedding vector and pose keypoints - easily blows Groq's
      // free-tier tokens-per-minute cap. The assistant only needs the
      // profile and a handful of recent captures for location questions.
      const captures = Array.isArray(detail.captures) ? detail.captures : [];
      const sorted = [...captures].sort((a, b) => (b.timestamp ?? "").localeCompare(a.timestamp ?? ""));
      const recent = sorted.slice(0, 5).map((c) => ({
        timestamp: c.timestamp,
        camera_id: c.camera_id ?? c.station,
        latitude: c.latitude,
        longitude: c.longitude,
        zone: c.zone,
        alert_level: c.alert_level,
      }));

      return {
        profile: detail.profile,
        total_captures: captures.length,
        last_known_location: recent[0] ?? null,
        recent_captures: recent,
      };
    }

    case "get_tiger_associations": {
      const oppositeSexOnly = typeof args.opposite_sex_only === "boolean" ? args.opposite_sex_only : true;
      return api.tigerAssociations(5, oppositeSexOnly);
    }

    case "get_gis_context": {
      const bundle = await api.gisBundle();
      // Trim the heavy polygon geometry — the assistant only needs names/coords/metadata.
      return {
        metadata: bundle.metadata,
        villages: bundle.villages,
        water_sources: bundle.water_sources,
        territories: Object.fromEntries(
          Object.entries(bundle.territories).map(([id, t]) => [
            id,
            { tiger_id: t.tiger_id, name: t.name, sex: t.sex, life_stage: t.life_stage, centroid: t.centroid, area_km2: t.area_km2 },
          ])
        ),
      };
    }

    default:
      return { error: `Unknown tool: ${name}` };
  }
}
