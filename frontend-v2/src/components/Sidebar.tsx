"use client";

import {
  MapTrifold,
  Bell,
  PawPrint,
  Camera,
  Fingerprint,
  Trash,
  GearSix,
  SignOut,
  X,
} from "@phosphor-icons/react";
import type { View } from "./AppShell";

const NAV_ITEMS: { id: View; label: string; icon: typeof MapTrifold }[] = [
  { id: "map", label: "Reserve Map", icon: MapTrifold },
  { id: "identify", label: "Identify", icon: Fingerprint },
  { id: "attention", label: "Attention Queue", icon: Bell },
  { id: "catalogue", label: "Tiger Catalogue", icon: PawPrint },
  { id: "stations", label: "Station Health", icon: Camera },
  { id: "trash", label: "Blank Frame Trash", icon: Trash },
  { id: "settings", label: "Settings", icon: GearSix },
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
  return (
    <>
      {mobileOpen && (
        <div
          onClick={onMobileClose}
          className="fixed inset-0 z-40 bg-foreground/40 backdrop-blur-sm lg:hidden"
        />
      )}
      <aside
        className={`fixed inset-y-0 left-0 z-50 flex h-dvh w-64 shrink-0 -translate-x-full flex-col border-r border-nav-border bg-nav text-nav-foreground transition-transform duration-300 ease-out lg:static lg:translate-x-0 ${
          mobileOpen ? "translate-x-0" : ""
        }`}
      >
        <button
          onClick={onMobileClose}
          className="absolute right-3 top-3 flex h-8 w-8 items-center justify-center rounded-full text-nav-muted hover:bg-nav-active-bg/60 hover:text-nav-foreground lg:hidden"
        >
          <X size={16} />
        </button>
        <div className="flex items-center gap-3 px-6 py-6">
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
          <div className="min-w-0">
            <div className="font-mono text-[13px] font-semibold uppercase leading-tight tracking-wider text-nav-foreground">
              Pench
              <br />
              Intelligence
            </div>
            <div className="mt-1 text-[11px] text-nav-muted">Forest Department</div>
          </div>
        </div>

        <nav className="flex-1 space-y-1 px-3 pt-4">
          {NAV_ITEMS.map((item) => {
            const Icon = item.icon;
            const active = view === item.id || (item.id === "map" && view === "dossier");
            return (
              <button
                key={item.id}
                onClick={() => {
                  onNavigate(item.id);
                  onMobileClose?.();
                }}
                className={`flex w-full items-center gap-3 rounded-xl border-2 px-3 py-2.5 text-left text-sm font-semibold transition-all ${
                  active
                    ? "border-nav-active bg-nav-active-bg text-nav-active shadow-sm"
                    : "border-transparent text-nav-muted hover:border-nav-border hover:bg-nav-active-bg/50 hover:text-nav-foreground"
                }`}
              >
                <Icon size={17} weight={active ? "fill" : "regular"} />
                <span className="flex-1">{item.label}</span>
                {item.id === "attention" && attentionCount > 0 && (
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
          })}
        </nav>

        <div className="border-t border-nav-border px-3 py-4">
          <button className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm text-nav-muted transition-colors hover:bg-nav-active-bg/60 hover:text-nav-foreground">
            <SignOut size={16} />
            Logout
          </button>
          <div className="mt-2 flex items-center gap-3 rounded-lg px-3 py-2">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-nav-active-bg font-mono text-xs font-medium text-nav-active">
              RO
            </div>
            <div className="min-w-0">
              <div className="truncate text-[13px] font-medium text-nav-foreground">
                Range Officer
              </div>
              <div className="truncate text-[11px] text-nav-muted">
                Forest Department
              </div>
            </div>
          </div>
        </div>
      </aside>
    </>
  );
}
