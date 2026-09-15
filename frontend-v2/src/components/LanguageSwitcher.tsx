"use client";

import { useState } from "react";
import { Translate, Check } from "@phosphor-icons/react";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import type { Locale } from "@/lib/i18n/translations";

const OPTIONS: { code: Locale; short: string }[] = [
  { code: "en", short: "EN" },
  { code: "hi", short: "हिं" },
  { code: "mr", short: "मरा" },
];

export function LanguageSwitcher() {
  const { language, setLanguage, t } = useLanguage();
  const [open, setOpen] = useState(false);

  const current = OPTIONS.find((o) => o.code === language) ?? OPTIONS[0];

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        title={t("language.label")}
        className={`flex h-9 items-center gap-1.5 rounded-full border px-3 text-xs font-semibold transition-colors ${
          open
            ? "border-accent bg-accent-soft text-accent"
            : "border-border bg-surface text-muted hover:border-border-strong hover:text-foreground"
        }`}
      >
        <Translate size={15} />
        <span>{current.short}</span>
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 top-11 z-50 w-44 overflow-hidden rounded-xl border border-border bg-surface shadow-lg">
            <div className="border-b border-border px-4 py-2.5 font-mono text-[11px] uppercase tracking-wide text-muted">
              {t("language.label")}
            </div>
            {OPTIONS.map((opt) => (
              <button
                key={opt.code}
                onClick={() => {
                  setLanguage(opt.code);
                  setOpen(false);
                }}
                className="flex w-full items-center justify-between px-4 py-2.5 text-left text-sm text-foreground hover:bg-surface-sunken"
              >
                <span>{t(`language.${opt.code}`)}</span>
                {language === opt.code && <Check size={15} className="text-accent" weight="bold" />}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
