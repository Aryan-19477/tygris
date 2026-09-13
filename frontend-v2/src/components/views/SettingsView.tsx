"use client";

import { useEffect, useState } from "react";
import { CheckCircle, GearSix, XCircle, SignOut } from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { api } from "@/lib/api";

export function SettingsView() {
  const [online, setOnline] = useState<boolean | null>(null);
  const [modelStatus, setModelStatus] = useState<{ is_fully_trained: boolean; weights_loaded: Record<string, boolean> } | null>(null);

  useEffect(() => {
    api.stats().then(() => setOnline(true)).catch(() => setOnline(false));
    api.modelStatus().then(setModelStatus).catch(() => {});
  }, []);

  return (
    <div>
      <TopBar title="Settings" subtitle="Account, system status, and pipeline configuration" alertCount={0} />
      <div className="px-8 py-6 space-y-8">
        <section>
          <div className="mb-3 font-mono text-[11px] uppercase tracking-wide text-muted">Account</div>
          <div className="flex items-center justify-between rounded-2xl border border-border bg-surface p-5">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-accent-soft font-mono text-sm font-medium text-accent">
                RO
              </div>
              <div>
                <div className="text-sm font-medium text-foreground">Range Officer</div>
                <div className="text-xs text-muted">Forest Department, Pench Tiger Reserve</div>
              </div>
            </div>
            <button className="flex items-center gap-1.5 rounded-full border border-border-strong px-3.5 py-1.5 text-xs font-medium text-foreground hover:bg-surface-sunken">
              <SignOut size={13} />
              Log out
            </button>
          </div>
        </section>

        <section>
          <div className="mb-3 font-mono text-[11px] uppercase tracking-wide text-muted">System Architecture</div>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div className="rounded-2xl border border-border bg-surface p-5">
              <div className="mb-3 flex items-center gap-2">
                <GearSix size={16} className="text-muted" />
                <span className="font-mono text-[11px] uppercase tracking-wide text-muted">Identification API</span>
              </div>
              <div className="flex items-center gap-2">
                {online === null ? (
                  <span className="text-sm text-muted">Checking...</span>
                ) : online ? (
                  <>
                    <CheckCircle size={16} weight="fill" className="text-positive" />
                    <span className="text-sm font-medium text-foreground">Online</span>
                  </>
                ) : (
                  <>
                    <XCircle size={16} weight="fill" className="text-danger" />
                    <span className="text-sm font-medium text-foreground">Unreachable</span>
                  </>
                )}
              </div>
            </div>

            <div className="rounded-2xl border border-border bg-surface p-5">
              <div className="mb-3 font-mono text-[11px] uppercase tracking-wide text-muted">Model status</div>
              {modelStatus ? (
                <>
                  <div className="flex items-center gap-2">
                    {modelStatus.is_fully_trained ? (
                      <CheckCircle size={16} weight="fill" className="text-positive" />
                    ) : (
                      <XCircle size={16} weight="fill" className="text-danger" />
                    )}
                    <span className="text-sm font-medium text-foreground">
                      {modelStatus.is_fully_trained ? "Fully trained" : "Untrained stage(s) present"}
                    </span>
                  </div>
                  {!modelStatus.is_fully_trained && (
                    <div className="mt-2 text-xs text-muted">
                      {Object.entries(modelStatus.weights_loaded)
                        .filter(([, loaded]) => !loaded)
                        .map(([stage]) => stage)
                        .join(", ")}{" "}
                      running on untrained weights.
                    </div>
                  )}
                </>
              ) : (
                <span className="text-sm text-muted">Checking...</span>
              )}
            </div>

            <div className="rounded-2xl border border-border bg-surface p-5">
              <div className="mb-3 font-mono text-[11px] uppercase tracking-wide text-muted">Matching thresholds</div>
              <div className="space-y-1.5 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted">Auto-accept</span>
                  <span className="font-mono text-foreground">0.74 cosine</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted">Review floor</span>
                  <span className="font-mono text-foreground">0.55 cosine</span>
                </div>
              </div>
            </div>

            <div className="rounded-2xl border border-border bg-surface p-5">
              <div className="mb-3 font-mono text-[11px] uppercase tracking-wide text-muted">Compute</div>
              <div className="text-sm text-foreground">NVIDIA RTX 4070 Laptop GPU (WSL2 + CUDA)</div>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
