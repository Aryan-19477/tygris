"use client";

import React, { useState } from "react";
import { Eye, EyeSlash, Crosshair, Sparkle, Tag } from "@phosphor-icons/react";
import { useLanguage } from "@/lib/i18n/LanguageContext";

export interface Keypoint {
  id: number;
  name: string;
  x: number;
  y: number;
  visibility: number; // 0: invisible, 1: occluded, 2: visible
}

export interface PoseSkeletonProps {
  imageSrc?: string | null;
  keypoints?: Keypoint[];
  connections?: [number, number][];
  flankSide?: string;
  confidence?: number;
  width?: number;
  height?: number;
  className?: string;
}

// Canonical ATRW 15-Point Topology Connections. Must match the keypoint ID
// numbering the backend actually assigns (see
// backend/app/ml/pose/pose_extractor.py's POSE_KEYPOINTS_15 /
// SKELETON_CONNECTIONS — 0=Nose, 1/2=Eyes, 3/4=Ears, 5=Neck,
// 6/7=Shoulders, 8/9=Front Paws, 10/11=Hips, 12/13=Back Paws,
// 14=Tail Base), since `keypoints` normally comes straight from that API
// response. This is only the fallback used when the caller doesn't pass its
// own `connections` (as TigerDossierView now does with the backend's
// `pose_analysis.skeleton_connections`).
const DEFAULT_CONNECTIONS: [number, number][] = [
  [0, 1], [0, 2],       // Nose to Eyes
  [1, 3], [2, 4],       // Eyes to Ears
  [1, 5], [2, 5],       // Head to Neck
  [5, 6], [5, 7],       // Neck to Shoulders
  [6, 8], [7, 9],       // Shoulders to Front Paws
  [5, 14],              // Spine: Neck to Tail Base
  [14, 10], [14, 11],   // Tail Base to Hips
  [10, 12], [11, 13],   // Hips to Back Paws
];

