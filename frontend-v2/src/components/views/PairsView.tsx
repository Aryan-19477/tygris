"use client";

import { useEffect, useMemo, useState } from "react";
import { motion } from "motion/react";
import { Camera, Heart, MapPin, UsersThree } from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { api, type GalleryIndividual, type Stats, type TigerAssociationPair } from "@/lib/api";
import { useLanguage } from "@/lib/i18n/LanguageContext";

type PairKind = "courtship" | "family" | "overlap";

interface ClassifiedPair extends TigerAssociationPair {
  kind: PairKind;
}

const WINDOW_HOURS = 72;

function isJuvenile(individual: GalleryIndividual | undefined): boolean {
  const stage = (individual?.life_stage ?? "").toUpperCase();
  return stage.includes("CUB") || stage.includes("SUBADULT") || stage.includes("JUVENILE");
}

function classify(pair: TigerAssociationPair, byId: Map<string, GalleryIndividual>): PairKind {
  const a = byId.get(pair.tiger_a);
  const b = byId.get(pair.tiger_b);
  if (isJuvenile(a) || isJuvenile(b)) return "family";
  if (pair.sex_a !== pair.sex_b && pair.sex_a !== "U" && pair.sex_b !== "U") return "courtship";
  return "overlap";
}

const KIND_STYLE: Record<PairKind, { labelKey: string; text: string; bg: string; icon: typeof Heart }> = {
  courtship: { labelKey: "pairs.kindCourtship", text: "text-danger", bg: "bg-danger-soft", icon: Heart },
  family: { labelKey: "pairs.kindFamily", text: "text-positive", bg: "bg-positive-soft", icon: UsersThree },
  overlap: { labelKey: "pairs.kindOverlap", text: "text-caution", bg: "bg-caution-soft", icon: MapPin },
};

