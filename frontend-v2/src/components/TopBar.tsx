"use client";

import { useState } from "react";
import { Bell, UserCircle, SignOut } from "@phosphor-icons/react";
import { useNavigation } from "@/lib/navigation-context";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import VoiceAgentButton from "./VoiceAgentButton";
import { LanguageSwitcher } from "./LanguageSwitcher";

export function TopBar({
  title,
  subtitle,
  alertCount,
  right,
}: {
  title: string;
  subtitle: string;
  alertCount: number;
  right?: React.ReactNode;
}) {
  const { navigate } = useNavigation();
  const { t } = useLanguage();
  const [accountOpen, setAccountOpen] = useState(false);

  return (
    <div className="flex flex-wrap items-start justify-between gap-4 border-b border-border px-5 py-5 sm:gap-6 sm:px-8 sm:py-6">
      <div>
        <h1 className="font-serif text-2xl font-medium tracking-tight text-foreground sm:text-3xl">
          {title}
        </h1>
        <p className="mt-1 text-sm text-muted sm:text-[15px]">{subtitle}</p>
      </div>

      <div className="flex shrink-0 items-center gap-3 sm:gap-4">
        {right}
        <VoiceAgentButton />
        <LanguageSwitcher />
        <button
          onClick={() => navigate("captures")}
          title={t("nav.captures")}
          className="relative flex h-9 w-9 items-center justify-center rounded-full border border-border bg-surface text-muted transition-colors hover:border-border-strong hover:text-foreground"
        >
          <Bell size={16} />
          {alertCount > 0 && (
            <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-priority-high px-1 font-mono text-[10px] font-medium text-white">
              {alertCount}
            </span>
          )}
        </button>

        <div className="relative hidden sm:block">
          <button
            onClick={() => setAccountOpen((v) => !v)}
            title={t("topbar.account")}
            className={`flex h-9 w-9 items-center justify-center rounded-full border transition-colors ${
              accountOpen
                ? "border-accent bg-accent-soft text-accent"
                : "border-border bg-surface text-muted hover:border-border-strong hover:text-foreground"
            }`}
          >
            <UserCircle size={18} />
          </button>

          {accountOpen && (
            <>
              <div className="fixed inset-0 z-40" onClick={() => setAccountOpen(false)} />
              <div className="absolute right-0 top-11 z-50 w-56 overflow-hidden rounded-xl border border-border bg-surface shadow-lg">
                <div className="border-b border-border px-4 py-3">
                  <div className="text-sm font-medium text-foreground">{t("nav.roleName")}</div>
                  <div className="text-xs text-muted">{t("nav.department")}</div>
                </div>
                <button
                  onClick={() => {
                    navigate("settings");
                    setAccountOpen(false);
                  }}
                  className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm text-foreground hover:bg-surface-sunken"
                >
                  <UserCircle size={15} className="text-muted" />
                  {t("nav.settings")}
                </button>
                <button
                  className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm text-danger hover:bg-danger-soft"
                >
                  <SignOut size={15} />
                  {t("topbar.logout")}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
