"use client";

import { useState } from "react";
import {
  House,
  MapTrifold,
  Bell,
  PawPrint,
  Fingerprint,
  Heart,
  Binoculars,
  Trash,
  GearSix,
  SignOut,
  X,
  CaretDown,
  CaretLeft,
  CaretRight,
  MagnifyingGlass,
  ChartBar,
  CheckCircle,
} from "@phosphor-icons/react";
import type { View } from "./AppShell";
import { useLanguage } from "@/lib/i18n/LanguageContext";

type LeafItem = { id: View; key: string; icon: typeof MapTrifold };
type GroupItem = { groupKey: string; icon: typeof MapTrifold; children: LeafItem[] };
type NavEntry = LeafItem | GroupItem;

function isGroup(entry: NavEntry): entry is GroupItem {
  return "children" in entry;
}

// Attention Queue and Station Health used to be separate top-level pages;
// they're now one "Captures" screen (see views/CapturesView.tsx) that reads
// the same review-queue/alerts/stations data and lets a station chip filter
// the queue instead of navigating away. Pass 1 Screening and Blank Frame
// Trash stay separate for now (one's an upload tool, the other has no real
// backend yet) — see docs/ux-mockups/platform-roadmap.html for the planned
// next folds. Pairs & Family Groups joins the catalogue and ranger reports
// under "Population".
const NAV: NavEntry[] = [
  { id: "home", key: "nav.home", icon: House },
  { id: "map", key: "nav.map", icon: MapTrifold },
  { id: "identify", key: "nav.identify", icon: Fingerprint },
  { id: "captures", key: "nav.captures", icon: Bell },
  { id: "trash", key: "nav.trash", icon: Trash },
  {
    groupKey: "nav.population",
    icon: PawPrint,
    children: [
      { id: "catalogue", key: "nav.catalogue", icon: PawPrint },
      { id: "pairs", key: "nav.pairs", icon: Heart },
      { id: "rangerReports", key: "nav.rangerReports", icon: Binoculars },
    ],
  },
  {
    groupKey: "nav.preyIntelligence",
    icon: Binoculars,
    children: [
      { id: "preyChecker", key: "nav.preyChecker", icon: MagnifyingGlass },
      { id: "preyInsights", key: "nav.preyInsights", icon: ChartBar },
      { id: "preyReview", key: "nav.preyReview", icon: CheckCircle },
    ],
  },
  { id: "settings", key: "nav.settings", icon: GearSix },
];

