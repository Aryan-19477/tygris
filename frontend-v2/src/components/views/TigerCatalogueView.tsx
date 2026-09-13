"use client";

import { useEffect, useMemo, useState } from "react";
import { motion } from "motion/react";
import {
  MagnifyingGlass,
  MapPin,
  Camera,
} from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { api, type GalleryIndividual, type Stats } from "@/lib/api";

type FilterKey = "all" | "recent" | "multi-station";

export function TigerCatalogueView({
  stats,
  onOpenTiger,
}: {
  stats: Stats | null;
  onOpenTiger: (tigerId: string) => void;
}) {
  const [individuals, setIndividuals] = useState<GalleryIndividual[] | null>(null);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<FilterKey>("all");

  useEffect(() => {
    api.gallery().then((res) =>
      setIndividuals([...res.individuals].sort((a, b) => a.tiger_id.localeCompare(b.tiger_id)))
    );
  }, []);

  const filtered = useMemo(() => {
    if (!individuals) return null;
    let list = individuals;
    if (filter === "recent") {
      list = [...list].sort((a, b) => (b.last_seen ?? "").localeCompare(a.last_seen ?? "")).slice(0, 24);
    }
    if (filter === "multi-station") {
      list = list.filter((i) => (i.stations ?? []).length > 1);
    }
    if (query) {
      list = list.filter((i) => i.tiger_id.toLowerCase().includes(query.toLowerCase()));
    }
    return list;
  }, [individuals, filter, query]);

  return (
    <div>
      <TopBar
        title="Tiger Catalogue"
        subtitle={individuals ? `${individuals.length} identified individuals` : "Loading catalogue..."}
        alertCount={stats?.pending_review ?? 0}
        right={
          <div className="relative">
            <MagnifyingGlass size={15} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search ID"
              className="w-56 rounded-full border border-border bg-surface py-2 pl-9 pr-4 text-sm text-foreground placeholder:text-muted focus:border-accent focus:outline-none"
            />
          </div>
        }
      />

      <div className="px-8 py-6">
        <div className="mb-6 flex flex-wrap items-center gap-2">
          <FilterPill active={filter === "all"} onClick={() => setFilter("all")}>All</FilterPill>
          <FilterPill active={filter === "recent"} onClick={() => setFilter("recent")}>Recently seen</FilterPill>
          <FilterPill active={filter === "multi-station"} onClick={() => setFilter("multi-station")}>Multiple stations</FilterPill>
        </div>

        {!filtered && <TigerGridSkeleton />}

        {filtered && filtered.length === 0 && (
          <div className="flex min-h-70 flex-col items-center justify-center rounded-2xl border border-dashed border-border-strong text-center">
            <p className="text-[15px] font-medium text-foreground">No individuals match</p>
            <p className="mt-1 text-sm text-muted">Try a different filter</p>
          </div>
        )}

        {filtered && filtered.length > 0 && (
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {filtered.map((ind, i) => (
              <TigerCard key={ind.tiger_id} individual={ind} index={i} onSelect={() => onOpenTiger(ind.tiger_id)} />
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
      className={`rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors ${
        active
          ? "border-accent-strong bg-accent text-accent-foreground"
          : "border-border text-muted hover:border-border-strong hover:text-foreground"
      }`}
    >
      {children}
    </button>
  );
}

function TigerCard({ individual, index, onSelect }: { individual: GalleryIndividual; index: number; onSelect: () => void }) {
  return (
    <motion.button
      onClick={onSelect}
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, delay: Math.min(index * 0.03, 0.4), ease: [0.16, 1, 0.3, 1] }}
      className="group overflow-hidden rounded-xl border border-border bg-surface text-left transition-shadow hover:shadow-lg"
    >
      <div className="relative aspect-4/3 overflow-hidden bg-surface-sunken">
        {individual.thumbnail ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={individual.thumbnail}
            alt={individual.tiger_id}
            className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-105"
          />
        ) : (
          <div className="flex h-full items-center justify-center text-muted">
            <Camera size={24} />
          </div>
        )}
      </div>
      <div className="p-4">
        <div className="font-mono text-base font-semibold text-foreground">{individual.tiger_id}</div>
        <div className="mt-2 flex items-center justify-between border-t border-border pt-2.5 text-xs text-muted">
          <span className="flex items-center gap-1">
            <Camera size={12} />
            {individual.num_captures} captures
          </span>
          <span className="flex items-center gap-1">
            <MapPin size={12} />
            {(individual.stations ?? []).length} stations
          </span>
        </div>
      </div>
    </motion.button>
  );
}

function TigerGridSkeleton() {
  return (
    <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {Array.from({ length: 8 }).map((_, i) => (
        <div key={i} className="overflow-hidden rounded-xl border border-border">
          <div className="aspect-4/3 animate-pulse bg-surface-sunken" />
          <div className="space-y-2 p-4">
            <div className="h-4 w-20 animate-pulse rounded bg-surface-sunken" />
            <div className="h-3 w-full animate-pulse rounded bg-surface-sunken" />
          </div>
        </div>
      ))}
    </div>
  );
}