export function PairsView({
  stats,
  onOpenTiger,
}: {
  stats: Stats | null;
  onOpenTiger: (tigerId: string) => void;
}) {
  const { t } = useLanguage();
  const [pairs, setPairs] = useState<TigerAssociationPair[] | null>(null);
  const [individuals, setIndividuals] = useState<GalleryIndividual[] | null>(null);
  const [filter, setFilter] = useState<"all" | PairKind>("all");

  useEffect(() => {
    Promise.all([
      api.tigerAssociations(30, false, WINDOW_HOURS),
      api.gallery(),
    ]).then(([assoc, gal]) => {
      setPairs(assoc.pairs);
      setIndividuals(gal.individuals);
    });
  }, []);

  const byId = useMemo(() => {
    const map = new Map<string, GalleryIndividual>();
    (individuals ?? []).forEach((i) => map.set(i.tiger_id, i));
    return map;
  }, [individuals]);

  const classified: ClassifiedPair[] | null = useMemo(() => {
    if (!pairs) return null;
    return pairs.map((p) => ({ ...p, kind: classify(p, byId) }));
  }, [pairs, byId]);

  const filtered = useMemo(() => {
    if (!classified) return null;
    return filter === "all" ? classified : classified.filter((p) => p.kind === filter);
  }, [classified, filter]);

  const counts = useMemo(() => {
    const base = { courtship: 0, family: 0, overlap: 0 };
    (classified ?? []).forEach((p) => { base[p.kind] += 1; });
    return base;
  }, [classified]);

  return (
    <div>
      <TopBar
        title={t("pairs.title")}
        subtitle={t("pairs.subtitle")}
        alertCount={stats?.pending_review ?? 0}
      />

      <div className="px-8 py-6">
        <p className="mb-6 max-w-2xl text-sm text-muted">{t("pairs.methodology")}</p>

        <div className="mb-6 flex flex-wrap items-center gap-2">
          <FilterPill active={filter === "all"} onClick={() => setFilter("all")}>
            {t("pairs.filterAll")} <span className="font-mono text-xs opacity-60">{classified?.length ?? 0}</span>
          </FilterPill>
          <FilterPill active={filter === "courtship"} onClick={() => setFilter("courtship")}>
            {t(KIND_STYLE.courtship.labelKey)} <span className="font-mono text-xs opacity-60">{counts.courtship}</span>
          </FilterPill>
          <FilterPill active={filter === "family"} onClick={() => setFilter("family")}>
            {t(KIND_STYLE.family.labelKey)} <span className="font-mono text-xs opacity-60">{counts.family}</span>
          </FilterPill>
          <FilterPill active={filter === "overlap"} onClick={() => setFilter("overlap")}>
            {t(KIND_STYLE.overlap.labelKey)} <span className="font-mono text-xs opacity-60">{counts.overlap}</span>
          </FilterPill>
        </div>

        {!filtered && <p className="text-sm text-muted">{t("pairs.loading")}</p>}

        {filtered && filtered.length === 0 && (
          <div className="flex min-h-70 flex-col items-center justify-center rounded-2xl border border-dashed border-border-strong text-center">
            <p className="text-[15px] font-medium text-foreground">{t("pairs.noMatch")}</p>
            <p className="mt-1 text-sm text-muted">{t("pairs.tryDifferentFilter")}</p>
          </div>
        )}

        {filtered && filtered.length > 0 && (
          <div className="space-y-3">
            {filtered.map((pair, i) => (
              <PairCard key={`${pair.tiger_a}-${pair.tiger_b}`} pair={pair} index={i} byId={byId} onOpenTiger={onOpenTiger} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function FilterPill({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors ${
        active
          ? "border-accent-strong bg-accent text-accent-foreground"
          : "border-border text-muted hover:border-border-strong hover:text-foreground"
      }`}
    >
      {children}
    </button>
  );
}

function PairCard({
  pair,
  index,
  byId,
  onOpenTiger,
}: {
  pair: ClassifiedPair;
  index: number;
  byId: Map<string, GalleryIndividual>;
  onOpenTiger: (tigerId: string) => void;
}) {
  const { t } = useLanguage();
  const style = KIND_STYLE[pair.kind];
  const Icon = style.icon;
  const a = byId.get(pair.tiger_a);
  const b = byId.get(pair.tiger_b);

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.03, 0.3) }}
      className="flex items-start gap-4 rounded-xl border border-border bg-surface p-4"
    >
      <div className="flex shrink-0 -space-x-3">
        <TigerAvatar tiger={a} tigerId={pair.tiger_a} onOpenTiger={onOpenTiger} />
        <TigerAvatar tiger={b} tigerId={pair.tiger_b} onOpenTiger={onOpenTiger} />
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <button onClick={() => onOpenTiger(pair.tiger_a)} className="font-mono text-sm font-semibold text-foreground hover:underline">
            {pair.tiger_a}
          </button>
          <span className="text-muted">&amp;</span>
          <button onClick={() => onOpenTiger(pair.tiger_b)} className="font-mono text-sm font-semibold text-foreground hover:underline">
            {pair.tiger_b}
          </button>
          <span className={`ml-1 flex items-center gap-1 rounded-full px-2 py-0.5 font-mono text-[10px] font-semibold uppercase tracking-wide ${style.bg} ${style.text}`}>
            <Icon size={11} weight="fill" />
            {t(style.labelKey)}
          </span>
        </div>

        <p className="mt-1.5 text-xs text-muted">
          {t("pairs.coOccurrences", { count: pair.co_occurrences })} &middot; {t("pairs.withinWindow", { hours: WINDOW_HOURS })}
        </p>

        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <Camera size={12} className="text-muted" />
          {pair.shared_stations.map((s) => (
            <span key={s} className="rounded-full bg-surface-sunken px-2 py-0.5 font-mono text-[11px] text-muted">
              {s}
            </span>
          ))}
        </div>
      </div>
    </motion.div>
  );
}

function TigerAvatar({
  tiger,
  tigerId,
  onOpenTiger,
}: {
  tiger: GalleryIndividual | undefined;
  tigerId: string;
  onOpenTiger: (tigerId: string) => void;
}) {
  return (
    <button
      onClick={() => onOpenTiger(tigerId)}
      title={tigerId}
      className="h-11 w-11 overflow-hidden rounded-full border-2 border-surface bg-surface-sunken shadow-sm"
    >
      {tiger?.thumbnail ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={tiger.thumbnail} alt={tigerId} className="h-full w-full object-cover" />
      ) : (
        <div className="flex h-full w-full items-center justify-center text-muted">
          <Camera size={14} />
        </div>
      )}
    </button>
  );
}
