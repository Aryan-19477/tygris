"use client";

import { useEffect, useState } from "react";
import {
  CheckCircle,
  XCircle,
  Question,
  ArrowsClockwise,
  DownloadSimple,
  ShieldCheck,
  WarningCircle,
  Camera,
  Calendar,
  Sparkle
} from "@phosphor-icons/react";
import { api, type PreyReviewItem } from "@/lib/api";

const SPECIES_OPTIONS = [
  { id: "chital", name: "Chital / Spotted Deer" },
  { id: "sambar", name: "Sambar" },
  { id: "wild_pig", name: "Wild Pig / Wild Boar" },
  { id: "gaur", name: "Gaur / Indian Bison" },
  { id: "nilgai", name: "Nilgai / Blue Bull" },
  { id: "barking_deer", name: "Barking Deer / Muntjac" },
  { id: "chousingha", name: "Four-horned Antelope / Chousingha" },
  { id: "langur", name: "Northern Plains Gray Langur" },
  { id: "tiger", name: "Tiger (Panthera tigris)" },
  { id: "peafowl", name: "Indian Peafowl" },
  { id: "jackal", name: "Golden Jackal" },
  { id: "sloth_bear", name: "Sloth Bear" },
  { id: "other_mammal", name: "Other Mammal" },
  { id: "unknown", name: "Unknown Species" }
];

