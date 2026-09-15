"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { dictionaries, type Locale } from "./translations";

const STORAGE_KEY = "pench-intelligence-language";

type Vars = Record<string, string | number>;

interface LanguageContextValue {
  language: Locale;
  setLanguage: (locale: Locale) => void;
  t: (key: string, vars?: Vars) => string;
}

const LanguageContext = createContext<LanguageContextValue | null>(null);

function resolve(dict: Record<string, unknown>, key: string): string | undefined {
  let node: unknown = dict;
  for (const part of key.split(".")) {
    if (typeof node !== "object" || node === null) return undefined;
    node = (node as Record<string, unknown>)[part];
  }
  return typeof node === "string" ? node : undefined;
}

function interpolate(template: string, vars?: Vars): string {
  if (!vars) return template;
  return template.replace(/\{\{(\w+)\}\}/g, (match, name) =>
    name in vars ? String(vars[name]) : match
  );
}

export function LanguageProvider({ children }: { children: React.ReactNode }) {
  const [language, setLanguageState] = useState<Locale>("en");

  useEffect(() => {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored === "en" || stored === "hi" || stored === "mr") {
      setLanguageState(stored);
    }
  }, []);

  useEffect(() => {
    document.documentElement.lang = language;
    window.localStorage.setItem(STORAGE_KEY, language);
  }, [language]);

  const setLanguage = useCallback((locale: Locale) => {
    setLanguageState(locale);
  }, []);

  const t = useCallback(
    (key: string, vars?: Vars) => {
      const template = resolve(dictionaries[language], key) ?? resolve(dictionaries.en, key) ?? key;
      return interpolate(template, vars);
    },
    [language]
  );

  const value = useMemo(() => ({ language, setLanguage, t }), [language, setLanguage, t]);

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) {
    throw new Error("useLanguage must be used within LanguageProvider");
  }
  return ctx;
}
