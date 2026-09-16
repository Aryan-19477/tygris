"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { List } from "@phosphor-icons/react";
import { Sidebar } from "./Sidebar";
import { HomeView } from "./views/HomeView";
import { ReserveMapView } from "./views/ReserveMapView";
import { CapturesView } from "./views/CapturesView";
import { TigerCatalogueView } from "./views/TigerCatalogueView";
import { TigerDossierView } from "./views/TigerDossierView";
import { RangerReportsView } from "./views/RangerReportsView";
import { PairsView } from "./views/PairsView";
import { IdentifyView } from "./views/IdentifyView";
import { SettingsView } from "./views/SettingsView";
import { BlankFrameTrashView } from "./views/BlankFrameTrashView";
import ChatAssistantPanel from "./ChatAssistantPanel";
import { api, type Stats } from "@/lib/api";
import { NavigationContext } from "@/lib/navigation-context";
import { LanguageProvider } from "@/lib/i18n/LanguageContext";

export type View =
  | "home"
  | "map"
  | "captures"
  | "catalogue"
  | "pairs"
  | "dossier"
  | "rangerReports"
  | "identify"
  | "trash"
  | "settings";

export function AppShell() {
  const [view, setView] = useState<View>("home");
  const [selectedTigerId, setSelectedTigerId] = useState<string | null>(null);
  const [stats, setStats] = useState<Stats | null>(null);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  const openTigerDossier = useCallback((tigerId: string) => {
    setSelectedTigerId(tigerId);
    setView("dossier");
  }, []);

  const navigate = useCallback((v: View) => {
    if (v !== "dossier") setSelectedTigerId(null);
    setView(v);
  }, []);

  const refreshStats = useCallback(() => {
    api.stats().then(setStats).catch(() => {});
  }, []);

  useEffect(() => {
    refreshStats();
    const interval = setInterval(refreshStats, 15000);
    return () => clearInterval(interval);
  }, [refreshStats]);

  const attentionCount = stats?.pending_review ?? 0;
  const navigationValue = useMemo(() => ({ navigate }), [navigate]);

  return (
    <LanguageProvider>
    <NavigationContext.Provider value={navigationValue}>
      <div className="flex h-dvh overflow-hidden bg-background">
        <Sidebar
          view={view}
          onNavigate={navigate}
          attentionCount={attentionCount}
          mobileOpen={mobileNavOpen}
          onMobileClose={() => setMobileNavOpen(false)}
        />
        <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
          <div className="flex items-center gap-3 border-b border-nav-border bg-nav px-4 py-3 lg:hidden">
            <button
              data-testid="mobile-nav-toggle"
              onClick={() => setMobileNavOpen(true)}
              className="flex h-9 w-9 items-center justify-center rounded-full border border-nav-border text-nav-muted hover:text-nav-foreground"
            >
              <List size={16} />
            </button>
            <span className="font-mono text-xs font-semibold uppercase tracking-wider text-nav-foreground">
              Pench Intelligence
            </span>
          </div>
          <main className={`flex-1 ${view === "home" ? "overflow-hidden" : "overflow-y-auto"}`}>
            {view === "home" && <HomeView stats={stats} onOpenTiger={openTigerDossier} />}
            {view === "map" && (
              <ReserveMapView onOpenTiger={openTigerDossier} stats={stats} />
            )}
            {view === "captures" && (
              <CapturesView stats={stats} onResolved={refreshStats} />
            )}
            {view === "catalogue" && (
              <TigerCatalogueView stats={stats} onOpenTiger={openTigerDossier} />
            )}
            {view === "pairs" && (
              <PairsView stats={stats} onOpenTiger={openTigerDossier} />
            )}
            {view === "dossier" && selectedTigerId && (
              <TigerDossierView
                key={selectedTigerId}
                tigerId={selectedTigerId}
                stats={stats}
                onBack={() => navigate("map")}
                onNavigateToMap={() => navigate("map")}
              />
            )}
            {view === "rangerReports" && <RangerReportsView stats={stats} />}
            {view === "identify" && <IdentifyView stats={stats} />}
            {view === "trash" && <BlankFrameTrashView stats={stats} />}
            {view === "settings" && <SettingsView />}
          </main>
        </div>
      </div>
      <ChatAssistantPanel />
    </NavigationContext.Provider>
    </LanguageProvider>
  );
}
