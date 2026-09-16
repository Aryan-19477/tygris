"use client";

import {
  UploadSimple,
  FilmStrip,
  Star,
  Fingerprint,
  Target,
  FlowArrow,
  ArrowRight,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { Card, SectionLabel } from "@/components/ui";
import { IdentifyCapture } from "@/components/IdentifyCapture";
import type { Stats } from "@/lib/api";
import { useLanguage } from "@/lib/i18n/LanguageContext";

const STEPS = [
  { key: "upload", icon: UploadSimple, chips: ["JPG / PNG", "MP4 / MOV"], videoOnly: false },
  { key: "screen", icon: FilmStrip, chips: ["YOLOv8n", "Coat check"], videoOnly: true },
  { key: "best", icon: Star, chips: ["Quality score"], videoOnly: true },
  { key: "embed", icon: Fingerprint, chips: ["ResNet50", "Triplet loss"], videoOnly: false },
  { key: "match", icon: Target, chips: ["Cosine similarity"], videoOnly: false },
] as const;

export function IdentifyView({ stats }: { stats: Stats | null }) {
  const { t } = useLanguage();

  return (
    <div>
      <TopBar
        title={t("identify.title")}
        subtitle={t("identify.subtitle")}
        alertCount={stats?.pending_review ?? 0}
      />

      <div className="mx-auto max-w-6xl space-y-8 px-5 py-6 sm:px-8">
        <Card padding="lg">
          <IdentifyCapture />
        </Card>

        <section>
          <div className="mb-4 flex flex-wrap items-end justify-between gap-2">
            <div>
              <SectionLabel icon={<FlowArrow size={13} />} className="mb-1">
                {t("identify.pipeline.label")}
              </SectionLabel>
              <h2 className="font-serif text-xl font-medium text-foreground">
                {t("identify.pipeline.title")}
              </h2>
            </div>
            <div className="flex items-center gap-3 text-[11px] text-muted">
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full bg-accent" /> {t("identify.pipeline.allUploads")}
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full border border-dashed border-accent" />{" "}
                {t("identify.pipeline.videoOnly")}
              </span>
            </div>
          </div>

          <ol className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
            {STEPS.map((s, i) => {
              const Icon = s.icon;
              return (
                <li
                  key={s.key}
                  className={`relative flex flex-col rounded-xl border bg-surface p-4 ${
                    s.videoOnly ? "border-dashed border-accent/50" : "border-border"
                  }`}
                >
                  {i < STEPS.length - 1 && (
                    <span className="absolute -right-3.5 top-9 z-10 hidden h-6 w-6 items-center justify-center rounded-full border border-border bg-background text-muted lg:flex">
                      <ArrowRight size={11} weight="bold" />
                    </span>
                  )}
                  <div className="mb-3 flex items-center justify-between">
                    <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-accent-soft text-accent">
                      <Icon size={18} weight="duotone" />
                    </div>
                    <span className="font-mono text-[11px] font-semibold text-muted">0{i + 1}</span>
                  </div>
                  <h3 className="text-sm font-semibold text-foreground">
                    {t(`identify.pipeline.${s.key}.title`)}
                  </h3>
                  {s.videoOnly && (
                    <span className="mt-1 w-fit rounded-full bg-accent-soft px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-accent">
                      {t("identify.pipeline.videoOnly")}
                    </span>
                  )}
                  <p className="mt-2 flex-1 text-xs leading-relaxed text-muted">
                    {t(`identify.pipeline.${s.key}.body`)}
                  </p>
                  <div className="mt-3 flex flex-wrap gap-1">
                    {s.chips.map((c) => (
                      <span
                        key={c}
                        className="rounded border border-border bg-surface-sunken px-1.5 py-0.5 font-mono text-[10px] text-foreground"
                      >
                        {c}
                      </span>
                    ))}
                  </div>
                </li>
              );
            })}
          </ol>

          <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Fact
              value={stats?.total_individuals != null ? String(stats.total_individuals) : "—"}
              label={t("identify.pipeline.factGallery")}
            />
            <Fact value="3 fps" label={t("identify.pipeline.factSampling")} />
            <Fact value="4" label={t("identify.pipeline.factFilters")} />
          </div>
        </section>
      </div>
    </div>
  );
}

function Fact({ value, label }: { value: string; label: string }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-border bg-surface px-4 py-3">
      <span className="font-mono text-xl font-semibold text-foreground">{value}</span>
      <span className="text-xs leading-snug text-muted">{label}</span>
    </div>
  );
}
