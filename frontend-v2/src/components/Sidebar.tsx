"use client";

import { useState } from "react";
import {
  MapTrifold,
  Bell,
  PawPrint,
  Fingerprint,
  FilmStrip,
  Heart,
  Binoculars,
  Trash,
  GearSix,
  SignOut,
  X,
  CaretDown,
  CaretLeft,
  CaretRight,
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
  { id: "map", key: "nav.map", icon: MapTrifold },
  { id: "identify", key: "nav.identify", icon: Fingerprint },
  { id: "captures", key: "nav.captures", icon: Bell },
  { id: "screening", key: "nav.screening", icon: FilmStrip },
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
        className={`fixed inset-y-0 left-0 z-50 flex h-dvh shrink-0 -translate-x-full flex-col border-r border-nav-border bg-nav text-nav-foreground transition-[transform,width] duration-300 ease-out lg:static lg:translate-x-0 ${
          mobileOpen ? "translate-x-0" : ""
        } ${collapsed ? "w-[76px]" : "w-64"}`}
      >
        <button
          onClick={onMobileClose}
          className="absolute right-3 top-3 flex h-8 w-8 items-center justify-center rounded-full text-nav-muted hover:bg-nav-active-bg/60 hover:text-nav-foreground lg:hidden"
        >
          <X size={16} />
        </button>

        <button
          onClick={() => setCollapsed((v) => !v)}
          title={collapsed ? t("nav.expand") : t("nav.collapse")}
          className="absolute -right-3 top-8 z-10 hidden h-6 w-6 items-center justify-center rounded-full border border-nav-border bg-surface text-muted shadow-sm hover:text-foreground lg:flex"
        >
          {collapsed ? <CaretRight size={12} weight="bold" /> : <CaretLeft size={12} weight="bold" />}
        </button>

        <div className={`flex items-center gap-3 px-6 py-6 ${collapsed ? "justify-center px-0" : ""}`}>
          <svg
            viewBox="0 0 40 40"
            className="h-9 w-9 shrink-0"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <circle cx="20" cy="20" r="19" stroke="var(--nav-active)" strokeWidth="1" />
            <circle cx="20" cy="20" r="15.5" stroke="var(--nav-active)" strokeWidth="0.6" opacity="0.5" />
            <path
              d="M14 27V13h5.6c2.9 0 4.9 1.8 4.9 4.4 0 2.6-2 4.4-4.9 4.4H17v5.2h-3Zm3-7.6h2.3c1.3 0 2.1-.7 2.1-2s-.8-2-2.1-2H17v4Z"
              fill="var(--nav-active)"
            />
          </svg>
          {!collapsed && (
            <div className="min-w-0">
              <div className="font-mono text-[13px] font-semibold uppercase leading-tight tracking-wider text-nav-foreground">
                Pench
                <br />
                Intelligence
              </div>
              <div className="mt-1 text-[11px] text-nav-muted">{t("nav.department")}</div>
            </div>
          )}
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto px-3 pt-4">
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
                  className={`flex w-full items-center gap-3 rounded-xl border-2 px-3 py-2.5 text-left text-sm font-semibold transition-all ${
                    collapsed ? "justify-center px-0" : ""
                  } ${
                    active
                      ? "border-nav-active bg-nav-active-bg text-nav-active shadow-sm"
                      : "border-transparent text-nav-muted hover:border-nav-border hover:bg-nav-active-bg/50 hover:text-nav-foreground"
                  }`}
                >
                  <Icon size={17} weight={active ? "fill" : "regular"} />
                  {!collapsed && <span className="flex-1">{t(entry.key)}</span>}
                  {!collapsed && entry.id === "captures" && attentionCount > 0 && (
                    <span
                      className={`flex h-5 min-w-5 items-center justify-center rounded-full px-1 font-mono text-[11px] font-medium ${
                        active ? "bg-nav-active text-nav" : "bg-priority-high text-white"
                      }`}
                    >
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
              <div key={entry.groupKey}>
                <button
                  onClick={() => (collapsed ? setCollapsed(false) : toggleGroup(entry.groupKey))}
                  title={collapsed ? t(entry.groupKey) : undefined}
                  className={`flex w-full items-center gap-3 rounded-xl border-2 px-3 py-2.5 text-left text-sm font-semibold transition-all ${
                    collapsed ? "justify-center px-0" : ""
                  } ${
                    hasActiveChild
                      ? "border-transparent bg-nav-active-bg/60 text-nav-foreground"
                      : "border-transparent text-nav-muted hover:bg-nav-active-bg/50 hover:text-nav-foreground"
                  }`}
                >
                  <GroupIcon size={17} weight={hasActiveChild ? "fill" : "regular"} />
                  {!collapsed && (
                    <>
                      <span className="flex-1">{t(entry.groupKey)}</span>
                      <CaretDown
                        size={13}
                        weight="bold"
                        className={`transition-transform duration-200 ${open ? "rotate-180" : ""}`}
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
                      <div className="relative ml-[22px] mt-1 space-y-0.5 border-l border-nav-border py-1 pl-4">
                        {entry.children.map((child) => {
                          const ChildIcon = child.icon;
                          const active = view === child.id;
                          return (
                            <button
                              key={child.id}
                              onClick={() => {
                                onNavigate(child.id);
                                onMobileClose?.();
                              }}
                              className={`flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left text-[13px] transition-colors ${
                                active
                                  ? "bg-nav-active-bg font-semibold text-nav-active"
                                  : "text-nav-muted hover:bg-nav-active-bg/50 hover:text-nav-foreground"
                              }`}
                            >
                              <ChildIcon size={14} weight={active ? "fill" : "regular"} />
                              <span className="flex-1 truncate">{t(child.key)}</span>
                              {active && <CaretRight size={12} weight="bold" />}
                            </button>
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

        <div className="border-t border-nav-border px-3 py-4">
          {!collapsed && (
            <button className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm text-nav-muted transition-colors hover:bg-nav-active-bg/60 hover:text-nav-foreground">
              <SignOut size={16} />
              {t("nav.logout")}
            </button>
          )}
          {!collapsed ? (
            <div className="mt-2 flex items-center gap-3 rounded-lg px-3 py-2">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-nav-active-bg font-mono text-xs font-medium text-nav-active">
                RO
              </div>
              <div className="min-w-0">
                <div className="truncate text-[13px] font-medium text-nav-foreground">
                  {t("nav.roleName")}
                </div>
                <div className="truncate text-[11px] text-nav-muted">
                  {t("nav.department")}
                </div>
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-center rounded-lg py-2">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-nav-active-bg font-mono text-xs font-medium text-nav-active">
                RO
              </div>
            </div>
          )}
        </div>
      </aside>
    </>
  );
}
