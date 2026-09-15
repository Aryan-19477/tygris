"use client";

import { useMemo, useRef, useState } from "react";
import {
  FilmStrip,
  UploadSimple,
  Star,
  XCircle,
  CheckCircle,
  Spinner,
  Prohibit,
  Leaf,
  ImageBroken,
  PawPrint,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { Card, SectionLabel } from "@/components/ui";
import { api, type Stats, type ScreeningResult, type ScreeningFrame } from "@/lib/api";

const REASON_META: Record<
  string,
  { label: string; blurb: string; icon: typeof XCircle; tone: "good" | "bad" }
> = {
  TIGER_CANDIDATE: {
    label: "Tiger candidate",
    blurb: "Animal detected and coat check passed",
    icon: CheckCircle,
    tone: "good",
  },
  BLANK_IMAGE: {
    label: "Blank frame",
    blurb: "Flat/solid frame — IR glitch or flash burnout",
    icon: ImageBroken,
    tone: "bad",
  },
  NO_ANIMAL: {
    label: "Empty trigger",
    blurb: "Nothing detected — foliage or wind trigger",
    icon: Leaf,
    tone: "bad",
  },
  NON_ANIMAL: {
    label: "Person / vehicle",
    blurb: "Anthropogenic trigger",
    icon: Prohibit,
    tone: "bad",
  },
  NON_TARGET_WILDLIFE: {
    label: "Non-target wildlife",
    blurb: "Animal found but coat check failed",
    icon: PawPrint,
    tone: "bad",
  },
};

type FilterMode = "all" | "kept" | "rejected";

export function Pass1ScreeningView({ stats }: { stats: Stats | null }) {
  const [file, setFile] = useState<File | null>(null);
  const [sampleFps, setSampleFps] = useState(3);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ScreeningResult | null>(null);
  const [filter, setFilter] = useState<FilterMode>("all");
  const inputRef = useRef<HTMLInputElement>(null);

  const run = async () => {
    if (!file) return;
    setRunning(true);
    setError(null);
    setResult(null);
    try {
      setResult(await api.screenVideo(file, sampleFps));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Screening failed.");
    } finally {
      setRunning(false);
    }
  };

  const visibleFrames = useMemo(() => {
    if (!result) return [];
    if (filter === "kept") return result.frames.filter((f) => f.status === "KEPT");
    if (filter === "rejected") return result.frames.filter((f) => f.status === "REJECTED");
    return result.frames;
  }, [result, filter]);

  const keptCount = result?.counts.TIGER_CANDIDATE ?? 0;
  const rejectedCount = result ? result.total_frames_sampled - keptCount : 0;

  return (
    <div>
      <TopBar
        title="Pass 1 Screening"
        subtitle="Upload a clip — blank frames and non-tiger triggers are discarded, then the best frame is selected."
        alertCount={stats?.pending_review ?? 0}
      />

      <div className="px-5 py-6 sm:px-8">
        <Card padding="lg" className="mb-6">
          <SectionLabel icon={<FilmStrip size={13} />} className="mb-4">
            Camera-trap clip
          </SectionLabel>

          <div className="flex flex-col gap-4 sm:flex-row sm:items-end">
            <div className="flex-1">
              <input
                ref={inputRef}
                type="file"
                accept="video/*"
                onChange={(e) => {
                  setFile(e.target.files?.[0] ?? null);
                  setResult(null);
                  setError(null);
                }}
                className="hidden"
              />
              <button
                onClick={() => inputRef.current?.click()}
                className="flex w-full items-center gap-3 rounded-xl border-2 border-dashed border-border-strong bg-surface-sunken px-4 py-4 text-left transition-colors hover:border-accent hover:bg-accent-soft/40"
              >
                <UploadSimple size={20} className="shrink-0 text-muted" />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium text-foreground">
                    {file ? file.name : "Choose a video clip"}
                  </span>
                  <span className="block text-xs text-muted">
                    {file
                      ? `${(file.size / (1024 * 1024)).toFixed(1)} MB`
                      : "MP4, MOV or AVI from a camera-trap trigger"}
                  </span>
                </span>
              </button>
            </div>

            <div className="shrink-0">
              <label className="mb-1.5 block font-mono text-2xs uppercase tracking-wide text-muted">
                Sample rate
              </label>
              <select
                value={sampleFps}
                onChange={(e) => setSampleFps(Number(e.target.value))}
                className="h-[42px] rounded-lg border border-border bg-surface px-3 text-sm text-foreground"
              >
                <option value={1}>1 FPS</option>
                <option value={2}>2 FPS</option>
                <option value={3}>3 FPS</option>
                <option value={5}>5 FPS</option>
              </select>
            </div>

            <button
              onClick={run}
              disabled={!file || running}
              className="flex h-[42px] shrink-0 items-center justify-center gap-2 rounded-lg bg-accent px-5 text-sm font-semibold text-white transition-opacity disabled:opacity-40"
            >
              {running ? (
                <>
                  <Spinner size={15} className="animate-spin" />
                  Screening…
                </>
              ) : (
                "Run Pass 1"
              )}
            </button>
          </div>

          {error && (
            <div className="mt-4 flex items-start gap-2 rounded-lg border border-priority-high/40 bg-priority-high/10 px-3 py-2.5 text-sm text-foreground">
              <XCircle size={16} className="mt-0.5 shrink-0 text-priority-high" />
              <span>{error}</span>
            </div>
          )}
          {running && (
            <p className="mt-4 text-xs text-muted">
              First run downloads the YOLOv8n weights (~7 MB) and may take an extra moment.
            </p>
          )}
        </Card>

        {result && (
          <>
            <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <StatTile label="Frames sampled" value={result.total_frames_sampled} />
              <StatTile label="Kept" value={keptCount} tone="good" />
              <StatTile label="Discarded" value={rejectedCount} tone="bad" />
              <StatTile label="Blank" value={result.counts.BLANK_IMAGE} />
              <StatTile label="Empty trigger" value={result.counts.NO_ANIMAL} />
              <StatTile
                label="Non-target"
                value={result.counts.NON_TARGET_WILDLIFE + result.counts.NON_ANIMAL}
              />
            </div>

            {result.best_frame ? (
              <div className="mb-6 overflow-hidden rounded-xl border-2 border-accent bg-surface">
                <div className="flex items-center gap-2 border-b border-border bg-accent-soft px-5 py-3">
                  <Star size={15} weight="fill" className="text-accent" />
                  <span className="font-mono text-2xs font-semibold uppercase tracking-wide text-accent">
                    Best representative frame
                  </span>
                </div>
                <div className="grid grid-cols-1 gap-5 p-5 lg:grid-cols-[1fr_260px]">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={result.best_frame.full_image ?? result.best_frame.thumbnail}
                    alt="Best frame"
                    className="w-full rounded-lg border border-border object-contain"
                  />
                  <dl className="space-y-3 text-sm">
                    <Detail label="Quality score" value={result.best_frame.quality_score.toFixed(3)} />
                    <Detail label="Timestamp" value={`${result.best_frame.timestamp_sec.toFixed(2)} s`} />
                    <Detail label="Frame index" value={`#${result.best_frame.index}`} />
                    <Detail
                      label="Animal conf."
                      value={result.best_frame.detection_conf.toFixed(3)}
                    />
                  </dl>
                </div>
              </div>
            ) : (
              <div className="mb-6 rounded-xl border border-border bg-surface-sunken px-5 py-8 text-center">
                <p className="text-sm font-medium text-foreground">No usable frame found</p>
                <p className="mt-1 text-xs text-muted">
                  Every sampled frame was blank, empty, or failed the coat check.
                </p>
              </div>
            )}

            <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
              <h2 className="font-serif text-lg font-medium text-foreground">
                Frame-by-frame breakdown
              </h2>
              <div className="flex gap-1 rounded-lg border border-border bg-surface p-1">
                {(["all", "kept", "rejected"] as FilterMode[]).map((m) => (
                  <button
                    key={m}
                    onClick={() => setFilter(m)}
                    className={`rounded px-3 py-1 text-xs font-medium capitalize transition-colors ${
                      filter === m
                        ? "bg-accent-soft text-accent"
                        : "text-muted hover:text-foreground"
                    }`}
                  >
                    {m}
                  </button>
                ))}
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
              {visibleFrames.map((f) => (
                <FrameCard
                  key={f.index}
                  frame={f}
                  isBest={result.best_frame?.index === f.index}
                />
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function StatTile({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone?: "good" | "bad";
}) {
  const color =
    tone === "good" ? "text-accent" : tone === "bad" ? "text-priority-high" : "text-foreground";
  return (
    <div className="rounded-xl border border-border bg-surface px-4 py-3">
      <div className={`font-mono text-2xl font-semibold ${color}`}>{value}</div>
      <div className="mt-0.5 text-2xs text-muted">{label}</div>
    </div>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-border pb-2">
      <dt className="font-mono text-2xs uppercase tracking-wide text-muted">{label}</dt>
      <dd className="font-mono text-sm font-medium text-foreground">{value}</dd>
    </div>
  );
}

function FrameCard({ frame, isBest }: { frame: ScreeningFrame; isBest: boolean }) {
  const meta = REASON_META[frame.reason] ?? {
    label: frame.reason,
    blurb: "",
    icon: XCircle,
    tone: "bad" as const,
  };
  const Icon = meta.icon;
  const good = meta.tone === "good";

  return (
    <div
      className={`overflow-hidden rounded-lg border bg-surface ${
        isBest ? "border-2 border-accent" : good ? "border-accent/30" : "border-border"
      }`}
    >
      <div className="relative">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={frame.thumbnail}
          alt={`Frame ${frame.index}`}
          className={`aspect-video w-full object-cover ${good ? "" : "opacity-45 grayscale"}`}
        />
        {isBest && (
          <span className="absolute left-2 top-2 flex items-center gap-1 rounded-full bg-accent px-2 py-0.5 font-mono text-2xs font-semibold text-white">
            <Star size={10} weight="fill" /> BEST
          </span>
        )}
        <span className="absolute right-2 top-2 rounded bg-black/65 px-1.5 py-0.5 font-mono text-2xs text-white">
          {frame.timestamp_sec.toFixed(1)}s
        </span>
      </div>
      <div className="px-3 py-2.5">
        <div
          className={`flex items-center gap-1.5 font-mono text-2xs font-semibold uppercase tracking-wide ${
            good ? "text-accent" : "text-priority-high"
          }`}
        >
          <Icon size={12} weight="fill" />
          {meta.label}
        </div>
        <p className="mt-1 text-[11px] leading-snug text-muted">{meta.blurb}</p>
        {frame.status === "KEPT" && (
          <div className="mt-1.5 font-mono text-[11px] text-foreground">
            Q {frame.quality_score.toFixed(3)}
          </div>
        )}
      </div>
    </div>
  );
}
