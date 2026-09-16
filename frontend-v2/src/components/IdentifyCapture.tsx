"use client";

import { useCallback, useRef, useState } from "react";
import {
  UploadSimple,
  Sparkle,
  CheckCircle,
  WarningCircle,
  ArrowClockwise,
  UserPlus,
  FilmStrip,
  Image as ImageIcon,
  Star,
  CaretDown,
} from "@phosphor-icons/react";
import { api, type IdentifyResult, type ScreeningResult } from "@/lib/api";
import { useLanguage } from "@/lib/i18n/LanguageContext";

type Phase = "idle" | "screening" | "identifying" | "result" | "noFrame" | "error";

async function dataUrlToFile(dataUrl: string, name: string): Promise<File> {
  const blob = await (await fetch(dataUrl)).blob();
  return new File([blob], name, { type: blob.type || "image/jpeg" });
}

/**
 * One upload box for both photos and videos. A video is run through Pass 1
 * screening first and its best frame is sent on to identification; a photo
 * goes straight to identification.
 */
export function IdentifyCapture({ stationId }: { stationId?: string }) {
  const { t } = useLanguage();
  const [phase, setPhase] = useState<Phase>("idle");
  const [result, setResult] = useState<IdentifyResult | null>(null);
  const [screening, setScreening] = useState<ScreeningResult | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [isVideo, setIsVideo] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [showFrames, setShowFrames] = useState(false);
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const reset = () => {
    setPhase("idle");
    setResult(null);
    setScreening(null);
    setPreview(null);
    setErrorMsg(null);
    setShowFrames(false);
  };

  const run = useCallback(
    async (file: File) => {
      const video = file.type.startsWith("video/");
      setIsVideo(video);
      setResult(null);
      setScreening(null);
      setErrorMsg(null);
      try {
        let imageFile = file;
        if (video) {
          setPreview(null);
          setPhase("screening");
          const screen = await api.screenVideo(file, 3);
          setScreening(screen);
          const best = screen.best_frame;
          if (!best) {
            setPhase("noFrame");
            return;
          }
          const src = best.full_image ?? best.thumbnail;
          setPreview(src);
          imageFile = await dataUrlToFile(src, `best_frame_${best.index}.jpg`);
        } else {
          setPreview(URL.createObjectURL(file));
        }
        setPhase("identifying");
        setResult(await api.identify(imageFile, stationId));
        setPhase("result");
      } catch (e) {
        setErrorMsg(e instanceof Error ? e.message : null);
        setPhase("error");
      }
    },
    [stationId]
  );

  const handleFiles = useCallback(
    (files: FileList | null) => {
      const file = files?.[0];
      if (file) run(file);
    },
    [run]
  );

  const isKnown = result?.status === "KNOWN";
  const kept = screening?.counts.TIGER_CANDIDATE ?? 0;
  const discarded = screening ? screening.total_frames_sampled - kept : 0;

  return (
    <div>
      {phase === "idle" && (
        <div
          onDragOver={(e) => {
            e.preventDefault();
            setDragOver(true);
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={(e) => {
            e.preventDefault();
            setDragOver(false);
            handleFiles(e.dataTransfer.files);
          }}
          onClick={() => inputRef.current?.click()}
          className={`flex min-h-64 cursor-pointer flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed px-4 text-center transition-colors ${
            dragOver ? "border-accent bg-accent-soft" : "border-border-strong hover:border-accent/50"
          }`}
        >
          <input
            ref={inputRef}
            type="file"
            accept="image/*,video/*"
            className="hidden"
            onChange={(e) => {
              handleFiles(e.target.files);
              e.target.value = "";
            }}
          />
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-accent-soft text-accent">
            <UploadSimple size={20} weight="bold" />
          </div>
          <p className="text-sm font-medium text-foreground">{t("identifyCapture.dropTitle")}</p>
          <p className="text-xs text-muted">{t("identifyCapture.dropSub")}</p>
          <div className="mt-1 flex flex-wrap justify-center gap-2 text-[11px] text-muted">
            <span className="flex items-center gap-1 rounded-full border border-border px-2.5 py-1">
              <ImageIcon size={12} /> {t("identifyCapture.photoHint")}
            </span>
            <span className="flex items-center gap-1 rounded-full border border-border px-2.5 py-1">
              <FilmStrip size={12} /> {t("identifyCapture.videoHint")}
            </span>
          </div>
        </div>
      )}

      {(phase === "screening" || phase === "identifying") && (
        <div className="flex min-h-64 flex-col items-center justify-center gap-5">
          {isVideo && <Steps phase={phase} t={t} />}
          <div className="flex h-12 w-12 animate-spin items-center justify-center rounded-full bg-accent-soft text-accent">
            <Sparkle size={20} weight="fill" />
          </div>
          <p className="text-sm font-medium text-foreground">
            {phase === "screening" ? t("identifyCapture.screening") : t("identifyCapture.identifying")}
          </p>
          {phase === "screening" && (
            <p className="max-w-xs text-center text-xs text-muted">{t("identifyCapture.screeningSub")}</p>
          )}
        </div>
      )}

      {phase === "error" && (
        <div className="flex min-h-64 flex-col items-center justify-center gap-3 rounded-xl border border-danger/30 bg-danger-soft px-4 text-center">
          <WarningCircle size={26} className="text-danger" />
          <p className="text-sm font-medium text-danger">{t("identifyCapture.errorTitle")}</p>
          {errorMsg && <p className="font-mono text-[11px] text-muted">{errorMsg}</p>}
          <button
            onClick={reset}
            className="rounded-full border border-border-strong px-3.5 py-1.5 text-sm font-medium text-foreground hover:bg-surface"
          >
            {t("identifyCapture.tryAgain")}
          </button>
        </div>
      )}

      {phase === "noFrame" && screening && (
        <div className="flex flex-col gap-4">
          <ScreeningSummary sampled={screening.total_frames_sampled} kept={kept} discarded={discarded} t={t} />
          <div className="flex flex-col items-center gap-2 rounded-xl border border-caution/30 bg-caution-soft px-4 py-8 text-center">
            <WarningCircle size={24} className="text-caution" />
            <p className="text-sm font-medium text-foreground">{t("identifyCapture.noFrameTitle")}</p>
            <p className="text-xs text-muted">{t("identifyCapture.noFrameSub")}</p>
          </div>
          <FramesToggle screening={screening} open={showFrames} onToggle={() => setShowFrames((v) => !v)} t={t} />
          <UploadAnother onClick={reset} t={t} />
        </div>
      )}

      {phase === "result" && result && (
        <div className="flex flex-col gap-4">
          {screening && (
            <ScreeningSummary sampled={screening.total_frames_sampled} kept={kept} discarded={discarded} t={t} />
          )}

          {preview && (
            <div className="relative overflow-hidden rounded-xl border border-border bg-surface-sunken">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={preview} alt="" className="max-h-80 w-full object-contain" />
              {screening?.best_frame && (
                <span className="absolute left-3 top-3 flex items-center gap-1 rounded-full bg-accent px-2.5 py-1 font-mono text-[10px] font-semibold uppercase tracking-wide text-white">
                  <Star size={10} weight="fill" />
                  {t("identifyCapture.bestFrame", { sec: screening.best_frame.timestamp_sec.toFixed(1) })}
                </span>
              )}
            </div>
          )}

          <div
            className={`flex items-center gap-3 rounded-xl border p-4 ${
              isKnown ? "border-positive/30 bg-positive-soft" : "border-caution/30 bg-caution-soft"
            }`}
          >
            <div
              className={`flex h-10 w-10 items-center justify-center rounded-lg ${
                isKnown ? "bg-positive text-background" : "bg-caution text-background"
              }`}
            >
              {isKnown ? <CheckCircle size={20} weight="fill" /> : <WarningCircle size={20} weight="fill" />}
            </div>
            <div className="flex-1">
              <div className="font-mono text-[11px] uppercase tracking-wide text-muted">
                {isKnown ? t("identifyCapture.confidentMatch") : t("identifyCapture.needsDecision")}
              </div>
              <div className="text-lg font-semibold text-foreground">
                {isKnown ? result.tiger_id : result.predicted_tiger_id || t("identifyCapture.unrecognized")}
              </div>
            </div>
            <div className="text-right font-mono text-xs text-muted">
              <div>{t("identifyCapture.similarity", { pct: Math.round(result.confidence * 100) })}</div>
              <div>{t("identifyCapture.vsEnrolled", { count: result.gallery_size })}</div>
            </div>
          </div>

          {!isKnown && result.candidates && result.candidates.length > 0 && (
            <div className="flex flex-col gap-2">
              <div className="font-mono text-[11px] uppercase tracking-wide text-muted">
                {t("attention.closestCandidates")}
              </div>
              {result.candidates.slice(0, 3).map((c) => (
                <div
                  key={c.tiger_id}
                  className="flex items-center gap-3 rounded-lg border border-border px-3 py-2.5"
                >
                  <span className="font-mono text-sm font-medium text-foreground">{c.tiger_id}</span>
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-sunken">
                    <div className="h-full rounded-full bg-accent" style={{ width: `${c.similarity * 100}%` }} />
                  </div>
                  <span className="w-10 text-right font-mono text-xs text-muted">
                    {(c.similarity * 100).toFixed(0)}%
                  </span>
                </div>
              ))}
              <div className="mt-1 flex items-start gap-2 rounded-xl border border-caution/30 bg-caution-soft p-3 text-xs text-caution">
                <UserPlus size={15} className="mt-0.5 shrink-0" />
                <span>{t("identifyCapture.noCandidateWarning")}</span>
              </div>
            </div>
          )}

          {result.recorded_status === "SAVED_TO_GRAPH" && (
            <div className="flex items-center gap-2 rounded-lg bg-surface-sunken px-3 py-2 font-mono text-[11px] text-muted">
              <CheckCircle size={13} className="text-positive" />
              <span>{t("identifyCapture.sightingLogged", { id: result.recorded_event_id ?? "" })}</span>
            </div>
          )}

          {screening && (
            <FramesToggle screening={screening} open={showFrames} onToggle={() => setShowFrames((v) => !v)} t={t} />
          )}

          <UploadAnother onClick={reset} t={t} />
        </div>
      )}
    </div>
  );
}

type T = (key: string, vars?: Record<string, string | number>) => string;

function Steps({ phase, t }: { phase: "screening" | "identifying"; t: T }) {
  const steps = [
    { id: "screening", label: t("identifyCapture.stepScreen") },
    { id: "identifying", label: t("identifyCapture.stepIdentify") },
  ];
  const activeIdx = phase === "screening" ? 0 : 1;
  return (
    <div className="flex items-center gap-2 text-xs">
      {steps.map((s, i) => (
        <div key={s.id} className="flex items-center gap-2">
          <span
            className={`flex h-5 w-5 items-center justify-center rounded-full font-mono text-[10px] font-semibold ${
              i < activeIdx
                ? "bg-positive text-background"
                : i === activeIdx
                ? "bg-accent text-white"
                : "bg-surface-sunken text-muted"
            }`}
          >
            {i < activeIdx ? <CheckCircle size={12} weight="fill" /> : i + 1}
          </span>
          <span className={i === activeIdx ? "font-medium text-foreground" : "text-muted"}>{s.label}</span>
          {i < steps.length - 1 && <span className="h-px w-6 bg-border-strong" />}
        </div>
      ))}
    </div>
  );
}

function ScreeningSummary({
  sampled,
  kept,
  discarded,
  t,
}: {
  sampled: number;
  kept: number;
  discarded: number;
  t: T;
}) {
  return (
    <div className="grid grid-cols-3 gap-2">
      <Tile label={t("identifyCapture.framesSampled")} value={sampled} />
      <Tile label={t("identifyCapture.framesKept")} value={kept} className="text-positive" />
      <Tile label={t("identifyCapture.framesDiscarded")} value={discarded} className="text-danger" />
    </div>
  );
}

function Tile({ label, value, className = "text-foreground" }: { label: string; value: number; className?: string }) {
  return (
    <div className="rounded-lg border border-border bg-surface px-3 py-2">
      <div className={`font-mono text-lg font-semibold ${className}`}>{value}</div>
      <div className="text-[11px] text-muted">{label}</div>
    </div>
  );
}

function FramesToggle({
  screening,
  open,
  onToggle,
  t,
}: {
  screening: ScreeningResult;
  open: boolean;
  onToggle: () => void;
  t: T;
}) {
  return (
    <div className="rounded-xl border border-border">
      <button
        onClick={onToggle}
        className="flex w-full items-center justify-between px-3.5 py-2.5 text-xs font-medium text-foreground"
      >
        <span className="flex items-center gap-1.5">
          <FilmStrip size={14} className="text-muted" />
          {t("identifyCapture.viewFrames")}
        </span>
        <CaretDown size={12} className={`text-muted transition-transform ${open ? "rotate-180" : ""}`} />
      </button>
      {open && (
        <div className="grid grid-cols-3 gap-2 border-t border-border p-3 sm:grid-cols-4">
          {screening.frames.map((f) => {
            const good = f.status === "KEPT";
            const best = screening.best_frame?.index === f.index;
            return (
              <div
                key={f.index}
                className={`relative overflow-hidden rounded-md border ${best ? "border-2 border-accent" : "border-border"}`}
                title={f.reason.replace(/_/g, " ").toLowerCase()}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={f.thumbnail}
                  alt=""
                  className={`aspect-video w-full object-cover ${good ? "" : "opacity-40 grayscale"}`}
                />
                <span className="absolute bottom-1 right-1 rounded bg-black/65 px-1 font-mono text-[9px] text-white">
                  {f.timestamp_sec.toFixed(1)}s
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function UploadAnother({ onClick, t }: { onClick: () => void; t: T }) {
  return (
    <button
      onClick={onClick}
      className="flex items-center justify-center gap-1.5 rounded-full border border-border-strong px-3.5 py-2 text-sm font-medium text-foreground hover:bg-surface"
    >
      <ArrowClockwise size={13} />
      {t("identifyCapture.uploadAnother")}
    </button>
  );
}
