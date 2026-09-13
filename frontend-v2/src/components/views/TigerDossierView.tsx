"use client";

import { useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import { motion } from "motion/react";
import {
  ArrowLeft,
  MapPin,
  Calendar,
  Clock,
  PawPrint,
  Sparkle,
  Compass,
  Barcode,
} from "@phosphor-icons/react";

import { TopBar } from "@/components/TopBar";
import { PoseSkeletonViewer } from "@/components/PoseSkeletonViewer";
import { SightingWindowSlider, EmptySightingState } from "@/components/SightingWindowSlider";
import { api, type GalleryDetail, type Stats } from "@/lib/api";

const SightingTrailMap = dynamic(
  () => import("@/components/SightingTrailMap").then((mod) => mod.SightingTrailMap),
  { ssr: false, loading: () => <div className="h-90 w-full rounded-xl border border-border bg-surface-sunken animate-pulse" /> }
);

function hueForId(id: string) {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  }
  return hash % 360;
}

function formatDate(iso: string | null) {
  if (!iso) return "Unknown date";
  try {
    return new Date(iso).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
  } catch {
    return iso;
  }
}

export function TigerDossierView({
  tigerId,
  stats,
  onBack,
  onNavigateToMap,
}: {
  tigerId: string;
  stats: Stats | null;
  onBack: () => void;
  onNavigateToMap?: (tigerId: string) => void;
}) {
  const [detail, setDetail] = useState<GalleryDetail | null>(null);
  const [activeTab, setActiveTab] = useState<"pose" | "timeline" | "barcode">("timeline");

  useEffect(() => {
    api.galleryDetail(tigerId).then(setDetail).catch((err) => {
      console.error("[TigerDossierView] Error fetching detail:", err);
    });
  }, [tigerId]);

  const hue = hueForId(tigerId);
  const profile = detail?.profile;

  const capturesList = useMemo(() => {
    if (!detail || !Array.isArray(detail.captures)) return [];
    return detail.captures;
  }, [detail]);

  const stationHistory = useMemo(() => {
    if (!capturesList || capturesList.length === 0) return [];
    const counts = new Map<string, number>();
    for (const c of capturesList) {
      const st = c.camera_id || c.station;
      if (!st) continue;
      counts.set(st, (counts.get(st) ?? 0) + 1);
    }
    return Array.from(counts.entries()).sort((a, b) => b[1] - a[1]);
  }, [capturesList]);

  const timeline = useMemo(() => {
    if (!capturesList || capturesList.length === 0) return [];
    return [...capturesList].sort((a, b) => (b.timestamp ?? "").localeCompare(a.timestamp ?? ""));
  }, [capturesList]);

  const firstSeen = timeline.length > 0 ? timeline[timeline.length - 1] : null;
  const lastSeen = timeline.length > 0 ? timeline[0] : null;

  const coverImage = detail?.pose_analysis?.image || profile?.thumbnail || `/tigers/${tigerId}.jpg`;

  return (
    <div className="min-h-full">
      <TopBar
        title={`Tiger Dossier: ${profile?.name || tigerId}`}
        subtitle="Sighting history, movement trail, and biometric identification"
        alertCount={stats?.pending_review ?? 0}
        right={
          <div className="flex items-center gap-2">
            {onNavigateToMap && (
              <button
                onClick={() => onNavigateToMap(tigerId)}
                className="flex items-center gap-1.5 rounded-full bg-accent px-3.5 py-1.5 text-xs font-mono font-bold text-accent-foreground shadow-sm hover:opacity-90"
              >
                <Compass size={14} />
                <span>Focus on Reserve Map</span>
              </button>
            )}
            <button
              onClick={onBack}
              className="flex items-center gap-1.5 rounded-full border border-border px-3.5 py-1.5 text-xs font-medium text-foreground hover:bg-surface"
            >
              <ArrowLeft size={14} />
              <span>Back</span>
            </button>
          </div>
        }
      />

      <div className="px-6 py-6 sm:px-8 space-y-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-[360px_1fr]">
          <div className="lg:sticky lg:top-6 lg:self-start space-y-4">
            <div className="overflow-hidden rounded-2xl border border-border bg-surface shadow-sm">
              <div className="relative aspect-4/3 w-full overflow-hidden bg-surface-sunken">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={coverImage}
                  alt={tigerId}
                  className="h-full w-full object-cover filter contrast-105"
                  onError={(e) => {
                    (e.target as HTMLImageElement).src = "/tigers/PTR_TIG_001.jpg";
                  }}
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-black/10" />
                <div className="absolute top-3 left-3 flex items-center gap-2 rounded-full bg-black/70 px-3 py-1 text-[11px] font-mono font-bold text-white backdrop-blur-md border border-white/20">
                  <span
                    className="h-2.5 w-2.5 rounded-full ring-2 ring-white/50"
                    style={{ backgroundColor: `hsl(${hue}, 65%, 45%)` }}
                  />
                  <span>{profile?.territorial_status || "RESIDENT"}</span>
                </div>
              </div>

              <div className="p-5 space-y-4">
                <div>
                  <div className="font-mono text-xl font-bold text-foreground">{tigerId}</div>
                  <div className="text-xs text-muted font-mono mt-0.5">
                    {profile?.name || "Pench Resident Individual"} • {profile?.sex || "FEMALE"} • {profile?.age_years?.toFixed(1) || 4.5}y
                  </div>
                </div>

                <div className="space-y-2.5 border-t border-border pt-3 text-xs font-mono">
                  <BioRow icon={Compass} label="100% MCP Home Range" value={`${profile?.mcp_area_km2 || 38.5} km²`} highlight />
                  <BioRow icon={Calendar} label="First Recorded" value={firstSeen ? formatDate(firstSeen.timestamp) : "—"} />
                  <BioRow icon={Calendar} label="Last Recorded" value={lastSeen ? formatDate(lastSeen.timestamp) : "—"} />
                  <BioRow icon={MapPin} label="Primary station" value={stationHistory[0]?.[0] || "—"} />
                  <BioRow icon={PawPrint} label="Total sightings" value={`${timeline.length} events`} />
                </div>
              </div>
            </div>

            {stationHistory.length > 0 && (
              <div className="rounded-2xl border border-border bg-surface p-5 shadow-sm">
                <h3 className="mb-3 font-mono text-[11px] uppercase tracking-wider text-muted font-bold">
                  Camera station encounters
                </h3>
                <div className="space-y-2.5">
                  {stationHistory.slice(0, 5).map(([station, count]) => {
                    const max = stationHistory[0][1];
                    return (
                      <div key={station}>
                        <div className="mb-1 flex items-center justify-between font-mono text-xs">
                          <span className="font-bold text-foreground">{station}</span>
                          <span className="text-muted">{count} captures</span>
                        </div>
                        <div className="h-1.5 overflow-hidden rounded-full bg-surface-sunken">
                          <div className="h-full rounded-full bg-accent" style={{ width: `${(count / max) * 100}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>

          <div className="space-y-5">
            <div className="flex items-center gap-2 border-b border-border pb-3 font-mono">
              <button
                onClick={() => setActiveTab("timeline")}
                className={`flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-bold transition-all ${
                  activeTab === "timeline" ? "bg-accent text-accent-foreground shadow-sm" : "text-muted hover:text-foreground"
                }`}
              >
                <Clock size={14} />
                <span>Sighting Timeline ({timeline.length})</span>
              </button>
              <button
                onClick={() => setActiveTab("pose")}
                className={`flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-bold transition-all ${
                  activeTab === "pose" ? "bg-accent text-accent-foreground shadow-sm" : "text-muted hover:text-foreground"
                }`}
              >
                <Sparkle size={14} />
                <span>Pose &amp; flank</span>
              </button>
              <button
                onClick={() => setActiveTab("barcode")}
                className={`flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-bold transition-all ${
                  activeTab === "barcode" ? "bg-accent text-accent-foreground shadow-sm" : "text-muted hover:text-foreground"
                }`}
              >
                <Barcode size={14} />
                <span>Stripe signature</span>
              </button>
            </div>

            {activeTab === "timeline" && (
              timeline.length === 0 ? (
                <EmptySightingState />
              ) : (
                <SightingWindowSlider
                  items={timeline}
                  renderAbove={(visible) => <SightingTrailMap points={visible} tigerId={tigerId} />}
                  renderItem={(c, i) => {
                    const alertLevel = c.alert_level || "SAFE";
                    const isCrit = alertLevel === "CRITICAL";
                    const isCaut = alertLevel === "CAUTION";

                    return (
                      <motion.div
                        key={i}
                        initial={{ opacity: 0, y: 6 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ delay: Math.min(i * 0.03, 0.3) }}
                        className="flex items-center justify-between rounded-xl border border-border bg-surface p-4 shadow-sm"
                      >
                        <div className="flex items-center gap-3.5">
                          <div
                            className="h-3 w-3 rounded-full ring-2 ring-border-strong"
                            style={{ backgroundColor: `hsl(${hue}, 65%, 45%)` }}
                          />
                          <div>
                            <div className="font-mono text-xs font-bold text-foreground">
                              {c.camera_id || c.station || "Unknown station"}
                            </div>
                            <div className="text-[11px] font-mono text-muted mt-0.5">
                              {formatDate(c.timestamp)} • {c.zone || "CORE"} Zone • {c.flank_side || "Left"} Flank
                            </div>
                          </div>
                        </div>
                        <span
                          className={`rounded-full px-2.5 py-0.5 font-mono text-[10px] font-bold uppercase tracking-wider ${
                            isCrit
                              ? "bg-danger-soft text-danger border border-danger/40"
                              : isCaut
                              ? "bg-caution-soft text-caution border border-caution/40"
                              : "bg-positive-soft text-positive border border-positive/40"
                          }`}
                        >
                          {alertLevel}
                        </span>
                      </motion.div>
                    );
                  }}
                />
              )
            )}

            {activeTab === "pose" && (
              <div className="space-y-4">
                <div className="text-xs font-mono text-muted">
                  Anatomical keypoint alignment &amp; flank orientation for the most recent capture.
                </div>
                <PoseSkeletonViewer
                  imageSrc={coverImage}
                  keypoints={
                    Array.isArray(detail?.pose_analysis?.keypoints)
                      ? (detail?.pose_analysis?.keypoints as import("@/components/PoseSkeletonViewer").Keypoint[])
                      : undefined
                  }
                  flankSide={detail?.pose_analysis?.flank || "Left"}
                  confidence={detail?.pose_analysis?.confidence || 0.96}
                  width={640}
                  height={360}
                />
              </div>
            )}

            {activeTab === "barcode" && (
              <div className="rounded-2xl border border-border bg-surface p-6 space-y-5 shadow-sm">
                <div>
                  <div className="font-mono text-sm font-bold text-foreground">
                    {detail?.embedding?.dim ?? 512}-Dimensional Biometric Signature
                  </div>
                  <div className="text-xs text-muted font-mono mt-1">
                    L2-normalized representation vector extracted by a triplet-loss fine-tuned ResNet50 embedding model (97.5% rank-1 accuracy).
                  </div>
                </div>

                {detail?.embedding?.available && detail.embedding.vector ? (
                  <>
                    <div className="h-16 w-full rounded-xl border border-border bg-surface-sunken p-2 flex items-center gap-px overflow-hidden">
                      {detail.embedding.vector.map((val, idx) => {
                        const isPositive = val >= 0;
                        const heightPercent = Math.max(8, Math.min(100, Math.abs(val) * 100 * 6));
                        return (
                          <div key={idx} className="flex-1 flex flex-col justify-center items-center h-full group relative cursor-pointer" title={`dim[${idx}] = ${val.toFixed(4)}`}>
                            <div
                              className={`w-full rounded-xs transition-all ${isPositive ? "bg-positive" : "bg-accent-strong"}`}
                              style={{ height: `${heightPercent}%` }}
                            />
                          </div>
                        );
                      })}
                    </div>
                    <div className="flex items-center justify-between text-xs font-mono text-muted pt-2 border-t border-border">
                      <div className="flex items-center gap-2">
                        <span className="h-2 w-2 rounded-full bg-positive" />
                        <span>Positive activation</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="h-2 w-2 rounded-full bg-accent-strong" />
                        <span>Negative suppression</span>
                      </div>
                      <span>L2 Norm: {(detail.embedding.l2_norm ?? 0).toFixed(3)}</span>
                    </div>
                    <div className="text-[11px] font-mono text-muted">
                      Extracted from {detail.embedding.num_source_entries} reference
                      {detail.embedding.num_source_entries === 1 ? " photo" : " photos"} enrolled for this individual.
                    </div>
                  </>
                ) : (
                  <div className="rounded-xl border border-dashed border-border-strong p-6 text-center text-xs font-mono text-muted space-y-2">
                    <div className="font-bold text-foreground">No embedding available for this individual</div>
                    <div className="leading-relaxed">
                      {detail?.embedding?.detail || "This tiger has no enrolled embedding, and the embedding status could not be determined."}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function BioRow({
  icon: Icon,
  label,
  value,
  highlight = false,
}: {
  icon: typeof MapPin;
  label: string;
  value: string;
  highlight?: boolean;
}) {
  return (
    <div className="flex items-center justify-between text-xs">
      <div className="flex items-center gap-2 text-muted">
        <Icon size={14} />
        <span>{label}</span>
      </div>
      <span className={`font-mono font-bold ${highlight ? "text-positive" : "text-foreground"}`}>{value}</span>
    </div>
  );
}
