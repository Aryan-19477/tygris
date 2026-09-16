"use client";

import { useState, useRef, ChangeEvent, DragEvent } from "react";
import {
  UploadSimple,
  CheckCircle,
  WarningCircle,
  Question,
  ShieldCheck,
  Eye,
  Camera,
  ArrowsClockwise,
  MagnifyingGlass,
  Sparkle,
  SlidersHorizontal,
  BookmarkSimple
} from "@phosphor-icons/react";
import { api, type PreyIdentifyCheckResult, type PreyAnimal } from "@/lib/api";

export function PreyCheckerView() {
  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [result, setResult] = useState<PreyIdentifyCheckResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cameraId, setCameraId] = useState("PTR-CORE-12");
  const [recordObservation, setRecordObservation] = useState(true);
  const [savedSuccess, setSavedSuccess] = useState(false);
  const [dragActive, setDragActive] = useState(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileSelect = (selected: File) => {
    setFile(selected);
    setError(null);
    setResult(null);
    setSavedSuccess(false);
    const url = URL.createObjectURL(selected);
    setPreviewUrl(url);
  };

  const onInputChange = (e: ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      handleFileSelect(e.target.files[0]);
    }
  };

  const onDragOver = (e: DragEvent) => {
    e.preventDefault();
    setDragActive(true);
  };

  const onDragLeave = () => setDragActive(false);

  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragActive(false);
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      handleFileSelect(e.dataTransfer.files[0]);
    }
  };

  const runIdentifyCheck = async () => {
    if (!file) return;
    setIsAnalyzing(true);
    setError(null);
    try {
      const res = await api.prey.identifyCheck(file, {
        camera_id: cameraId,
        record_observation: recordObservation,
      });
      setResult(res);
      if (res.saved_observation_ids && res.saved_observation_ids.length > 0) {
        setSavedSuccess(true);
      }
    } catch (err: any) {
      setError(err?.message || "Failed to analyze animal image.");
    } finally {
      setIsAnalyzing(false);
    }
  };

  // Test with generated sample frame if user doesn't have an image ready
  const loadSyntheticSample = async (type: "chital" | "sambar" | "boar") => {
    const canvas = document.createElement("canvas");
    canvas.width = 640;
    canvas.height = 480;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // Background: jungle vegetation
    const grad = ctx.createLinearGradient(0, 0, 0, 480);
    grad.addColorStop(0, "#2d4a22");
    grad.addColorStop(1, "#172612");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 640, 480);

    // Forest ground
    ctx.fillStyle = "#3b3122";
    ctx.fillRect(0, 360, 640, 120);

    if (type === "chital") {
      // Golden rufous with white spots
      ctx.fillStyle = "#c27c38";
      ctx.beginPath();
      ctx.ellipse(320, 260, 110, 65, 0, 0, Math.PI * 2);
      ctx.fill();
      // Neck & head
      ctx.beginPath();
      ctx.ellipse(420, 200, 35, 55, 0.4, 0, Math.PI * 2);
      ctx.fill();
      // White spots
      ctx.fillStyle = "#ffffff";
      for (let i = 0; i < 22; i++) {
        const x = 250 + (i % 6) * 22;
        const y = 230 + Math.floor(i / 6) * 16;
        ctx.beginPath();
        ctx.arc(x, y, 4, 0, Math.PI * 2);
        ctx.fill();
      }
    } else if (type === "sambar") {
      // Dark brown heavy deer
      ctx.fillStyle = "#4a3b32";
      ctx.beginPath();
      ctx.ellipse(320, 250, 140, 85, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.ellipse(430, 180, 45, 65, 0.5, 0, Math.PI * 2);
      ctx.fill();
    } else {
      // Wild boar: dark compact body
      ctx.fillStyle = "#262322";
      ctx.beginPath();
      ctx.ellipse(310, 300, 95, 55, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.ellipse(390, 310, 40, 35, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    canvas.toBlob((blob) => {
      if (blob) {
        const sampleFile = new File([blob], `sample_${type}.jpg`, { type: "image/jpeg" });
        handleFileSelect(sampleFile);
      }
    }, "image/jpeg", 0.9);
  };

  const getDecisionBadge = (decision: string) => {
    switch (decision) {
      case "auto_accepted":
        return (
          <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-2.5 py-1 text-xs font-semibold text-emerald-400 border border-emerald-500/30">
            <CheckCircle size={14} weight="fill" />
            AUTO ACCEPTED
          </span>
        );
      case "needs_review":
        return (
          <span className="inline-flex items-center gap-1 rounded-full bg-amber-500/15 px-2.5 py-1 text-xs font-semibold text-amber-400 border border-amber-500/30">
            <WarningCircle size={14} weight="fill" />
            NEEDS REVIEW
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1 rounded-full bg-slate-500/15 px-2.5 py-1 text-xs font-semibold text-slate-300 border border-slate-500/30">
            <Question size={14} weight="bold" />
            UNKNOWN / ABSTAINED
          </span>
        );
    }
  };

  return (
    <div className="min-h-full bg-background p-6 space-y-6 text-foreground">
      {/* Header */}
      <div className="flex flex-col gap-2 border-b border-border/40 pb-5 md:flex-row md:items-center md:justify-between">
        <div>
          <div className="inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary border border-primary/20">
            <Sparkle size={14} />
            Pench Multi-Species Vision Pipeline (FR-01 - FR-15)
          </div>
          <h1 className="mt-2 text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
            Wildlife Species Identify Checker
          </h1>
          <p className="text-sm text-muted">
            Test any camera-trap image through the 5-stage quality gate, animal detector, species classifier, and confidence calibration layer.
          </p>
        </div>

        {/* Quick Sample Selector */}
        <div className="flex items-center gap-2 text-xs">
          <span className="text-muted">Quick Test:</span>
          <button
            onClick={() => loadSyntheticSample("chital")}
            className="rounded-lg border border-border bg-surface px-2.5 py-1.5 font-medium hover:bg-surface-hover hover:text-foreground transition-all"
          >
            🦌 Chital Sample
          </button>
          <button
            onClick={() => loadSyntheticSample("sambar")}
            className="rounded-lg border border-border bg-surface px-2.5 py-1.5 font-medium hover:bg-surface-hover hover:text-foreground transition-all"
          >
            🦌 Sambar Sample
          </button>
          <button
            onClick={() => loadSyntheticSample("boar")}
            className="rounded-lg border border-border bg-surface px-2.5 py-1.5 font-medium hover:bg-surface-hover hover:text-foreground transition-all"
          >
            🐗 Wild Boar
          </button>
        </div>
      </div>

      {/* Grid: Upload & Controls | Results */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
        {/* Left Column: Upload & Options (5 cols) */}
        <div className="space-y-4 lg:col-span-5">
          <div
            onDragOver={onDragOver}
            onDragLeave={onDragLeave}
            onDrop={onDrop}
            onClick={() => fileInputRef.current?.click()}
            className={`relative flex min-h-[260px] cursor-pointer flex-col items-center justify-center rounded-2xl border-2 border-dashed p-6 text-center transition-all ${
              dragActive
                ? "border-primary bg-primary/5"
                : "border-border/60 bg-surface hover:border-primary/50 hover:bg-surface-hover/50"
            }`}
          >
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={onInputChange}
            />

            {previewUrl ? (
              <div className="relative h-56 w-full overflow-hidden rounded-xl">
                <img
                  src={previewUrl}
                  alt="Upload preview"
                  className="h-full w-full object-contain"
                />
                <div className="absolute inset-0 flex items-center justify-center bg-black/40 opacity-0 transition-opacity hover:opacity-100">
                  <span className="rounded-lg bg-surface/90 px-3 py-1.5 text-xs font-semibold text-foreground shadow">
                    Click to change photo
                  </span>
                </div>
              </div>
            ) : (
              <div className="flex flex-col items-center space-y-3">
                <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                  <UploadSimple size={28} />
                </div>
                <div>
                  <p className="text-sm font-semibold text-foreground">
                    Drop camera-trap photo here, or browse
                  </p>
                  <p className="mt-1 text-xs text-muted">
                    Supports JPG, PNG, JPEG, IR / Day / Twilight imagery
                  </p>
                </div>
              </div>
            )}
          </div>

          {/* Controls Card */}
          <div className="rounded-2xl border border-border/50 bg-surface p-4 space-y-4">
            <div className="flex items-center justify-between text-xs font-semibold text-muted uppercase tracking-wider">
              <span>Observation Context</span>
              <SlidersHorizontal size={16} />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-muted">Camera Station</label>
                <input
                  type="text"
                  value={cameraId}
                  onChange={(e) => setCameraId(e.target.value)}
                  className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-xs text-foreground focus:border-primary focus:outline-none"
                  placeholder="e.g. PTR_CAM_01"
                />
              </div>
              <div className="flex flex-col justify-end">
                <label className="flex items-center gap-2 cursor-pointer text-xs text-foreground pb-2">
                  <input
                    type="checkbox"
                    checked={recordObservation}
                    onChange={(e) => setRecordObservation(e.target.checked)}
                    className="rounded border-border accent-primary"
                  />
                  <span>Save to Observations</span>
                </label>
              </div>
            </div>

            <button
              onClick={runIdentifyCheck}
              disabled={!file || isAnalyzing}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 py-3 text-sm font-semibold text-primary-foreground shadow-sm transition-all hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isAnalyzing ? (
                <>
                  <ArrowsClockwise size={18} className="animate-spin" />
                  Running 5-Stage Inference...
                </>
              ) : (
                <>
                  <MagnifyingGlass size={18} weight="bold" />
                  Identify Animal & Verify
                </>
              )}
            </button>

            {error && (
              <div className="rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-xs text-red-400 flex items-center gap-2">
                <WarningCircle size={16} />
                <span>{error}</span>
              </div>
            )}

            {savedSuccess && (
              <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-xs text-emerald-400 flex items-center gap-2">
                <CheckCircle size={16} />
                <span>Observation successfully recorded in Pench SQLite database!</span>
              </div>
            )}
          </div>
        </div>

        {/* Right Column: In-depth Results & Annotations (7 cols) */}
        <div className="space-y-4 lg:col-span-7">
          {result ? (
            <div className="space-y-4">
              {/* Annotated Image Card */}
              <div className="rounded-2xl border border-border/50 bg-surface p-4">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold text-foreground">
                      Detection & Species Localization
                    </span>
                    <span className="text-xs text-muted font-mono">
                      ({result.total_animals_detected} detected)
                    </span>
                  </div>
                  {getDecisionBadge(result.overall_decision)}
                </div>

                <div className="relative overflow-hidden rounded-xl border border-border/40 bg-black/40 flex items-center justify-center min-h-[300px]">
                  <img
                    src={result.annotated_image}
                    alt="Annotated identification"
                    className="max-h-[420px] w-full object-contain rounded-lg"
                  />
                </div>
              </div>

              {/* Quality Gate Card (FR-06) */}
              <div className="rounded-2xl border border-border/50 bg-surface p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted">
                    Stage 1: Image Quality Assessment Gate
                  </span>
                  <span
                    className={`text-xs font-semibold px-2 py-0.5 rounded-full ${
                      result.image_quality.usable
                        ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
                        : "bg-red-500/10 text-red-400 border border-red-500/20"
                    }`}
                  >
                    {result.image_quality.usable ? "USABLE FOR AI" : "ROUTED TO REVIEW"}
                  </span>
                </div>

                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mt-3 text-center">
                  <div className="rounded-xl bg-background/60 border border-border/40 p-2.5">
                    <div className="text-[11px] text-muted">Quality Score</div>
                    <div className="text-base font-bold text-foreground mt-0.5">
                      {Math.round(result.image_quality.quality_score * 100)}%
                    </div>
                  </div>
                  <div className="rounded-xl bg-background/60 border border-border/40 p-2.5">
                    <div className="text-[11px] text-muted">Sharpness / Blur</div>
                    <div className="text-base font-bold text-foreground mt-0.5">
                      {result.image_quality.laplacian_variance}
                    </div>
                  </div>
                  <div className="rounded-xl bg-background/60 border border-border/40 p-2.5">
                    <div className="text-[11px] text-muted">Condition</div>
                    <div className="text-base font-bold capitalize text-foreground mt-0.5">
                      {result.image_quality.lighting_condition.replace("_", " ")}
                    </div>
                  </div>
                  <div className="rounded-xl bg-background/60 border border-border/40 p-2.5">
                    <div className="text-[11px] text-muted">Resolution</div>
                    <div className="text-base font-bold text-foreground mt-0.5">
                      {result.image_quality.resolution[0]}×{result.image_quality.resolution[1]}
                    </div>
                  </div>
                </div>

                {result.image_quality.issues && result.image_quality.issues.length > 0 && (
                  <div className="mt-2 text-xs text-amber-400 flex items-center gap-1.5">
                    <WarningCircle size={14} />
                    <span>Flags: {result.image_quality.issues.join(", ")}</span>
                  </div>
                )}
              </div>

              {/* Detected Animals Breakdown */}
              <div className="space-y-3">
                <div className="text-xs font-semibold uppercase tracking-wider text-muted">
                  Stage 2 & 3: Individual Animal Classification
                </div>

                {result.animals.map((animal, idx) => (
                  <div
                    key={idx}
                    className="rounded-2xl border border-border/50 bg-surface p-4 space-y-3"
                  >
                    <div className="flex items-start justify-between">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-lg font-bold capitalize text-foreground">
                            {animal.species.replace("_", " ")}
                          </span>
                          <span className="text-xs text-muted font-mono">
                            (Animal #{animal.animal_index})
                          </span>
                        </div>
                        <div className="mt-1 text-xs text-muted font-mono">
                          BBox: [{animal.bbox.join(", ")}]
                        </div>
                      </div>
                      {getDecisionBadge(animal.decision)}
                    </div>

                    {/* Confidence Meter */}
                    <div>
                      <div className="flex justify-between text-xs mb-1">
                        <span className="text-muted">Species Confidence</span>
                        <span className="font-semibold text-foreground">
                          {Math.round(animal.species_confidence * 100)}%
                        </span>
                      </div>
                      <div className="h-2 w-full rounded-full bg-background overflow-hidden">
                        <div
                          className={`h-full rounded-full ${
                            animal.species_confidence >= 0.85
                              ? "bg-emerald-500"
                              : animal.species_confidence >= 0.50
                              ? "bg-amber-500"
                              : "bg-slate-400"
                          }`}
                          style={{ width: `${Math.min(100, animal.species_confidence * 100)}%` }}
                        />
                      </div>
                    </div>

                    {/* Attributes Grid (FR-09, FR-10) */}
                    <div className="grid grid-cols-3 gap-2 pt-1">
                      <div className="rounded-lg bg-background/50 border border-border/30 px-3 py-2">
                        <span className="text-[10px] uppercase tracking-wider text-muted">Sex</span>
                        <p className="text-xs font-semibold capitalize text-foreground mt-0.5">
                          {animal.sex}
                        </p>
                      </div>
                      <div className="rounded-lg bg-background/50 border border-border/30 px-3 py-2">
                        <span className="text-[10px] uppercase tracking-wider text-muted">Age Class</span>
                        <p className="text-xs font-semibold capitalize text-foreground mt-0.5">
                          {animal.age_class}
                        </p>
                      </div>
                      <div className="rounded-lg bg-background/50 border border-border/30 px-3 py-2">
                        <span className="text-[10px] uppercase tracking-wider text-muted">Behaviour</span>
                        <p className="text-xs font-semibold capitalize text-foreground mt-0.5">
                          {animal.behaviour} ({Math.round(animal.behaviour_confidence * 100)}%)
                        </p>
                      </div>
                    </div>

                    {/* Decision Rationale */}
                    <div className="rounded-lg bg-surface-hover/50 p-2.5 text-xs text-muted flex items-start gap-2">
                      <ShieldCheck size={16} className="text-primary mt-0.5 shrink-0" />
                      <div>
                        <span className="font-medium text-foreground">Calibration Logic: </span>
                        <span>{animal.decision_reason}</span>
                      </div>
                    </div>

                    {/* Alternative Candidates */}
                    {animal.candidates && animal.candidates.length > 1 && (
                      <div className="pt-1 text-xs">
                        <span className="text-muted">Alternative candidates: </span>
                        {animal.candidates.slice(1).map((c, i) => (
                          <span key={i} className="font-mono text-muted mr-3">
                            {c.species.replace("_", " ")} ({Math.round(c.score * 100)}%)
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="flex h-full min-h-[400px] flex-col items-center justify-center rounded-2xl border border-border/40 bg-surface/50 p-8 text-center">
              <Eye size={42} className="text-muted/40 mb-3" />
              <h3 className="text-base font-semibold text-foreground">Awaiting Image for Identification</h3>
              <p className="mt-1 max-w-sm text-xs text-muted">
                Drop an animal photo on the left or select one of the quick test samples above to execute multi-species detection.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
