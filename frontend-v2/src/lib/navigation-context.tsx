"use client";

import { createContext, useContext } from "react";
import type { View } from "@/components/AppShell";

interface NavigationContextValue {
  navigate: (view: View) => void;
}

export const NavigationContext = createContext<NavigationContextValue | null>(null);

/**
 * Lets shared chrome (TopBar's alert bell, etc.) trigger navigation without
 * every view threading an onNavigate prop down from AppShell — the
 * component tree is 7 views deep for this one cross-cutting concern.
 */
export function useNavigation() {
  const ctx = useContext(NavigationContext);
  if (!ctx) {
    throw new Error("useNavigation must be used within AppShell's NavigationContext.Provider");
  }
  return ctx;
}