export function PoseSkeletonViewer({
  imageSrc,
  keypoints = [],
  connections = DEFAULT_CONNECTIONS,
  flankSide = "Left",
  confidence = 0.98,
  // Matches the fixed 1920x1080 canonical pixel space the backend generates
  // keypoints in (see pose_extractor.py's get_pose_for_image default args) —
  // the SVG viewBox must agree with that space or every keypoint renders
  // far outside the visible frame instead of on the tiger.
  width = 1920,
  height = 1080,
  className = "",
}: PoseSkeletonProps) {
  const { t } = useLanguage();
  const [showSkeleton, setShowSkeleton] = useState(true);
  const [showLabels, setShowLabels] = useState(false);
  const [selectedJoint, setSelectedJoint] = useState<Keypoint | null>(null);

  const activeKeypoints = keypoints && keypoints.length > 0 ? keypoints : [];
  const kpMap = new Map(activeKeypoints.map((k) => [k.id, k]));
  const defaultImage = imageSrc || "/tigers/T103_F.jpg";

  return (
    <div className={`relative overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950 shadow-2xl ${className}`}>
      <div className="flex items-center justify-between border-b border-zinc-800 bg-zinc-900/90 px-4 py-2.5 backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1.5 rounded-full bg-emerald-500/20 px-3 py-0.5 text-xs font-bold text-emerald-300 border border-emerald-500/30">
            <Sparkle size={13} weight="fill" />
            <span>{t("pose.topologyBadge")}</span>
          </div>
          <span className="font-mono text-xs text-zinc-300">
            {t("pose.flankLabel", { side: flankSide, pct: Math.round(confidence * 100) })}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowSkeleton(!showSkeleton)}
            className={`flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-mono font-medium transition-all ${
              showSkeleton
                ? "bg-emerald-600 text-white shadow-sm"
                : "bg-zinc-800 text-zinc-400 hover:text-white"
            }`}
          >
            {showSkeleton ? <Eye size={13} /> : <EyeSlash size={13} />}
            <span>{t("pose.skeleton")}</span>
          </button>

          <button
            onClick={() => setShowLabels(!showLabels)}
            className={`flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-mono font-medium transition-all ${
              showLabels
                ? "bg-emerald-600 text-white shadow-sm"
                : "bg-zinc-800 text-zinc-400 hover:text-white"
            }`}
          >
            <Tag size={13} />
            <span>{t("pose.labels")}</span>
          </button>
        </div>
      </div>

      <div className="relative aspect-16/9 w-full overflow-hidden bg-zinc-950 flex items-center justify-center">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={defaultImage}
          alt="Tiger Camera-Trap Flank"
          className="absolute inset-0 h-full w-full object-cover filter contrast-105"
        />

        <div className="absolute inset-0 bg-gradient-to-t from-zinc-950/70 via-black/10 to-zinc-950/30 pointer-events-none" />

        <svg viewBox={`0 0 ${width} ${height}`} className="absolute inset-0 h-full w-full">
          {showSkeleton && (
            <g className="transition-opacity duration-300">
              {connections.map(([a, b], idx) => {
                const kpA = kpMap.get(a);
                const kpB = kpMap.get(b);
                if (!kpA || !kpB) return null;
                if (kpA.visibility === 0 || kpB.visibility === 0) return null;

                const isSpine = (a === 13 && b === 14) || (a === 14 && b === 11);

                return (
                  <line
                    key={`bone-${idx}`}
                    x1={kpA.x}
                    y1={kpA.y}
                    x2={kpB.x}
                    y2={kpB.y}
                    stroke={isSpine ? "#10b981" : "#06b6d4"}
                    strokeWidth={isSpine ? 3.5 : 2.5}
                    strokeLinecap="round"
                    strokeOpacity={0.9}
                  />
                );
              })}

              {activeKeypoints.map((kp) => {
                if (kp.visibility === 0) return null;

                const isSelected = selectedJoint?.id === kp.id;
                const isHead = kp.id <= 2;
                const isLimb = kp.id === 4 || kp.id === 6 || kp.id === 8 || kp.id === 10;

                return (
                  <g
                    key={`kp-${kp.id}`}
                    className="cursor-pointer group"
                    onClick={() => setSelectedJoint(kp)}
                  >
                    {isSelected && (
                      <circle
                        cx={kp.x}
                        cy={kp.y}
                        r={12}
                        fill="none"
                        stroke="#10b981"
                        strokeWidth={2}
                        className="animate-ping opacity-75"
                      />
                    )}

                    <circle
                      cx={kp.x}
                      cy={kp.y}
                      r={isSelected ? 6.5 : 4.5}
                      fill={isHead ? "#f59e0b" : isLimb ? "#06b6d4" : "#10b981"}
                      stroke="#ffffff"
                      strokeWidth={isSelected ? 2.5 : 1.5}
                      className="transition-transform duration-200 group-hover:scale-150"
                    />

                    {(showLabels || isSelected) && (
                      <g>
                        <rect
                          x={kp.x + 8}
                          y={kp.y - 10}
                          width={kp.name.length * 6.5 + 10}
                          height={18}
                          rx={4}
                          fill="rgba(9, 9, 11, 0.9)"
                          stroke="rgba(255, 255, 255, 0.3)"
                          strokeWidth={1}
                        />
                        <text
                          x={kp.x + 13}
                          y={kp.y + 3}
                          fill="#ffffff"
                          fontSize="9.5"
                          fontFamily="monospace"
                          fontWeight="bold"
                        >
                          {kp.name}
                        </text>
                      </g>
                    )}
                  </g>
                );
              })}
            </g>
          )}
        </svg>

        {selectedJoint && (
          <div className="absolute bottom-3 left-3 flex items-center gap-3 rounded-xl border border-white/20 bg-black/90 px-3.5 py-2 text-xs font-mono text-white backdrop-blur-md shadow-2xl">
            <Crosshair size={15} className="text-emerald-400" />
            <div>
              <span className="font-bold text-emerald-400">#{selectedJoint.id} {selectedJoint.name}</span>
              <span className="text-zinc-400 text-[10px] ml-2">X: {Math.round(selectedJoint.x)}px | Y: {Math.round(selectedJoint.y)}px</span>
            </div>
            <button
              onClick={() => setSelectedJoint(null)}
              className="ml-2 text-zinc-400 hover:text-white"
            >
              ✕
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