export function PreyReviewView() {
  const [items, setItems] = useState<PreyReviewItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedItem, setSelectedItem] = useState<PreyReviewItem | null>(null);
  const [correctedSpecies, setCorrectedSpecies] = useState("chital");
  const [verifiedSex, setVerifiedSex] = useState("unknown");
  const [verifiedAge, setVerifiedAge] = useState("adult");
  const [verifiedBehaviour, setVerifiedBehaviour] = useState("grazing");
  const [notes, setNotes] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [exportMessage, setExportMessage] = useState<string | null>(null);

  const fetchQueue = async () => {
    setLoading(true);
    try {
      const q = await api.prey.getReviewQueue(40);
      setItems(q);
      if (q.length > 0 && !selectedItem) {
        setSelectedItem(q[0]);
        setCorrectedSpecies(q[0].predicted_species || "chital");
      }
    } catch (e) {
      console.error("Failed to load review queue", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchQueue();
  }, []);

  const handleResolve = async (action: "confirm" | "correct" | "reject") => {
    if (!selectedItem) return;
    setSubmitting(true);
    try {
      await api.prey.resolveReview(selectedItem.review_id, {
        action,
        verified_species: action === "confirm" ? selectedItem.predicted_species : correctedSpecies,
        verified_sex: verifiedSex,
        verified_age: verifiedAge,
        verified_behaviour: verifiedBehaviour,
        notes: notes || undefined
      });

      // Remove from queue
      const remaining = items.filter((i) => i.review_id !== selectedItem.review_id);
      setItems(remaining);
      setSelectedItem(remaining.length > 0 ? remaining[0] : null);
      if (remaining.length > 0) {
        setCorrectedSpecies(remaining[0].predicted_species || "chital");
      }
      setNotes("");
    } catch (err) {
      console.error("Failed to resolve review item", err);
    } finally {
      setSubmitting(false);
    }
  };

  const handleExport = async () => {
    try {
      const exp = await api.prey.exportTrainingData();
      const blob = new Blob([JSON.stringify(exp, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `pench_prey_active_learning_${Date.now()}.json`;
      a.click();
      setExportMessage(`Exported ${exp.total_annotated_samples} verified training annotations!`);
      setTimeout(() => setExportMessage(null), 4000);
    } catch (e) {
      console.error("Export failed", e);
    }
  };

  return (
    <div className="min-h-full bg-background p-6 space-y-6 text-foreground">
      {/* Header */}
      <div className="flex flex-col gap-2 border-b border-border/40 pb-5 md:flex-row md:items-center md:justify-between">
        <div>
          <div className="inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary border border-primary/20">
            <Sparkle size={14} />
            Human-in-the-Loop & Active Learning (FR-16, FR-17)
          </div>
          <h1 className="mt-2 text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
            Prey Verification & Review Queue
          </h1>
          <p className="text-sm text-muted">
            Inspect uncertain animal predictions, correct species classifications, and contribute ground truth to future Pench model retraining.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={fetchQueue}
            className="inline-flex items-center gap-2 rounded-xl border border-border bg-surface px-3 py-2 text-xs font-semibold text-foreground hover:bg-surface-hover shadow-sm transition-all"
          >
            <ArrowsClockwise size={14} className={loading ? "animate-spin" : ""} />
            Refresh Queue
          </button>
          <button
            onClick={handleExport}
            className="inline-flex items-center gap-2 rounded-xl bg-primary px-3 py-2 text-xs font-semibold text-primary-foreground hover:bg-primary/90 shadow-sm transition-all"
          >
            <DownloadSimple size={14} weight="bold" />
            Export Training Dataset
          </button>
        </div>
      </div>

      {exportMessage && (
        <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-xs text-emerald-400 flex items-center gap-2">
          <CheckCircle size={16} />
          <span>{exportMessage}</span>
        </div>
      )}

      {/* Main Review Interface */}
      {items.length === 0 && !loading ? (
        <div className="flex h-96 flex-col items-center justify-center rounded-2xl border border-border/40 bg-surface/50 p-8 text-center">
          <CheckCircle size={44} className="text-emerald-400 mb-3" />
          <h3 className="text-base font-bold text-foreground">Review Queue is Clear!</h3>
          <p className="mt-1 max-w-sm text-xs text-muted">
            All current prey predictions satisfy high-confidence thresholds (≥85%) and have been automatically accepted.
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
          {/* Queue List (4 cols) */}
          <div className="space-y-3 lg:col-span-4 overflow-y-auto max-h-[750px] pr-1">
            <div className="text-xs font-semibold uppercase tracking-wider text-muted flex justify-between items-center">
              <span>Pending Ranger Verification ({items.length})</span>
            </div>

            {items.map((item) => {
              const isSelected = selectedItem?.review_id === item.review_id;
              return (
                <div
                  key={item.review_id}
                  onClick={() => {
                    setSelectedItem(item);
                    setCorrectedSpecies(item.predicted_species || "chital");
                  }}
                  className={`cursor-pointer rounded-2xl border p-4 transition-all ${
                    isSelected
                      ? "border-primary bg-primary/10 shadow-sm"
                      : "border-border/50 bg-surface hover:border-primary/40 hover:bg-surface-hover/60"
                  }`}
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <span className="font-bold capitalize text-sm text-foreground">
                        {item.predicted_species.replace("_", " ")}
                      </span>
                      <div className="mt-1 flex items-center gap-3 text-xs text-muted">
                        <span className="flex items-center gap-1 font-mono">
                          <Camera size={13} /> {item.camera_id || "PTR-STN"}
                        </span>
                        <span>{item.timestamp?.slice(5, 16) || "Recent"}</span>
                      </div>
                    </div>
                    <span className="font-mono text-xs font-bold text-amber-400">
                      {Math.round(item.confidence * 100)}%
                    </span>
                  </div>

                  <div className="mt-2 text-[11px] text-muted line-clamp-1">
                    Reason: {item.reason.replace(/_/g, " ")}
                  </div>
                </div>
              );
            })}
          </div>

          {/* Inspection & Resolution Panel (8 cols) */}
          {selectedItem && (
            <div className="rounded-2xl border border-border/50 bg-surface p-6 space-y-5 lg:col-span-8">
              <div className="flex items-center justify-between border-b border-border/40 pb-4">
                <div>
                  <h3 className="text-lg font-bold text-foreground">
                    Observation Inspection ({selectedItem.review_id})
                  </h3>
                  <div className="mt-1 flex items-center gap-3 text-xs text-muted">
                    <span className="font-mono">Obs ID: {selectedItem.observation_id}</span>
                    <span>•</span>
                    <span className="font-mono">Camera: {selectedItem.camera_id || "PTR-STN"}</span>
                    <span>•</span>
                    <span>{selectedItem.timestamp}</span>
                  </div>
                </div>

                <div className="text-right">
                  <span className="text-xs text-muted block">AI Confidence</span>
                  <span className="text-lg font-bold font-mono text-amber-400">
                    {Math.round(selectedItem.confidence * 100)}%
                  </span>
                </div>
              </div>

              {/* Rationale Notice */}
              <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-300 flex items-start gap-2">
                <WarningCircle size={18} className="shrink-0 mt-0.5" />
                <div>
                  <span className="font-semibold">Routing Reason: </span>
                  <span>{selectedItem.reason.replace(/_/g, " ")}. Needs ranger domain verification.</span>
                </div>
              </div>

              {/* Verification Form */}
              <div className="space-y-4 pt-2">
                <div>
                  <label className="text-xs font-semibold text-foreground">Confirm / Correct Species</label>
                  <select
                    value={correctedSpecies}
                    onChange={(e) => setCorrectedSpecies(e.target.value)}
                    className="mt-1.5 w-full rounded-xl border border-border bg-background px-3 py-2.5 text-xs text-foreground focus:border-primary focus:outline-none"
                  >
                    {SPECIES_OPTIONS.map((sp) => (
                      <option key={sp.id} value={sp.id}>
                        {sp.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="grid grid-cols-3 gap-3">
                  <div>
                    <label className="text-xs text-muted">Sex</label>
                    <select
                      value={verifiedSex}
                      onChange={(e) => setVerifiedSex(e.target.value)}
                      className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-xs text-foreground focus:border-primary focus:outline-none"
                    >
                      <option value="male">Male</option>
                      <option value="female">Female</option>
                      <option value="unknown">Unknown</option>
                    </select>
                  </div>

                  <div>
                    <label className="text-xs text-muted">Age Class</label>
                    <select
                      value={verifiedAge}
                      onChange={(e) => setVerifiedAge(e.target.value)}
                      className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-xs text-foreground focus:border-primary focus:outline-none"
                    >
                      <option value="adult">Adult</option>
                      <option value="juvenile">Juvenile</option>
                      <option value="unknown">Unknown</option>
                    </select>
                  </div>

                  <div>
                    <label className="text-xs text-muted">Behaviour</label>
                    <select
                      value={verifiedBehaviour}
                      onChange={(e) => setVerifiedBehaviour(e.target.value)}
                      className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-xs text-foreground focus:border-primary focus:outline-none"
                    >
                      <option value="grazing">Grazing</option>
                      <option value="feeding">Feeding</option>
                      <option value="walking">Walking</option>
                      <option value="alert">Alert</option>
                      <option value="resting">Resting</option>
                      <option value="drinking">Drinking</option>
                      <option value="fleeing">Fleeing</option>
                      <option value="unknown">Unknown</option>
                    </select>
                  </div>
                </div>

                <div>
                  <label className="text-xs text-muted">Ranger Notes</label>
                  <input
                    type="text"
                    value={notes}
                    onChange={(e) => setNotes(e.target.value)}
                    placeholder="e.g. Verified antler structure and spots. Pench central sector."
                    className="mt-1 w-full rounded-xl border border-border bg-background px-3 py-2 text-xs text-foreground focus:border-primary focus:outline-none"
                  />
                </div>

                {/* Actions */}
                <div className="flex flex-wrap items-center gap-3 pt-3 border-t border-border/40">
                  <button
                    onClick={() => handleResolve("confirm")}
                    disabled={submitting}
                    className="inline-flex items-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-xs font-semibold text-white shadow hover:bg-emerald-500 disabled:opacity-50 transition-all"
                  >
                    <CheckCircle size={16} weight="bold" />
                    Confirm AI Species ({selectedItem.predicted_species.replace("_", " ")})
                  </button>

                  <button
                    onClick={() => handleResolve("correct")}
                    disabled={submitting}
                    className="inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-semibold text-primary-foreground shadow hover:bg-primary/90 disabled:opacity-50 transition-all"
                  >
                    <ShieldCheck size={16} weight="bold" />
                    Save Correction as {correctedSpecies.replace("_", " ")}
                  </button>

                  <button
                    onClick={() => handleResolve("reject")}
                    disabled={submitting}
                    className="inline-flex items-center gap-2 rounded-xl border border-border bg-surface px-4 py-2.5 text-xs font-semibold text-muted hover:text-foreground hover:bg-surface-hover transition-all"
                  >
                    <Question size={16} weight="bold" />
                    Mark as Unknown / Rejected
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