export function Sidebar({
  view,
  onNavigate,
  attentionCount,
  mobileOpen = false,
  onMobileClose,
}: {
  view: View;
  onNavigate: (v: View) => void;
  attentionCount: number;
  mobileOpen?: boolean;
  onMobileClose?: () => void;
}) {
  const { t } = useLanguage();
  const [collapsed, setCollapsed] = useState(false);
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({
    "nav.population": true,
    "nav.preyIntelligence": true,
  });

  const toggleGroup = (key: string) =>
    setOpenGroups((prev) => ({ ...prev, [key]: !prev[key] }));

  return (
    <>
      {mobileOpen && (
        <div
          onClick={onMobileClose}
          className="fixed inset-0 z-40 bg-foreground/40 backdrop-blur-sm lg:hidden"
        />
      )}
      <aside
        className={`fixed inset-y-0 left-0 z-50 flex h-dvh shrink-0 -translate-x-full flex-col border-r border-zinc-200/80 bg-white text-zinc-900 transition-[transform,width] duration-300 ease-out lg:static lg:translate-x-0 ${
          mobileOpen ? "translate-x-0" : ""
        } ${collapsed ? "w-[76px]" : "w-64"}`}
      >
        <button
          onClick={onMobileClose}
          className="absolute right-3 top-3 flex h-8 w-8 items-center justify-center rounded-full text-zinc-400 hover:bg-zinc-100 hover:text-zinc-700 lg:hidden"
        >
          <X size={16} />
        </button>

        {/* Brand Header */}
        <div className={`flex items-center gap-3 px-3.5 pt-4 pb-2.5 ${collapsed ? "justify-center px-2 flex-col gap-2 pt-4" : ""}`}>
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-zinc-900 text-white shadow-md transition-transform hover:scale-[1.02]">
            <svg viewBox="0 0 24 24" className="h-6 w-6 text-white" fill="none">
              <circle cx="12" cy="12" r="8.5" stroke="currentColor" strokeWidth="2.2" />
              <circle cx="12" cy="12" r="3.2" fill="currentColor" />
            </svg>
          </div>
          {!collapsed ? (
            <>
              <div className="min-w-0 flex-1">
                <div className="font-bold text-sm tracking-tight text-zinc-900 leading-tight">
                  Pench Intelligence
                </div>
                <div className="text-[11px] text-zinc-400 font-medium">
                  {t("nav.department")}
                </div>
              </div>
              <button
                onClick={() => setCollapsed(true)}
                title={t("nav.collapse")}
                className="hidden lg:flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-zinc-200 bg-white text-zinc-400 shadow-2xs hover:border-zinc-300 hover:text-zinc-800 transition-all active:scale-95"
              >
                <CaretLeft size={13} weight="bold" />
              </button>
            </>
          ) : (
            <button
              onClick={() => setCollapsed(false)}
              title={t("nav.expand")}
              className="hidden lg:flex h-6 w-6 items-center justify-center rounded-full border border-zinc-200 bg-white text-zinc-400 shadow-2xs hover:border-zinc-300 hover:text-zinc-800 transition-all active:scale-95"
            >
              <CaretRight size={12} weight="bold" />
            </button>
          )}
        </div>

        {/* Navigation Items */}
        <nav className="flex-1 space-y-1 overflow-y-auto px-3 pt-2">
          {NAV.map((entry) => {
            if (!isGroup(entry)) {
              const Icon = entry.icon;
              const active = view === entry.id || (entry.id === "map" && view === "dossier");
              return (
                <button
                  key={entry.id}
                  onClick={() => {
                    onNavigate(entry.id);
                    onMobileClose?.();
                  }}
                  title={collapsed ? t(entry.key) : undefined}
                  className={`group flex w-full items-center gap-3 rounded-2xl px-3.5 py-2.5 text-left text-sm transition-all duration-150 ${
                    collapsed ? "justify-center px-0" : ""
                  } ${
                    active
                      ? "bg-zinc-100 font-semibold text-zinc-900 shadow-2xs"
                      : "text-zinc-600 font-medium hover:bg-zinc-100/70 hover:text-zinc-950"
                  }`}
                >
                  <Icon
                    size={18}
                    weight={active ? "fill" : "regular"}
                    className={`shrink-0 transition-colors ${
                      active ? "text-zinc-900" : "text-zinc-500 group-hover:text-zinc-800"
                    }`}
                  />
                  {!collapsed && <span className="flex-1 truncate">{t(entry.key)}</span>}
                  {!collapsed && entry.id === "captures" && attentionCount > 0 && (
                    <span className="flex h-5 min-w-5 items-center justify-center rounded-lg bg-emerald-100 px-2 font-mono text-xs font-bold text-emerald-800 shadow-2xs">
                      {attentionCount}
                    </span>
                  )}
                </button>
              );
            }

            const GroupIcon = entry.icon;
            const hasActiveChild = entry.children.some((c) => c.id === view);
            const open = collapsed ? true : openGroups[entry.groupKey];

            return (
              <div key={entry.groupKey} className="space-y-0.5">
                <button
                  onClick={() => (collapsed ? setCollapsed(false) : toggleGroup(entry.groupKey))}
                  title={collapsed ? t(entry.groupKey) : undefined}
                  className={`group flex w-full items-center gap-3 rounded-2xl px-3.5 py-2.5 text-left text-sm transition-all duration-150 ${
                    collapsed ? "justify-center px-0" : ""
                  } ${
                    hasActiveChild || open
                      ? "bg-zinc-100/70 font-semibold text-zinc-900"
                      : "text-zinc-600 font-medium hover:bg-zinc-100/70 hover:text-zinc-950"
                  }`}
                >
                  <GroupIcon
                    size={18}
                    weight={hasActiveChild ? "fill" : "regular"}
                    className={`shrink-0 transition-colors ${
                      hasActiveChild ? "text-zinc-900" : "text-zinc-500 group-hover:text-zinc-800"
                    }`}
                  />
                  {!collapsed && (
                    <>
                      <span className="flex-1 truncate">{t(entry.groupKey)}</span>
                      <CaretDown
                        size={14}
                        weight="bold"
                        className={`text-zinc-400 transition-transform duration-200 ${
                          open ? "rotate-180" : ""
                        }`}
                      />
                    </>
                  )}
                </button>

                {!collapsed && (
                  <div
                    className="grid overflow-hidden transition-[grid-template-rows] duration-200 ease-out"
                    style={{ gridTemplateRows: open ? "1fr" : "0fr" }}
                  >
                    <div className="min-h-0">
                      <div className="relative ml-6 pl-3.5 py-1 space-y-1">
                        {/* Continuous vertical guide line that terminates at the last child's curve */}
                        <div
                          className="pointer-events-none absolute left-0 top-0 w-px bg-zinc-200"
                          style={{ bottom: "18px" }}
                        />

                        {entry.children.map((child) => {
                          const ChildIcon = child.icon;
                          const active = view === child.id;
                          return (
                            <div key={child.id} className="relative flex items-center">
                              {/* Curved branch connector from vertical line to item */}
                              <div
                                className="pointer-events-none absolute -left-3.5 top-0 w-3.5 border-b border-l border-zinc-200 rounded-bl-lg"
                                style={{ height: "18px" }}
                              />

                              <button
                                onClick={() => {
                                  onNavigate(child.id);
                                  onMobileClose?.();
                                }}
                                className={`flex w-full items-center justify-between rounded-xl px-3 py-2 text-left text-sm transition-all duration-150 ${
                                  active
                                    ? "bg-zinc-100 font-semibold text-zinc-900 shadow-2xs"
                                    : "text-zinc-500 font-medium hover:bg-zinc-100/60 hover:text-zinc-900"
                                }`}
                              >
                                <div className="flex items-center gap-2 truncate">
                                  <ChildIcon
                                    size={14}
                                    weight={active ? "fill" : "regular"}
                                    className={`shrink-0 ${active ? "text-zinc-900" : "text-zinc-400"}`}
                                  />
                                  <span className="truncate">{t(child.key)}</span>
                                </div>
                                {active && (
                                  <CaretRight
                                    size={12}
                                    weight="bold"
                                    className="text-zinc-500 shrink-0 ml-1.5"
                                  />
                                )}
                              </button>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </nav>

        {/* User Profile Footer */}
        <div className="border-t border-zinc-100 p-3">
          {!collapsed ? (
            <div className="flex items-center justify-between rounded-2xl border border-zinc-200/60 bg-zinc-50/70 p-2.5 transition-colors hover:bg-zinc-100/70">
              <div className="flex items-center gap-2.5 min-w-0">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-zinc-900 font-mono text-xs font-bold text-white shadow-2xs">
                  RO
                </div>
                <div className="min-w-0">
                  <div className="truncate text-xs font-semibold text-zinc-900">
                    {t("nav.roleName")}
                  </div>
                  <div className="truncate text-[10px] text-zinc-500">
                    {t("nav.department")}
                  </div>
                </div>
              </div>
              <button
                title={t("nav.logout")}
                className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-zinc-400 hover:bg-zinc-200/60 hover:text-danger transition-colors"
              >
                <SignOut size={14} />
              </button>
            </div>
          ) : (
            <div className="flex items-center justify-center py-1">
              <div
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-zinc-900 font-mono text-xs font-bold text-white shadow-2xs"
                title={t("nav.roleName")}
              >
                RO
              </div>
            </div>
          )}
        </div>
      </aside>
    </>
  );
}
