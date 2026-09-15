"use client";

import { useCallback, useRef, useState } from "react";
import {
  UploadSimple,
  Sparkle,
  CheckCircle,
  WarningCircle,
  ArrowClockwise,
  UserPlus,
} from "@phosphor-icons/react";
import { api, type IdentifyResult } from "@/lib/api";
import { useLanguage } from "@/lib/i18n/LanguageContext";

type Phase = "idle" | "uploading" | "result" | "error";

/**
 * Shared upload -> identify -> confirm/enroll flow, used by both the
 * Reserve Map's per-station slide-over and the standalone Identify tab.
 * station is optional: the map slide-over always has one (tied to the
 * pin the ranger clicked); the standalone tab lets her pick one, or
 * leave it unset for a capture that isn't tied to a specific camera.
 */
export function IdentifyCapture({ stationId }: { stationId?: string }) {
  const { t } = useLanguage();
  const [phase, setPhase] = useState<Phase>("idle");
  const [result, setResult] = useState<IdentifyResult | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const runIdentify = useCallback(
    async (file: File) => {
      setPhase("uploading");
      try {
        const res = await api.identify(file, stationId);
        setResult(res);
        setPhase("result");
      } catch {
        setPhase("error");
      }
    },
    [stationId]
  );

  const handleFiles = useCallback(
    (files: FileList | null) => {
      const file = files?.[0];
      if (file) runIdentify(file);
    },
    [runIdentify]
  );

  const isKnown = result?.status === "KNOWN";

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
          className={`flex min-h-64 cursor-pointer flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed transition-colors ${
            dragOver ? "border-accent bg-accent-soft" : "border-border-strong hover:border-accent/50"
          }`}
        >
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => handleFiles(e.target.files)}
          />
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-accent-soft text-accent">
            <UploadSimple size={20} weight="bold" />
          </div>
          <p className="text-sm font-medium text-foreground">{t("identifyCapture.dropTitle")}</p>
          <p className="text-xs text-muted">{t("identifyCapture.dropSub")}</p>
        </div>
      )}

      {phase === "uploading" && (
        <div className="flex min-h-64 flex-col items-center justify-center gap-3">
          <div className="flex h-12 w-12 animate-spin items-center justify-center rounded-full bg-accent-soft text-accent">
            <Sparkle size={20} weight="fill" />
          </div>
          <p className="text-sm font-medium text-foreground">{t("identifyCapture.identifying")}</p>
        </div>
      )}

      {phase === "error" && (
        <div className="flex min-h-64 flex-col items-center justify-center gap-3 rounded-xl border border-danger/30 bg-danger-soft">
          <WarningCircle size={26} className="text-danger" />
          <p className="text-sm font-medium text-danger">{t("identifyCapture.errorTitle")}</p>
          <button
            onClick={() => setPhase("idle")}
            className="rounded-full border border-border-strong px-3.5 py-1.5 text-sm font-medium text-foreground hover:bg-surface"
          >
            {t("identifyCapture.tryAgain")}
          </button>
        </div>
      )}

      {phase === "result" && result && (
        <div className="flex flex-col gap-4">
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

          <button
            onClick={() => {
              setPhase("idle");
              setResult(null);
            }}
            className="flex items-center justify-center gap-1.5 rounded-full border border-border-strong px-3.5 py-2 text-sm font-medium text-foreground hover:bg-surface"
          >
            <ArrowClockwise size={13} />
            {t("identifyCapture.uploadAnother")}
          </button>
        </div>
      )}
    </div>
  );
}
