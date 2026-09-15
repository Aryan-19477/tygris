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
import { Card, SectionLabel, Pill } from "@/components/ui";
import { PoseSkeletonViewer } from "@/components/PoseSkeletonViewer";
import { SightingWindowSlider, EmptySightingState } from "@/components/SightingWindowSlider";
import { api, type GalleryDetail, type Stats } from "@/lib/api";
import { useLanguage } from "@/lib/i18n/LanguageContext";

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

function formatDate(iso: string | null, unknownLabel: string) {
  if (!iso) return unknownLabel;
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
  const { t } = useLanguage();
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
        title={t("dossier.title", { name: profile?.name || tigerId })}
        subtitle={t("dossier.subtitle")}
        alertCount={stats?.pending_review ?? 0}
        right={
          <div className="flex items-center gap-2">
            {onNavigateToMap && (
              <button
                onClick={() => onNavigateToMap(tigerId)}
                className="flex items-center gap-1.5 rounded-full bg-accent px-3.5 py-1.5 text-xs font-mono font-bold text-accent-foreground shadow-sm hover:opacity-90"
              >
                <Compass size={14} />
                <span>{t("dossier.focusOnMap")}</span>
              </button>
            )}
            <button
              onClick={onBack}
              className="flex items-center gap-1.5 rounded-full border border-border px-3.5 py-1.5 text-xs font-medium text-foreground hover:bg-surface"
            >
              <ArrowLeft size={14} />
              <span>{t("dossier.back")}</span>
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
                    (e.target as HTMLImageElement).src = "/tigers/T103_F.jpg";
                  }}
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-black/10" />
                <div className="absolute top-3 left-3 flex items-center gap-2 rounded-full bg-black/70 px-3 py-1 text-2xs font-mono font-bold text-white backdrop-blur-md border border-white/20">
                  <span
                    className="h-2.5 w-2.5 rounded-full ring-2 ring-white/50"
                    style={{ backgroundColor: `hsl(${hue}, 65%, 45%)` }}
                  />
                  <span>{profile?.territorial_status || t("dossier.residentDefault")}</span>
                </div>
              </div>

              <div className="p-5 space-y-4">
                <div>
                  <div className="font-mono text-xl font-bold text-foreground">{tigerId}</div>
                  <div className="text-xs text-muted font-mono mt-0.5">
                    {profile?.name || t("dossier.defaultProfileName")} • {profile?.sex || "FEMALE"} • {profile?.age_years?.toFixed(1) || 4.5}y
                  </div>
                </div>

                <div className="space-y-2.5 border-t border-border pt-3 text-xs font-mono">
                  <BioRow icon={Compass} label={t("dossier.homeRange")} value={`${profile?.mcp_area_km2 || 38.5} km²`} highlight />
                  <BioRow icon={Calendar} label={t("dossier.firstRecorded")} value={firstSeen ? formatDate(firstSeen.timestamp, t("common.unknownDate")) : "—"} />
                  <BioRow icon={Calendar} label={t("dossier.lastRecorded")} value={lastSeen ? formatDate(lastSeen.timestamp, t("common.unknownDate")) : "—"} />
                  <BioRow icon={MapPin} label={t("dossier.primaryStation")} value={stationHistory[0]?.[0] || "—"} />
                  <BioRow icon={PawPrint} label={t("dossier.totalSightings")} value={t("dossier.totalSightingsValue", { count: timeline.length })} />
                </div>
              </div>
            </div>

            {stationHistory.length > 0 && (
              <Card padding="lg" className="shadow-sm">
                <SectionLabel className="mb-3">{t("dossier.cameraEncounters")}</SectionLabel>
                <div className="space-y-2.5">
                  {stationHistory.slice(0, 5).map(([station, count]) => {
                    const max = stationHistory[0][1];
                    return (
                      <div key={station}>
                        <div className="mb-1 flex items-center justify-between font-mono text-xs">
                          <span className="font-bold text-foreground">{station}</span>
                          <span className="text-muted">{t("dossier.capturesCount", { count })}</span>
                        </div>
                        <div className="h-1.5 overflow-hidden rounded-full bg-surface-sunken">
                          <div className="h-full rounded-full bg-accent" style={{ width: `${(count / max) * 100}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              </Card>
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
                <span>{t("dossier.tabTimeline", { count: timeline.length })}</span>
              </button>
              <button
                onClick={() => setActiveTab("pose")}
                className={`flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-bold transition-all ${
                  activeTab === "pose" ? "bg-accent text-accent-foreground shadow-sm" : "text-muted hover:text-foreground"
                }`}
              >
                <Sparkle size={14} />
                <span>{t("dossier.tabPose")}</span>
              </button>
              <button
                onClick={() => setActiveTab("barcode")}
                className={`flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-bold transition-all ${
                  activeTab === "barcode" ? "bg-accent text-accent-foreground shadow-sm" : "text-muted hover:text-foreground"
                }`}
              >
                <Barcode size={14} />
                <span>{t("dossier.tabBarcode")}</span>
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
                      >
                        <Card padding="md" className="flex items-center justify-between shadow-sm">
                          <div className="flex items-center gap-3.5">
                            <div
                              className="h-3 w-3 rounded-full ring-2 ring-border-strong"
                              style={{ backgroundColor: `hsl(${hue}, 65%, 45%)` }}
                            />
                            <div>
                              <div className="font-mono text-xs font-bold text-foreground">
                                {c.camera_id || c.station || t("common.unknownStation")}
                              </div>
                              <div className="text-2xs font-mono text-muted mt-0.5">
                                {formatDate(c.timestamp, t("common.unknownDate"))} • {t("dossier.zoneLabel", { zone: c.zone || "CORE" })} • {t("dossier.flankLabel", { flank: c.flank_side || "Left" })}
                              </div>
                            </div>
                          </div>
                          <Pill
                            tone={isCrit ? "danger" : isCaut ? "caution" : "positive"}
                            className={`px-2.5 py-0.5 border ${
                              isCrit ? "border-danger/40" : isCaut ? "border-caution/40" : "border-positive/40"
                            }`}
                          >
                            {isCrit ? t("attention.urgencyCritical") : isCaut ? t("attention.urgencyCaution") : t("common.safe")}
                          </Pill>
                        </Card>
                      </motion.div>
                    );
                  }}
                />
              )
            )}

            {activeTab === "pose" && (
              <div className="space-y-4">
                <div className="text-xs font-mono text-muted">
                  {t("dossier.poseExplainer")}
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
              <Card padding="lg" className="space-y-5 shadow-sm">
                <div>
                  <div className="font-mono text-sm font-bold text-foreground">
                    {t("dossier.barcodeTitle", { dim: detail?.embedding?.dim ?? 512 })}
                  </div>
                  <div className="text-xs text-muted font-mono mt-1">
                    {t("dossier.barcodeDesc")}
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
                        <span>{t("dossier.positiveActivation")}</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="h-2 w-2 rounded-full bg-accent-strong" />
                        <span>{t("dossier.negativeSuppression")}</span>
                      </div>
                      <span>{t("dossier.l2Norm", { value: (detail.embedding.l2_norm ?? 0).toFixed(3) })}</span>
                    </div>
                    <div className="text-2xs font-mono text-muted">
                      {t("dossier.extractedFrom", {
                        count: detail.embedding.num_source_entries ?? 0,
                        unit: detail.embedding.num_source_entries === 1 ? t("dossier.photoSingular") : t("dossier.photoPlural"),
                      })}
                    </div>
                  </>
                ) : (
                  <div className="rounded-xl border border-dashed border-border-strong p-6 text-center text-xs font-mono text-muted space-y-2">
                    <div className="font-bold text-foreground">{t("dossier.noEmbedding")}</div>
                    <div className="leading-relaxed">
                      {detail?.embedding?.detail || t("dossier.noEmbeddingDetailFallback")}
                    </div>
                  </div>
                )}
              </Card>
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
