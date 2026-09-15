"use client";

import { useEffect, useState } from "react";
import { CheckCircle, GearSix, XCircle, SignOut } from "@phosphor-icons/react";
import { TopBar } from "@/components/TopBar";
import { Card, SectionLabel } from "@/components/ui";
import { api } from "@/lib/api";
import { useLanguage } from "@/lib/i18n/LanguageContext";

export function SettingsView() {
  const { t } = useLanguage();
  const [online, setOnline] = useState<boolean | null>(null);
  const [modelStatus, setModelStatus] = useState<{ is_fully_trained: boolean; weights_loaded: Record<string, boolean> } | null>(null);

  useEffect(() => {
    api.stats().then(() => setOnline(true)).catch(() => setOnline(false));
    api.modelStatus().then(setModelStatus).catch(() => {});
  }, []);

  return (
    <div>
      <TopBar title={t("settings.title")} subtitle={t("settings.subtitle")} alertCount={0} />
      <div className="px-8 py-6 space-y-8">
        <section>
          <SectionLabel className="mb-3">{t("settings.account")}</SectionLabel>
          <Card padding="lg" className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-accent-soft font-mono text-sm font-medium text-accent">
                RO
              </div>
              <div>
                <div className="text-sm font-medium text-foreground">{t("nav.roleName")}</div>
                <div className="text-xs text-muted">{t("nav.department")}, Pench Tiger Reserve</div>
              </div>
            </div>
            <button className="flex items-center gap-1.5 rounded-full border border-border-strong px-3.5 py-1.5 text-xs font-medium text-foreground hover:bg-surface-sunken">
              <SignOut size={13} />
              {t("settings.logout")}
            </button>
          </Card>
        </section>

        <section>
          <SectionLabel className="mb-3">{t("settings.systemArchitecture")}</SectionLabel>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <Card padding="lg">
              <div className="mb-3 flex items-center gap-2">
                <GearSix size={16} className="text-muted" />
                <SectionLabel>{t("settings.identificationApi")}</SectionLabel>
              </div>
              <div className="flex items-center gap-2">
                {online === null ? (
                  <span className="text-sm text-muted">{t("settings.checking")}</span>
                ) : online ? (
                  <>
                    <CheckCircle size={16} weight="fill" className="text-positive" />
                    <span className="text-sm font-medium text-foreground">{t("settings.online")}</span>
                  </>
                ) : (
                  <>
                    <XCircle size={16} weight="fill" className="text-danger" />
                    <span className="text-sm font-medium text-foreground">{t("settings.unreachable")}</span>
                  </>
                )}
              </div>
            </Card>

            <Card padding="lg">
              <SectionLabel className="mb-3">{t("settings.modelStatus")}</SectionLabel>
              {modelStatus ? (
                <>
                  <div className="flex items-center gap-2">
                    {modelStatus.is_fully_trained ? (
                      <CheckCircle size={16} weight="fill" className="text-positive" />
                    ) : (
                      <XCircle size={16} weight="fill" className="text-danger" />
                    )}
                    <span className="text-sm font-medium text-foreground">
                      {modelStatus.is_fully_trained ? t("settings.fullyTrained") : t("settings.untrainedPresent")}
                    </span>
                  </div>
                  {!modelStatus.is_fully_trained && (
                    <div className="mt-2 text-xs text-muted">
                      {Object.entries(modelStatus.weights_loaded)
                        .filter(([, loaded]) => !loaded)
                        .map(([stage]) => stage)
                        .join(", ")}{" "}
                      {t("settings.untrainedWeightsSuffix")}
                    </div>
                  )}
                </>
              ) : (
                <span className="text-sm text-muted">{t("settings.checking")}</span>
              )}
            </Card>

            <Card padding="lg">
              <SectionLabel className="mb-3">{t("settings.matchingThresholds")}</SectionLabel>
              <div className="space-y-1.5 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted">{t("settings.autoAccept")}</span>
                  <span className="font-mono text-foreground">0.74 cosine</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted">{t("settings.reviewFloor")}</span>
                  <span className="font-mono text-foreground">0.55 cosine</span>
                </div>
              </div>
            </Card>

            <Card padding="lg">
              <SectionLabel className="mb-3">{t("settings.compute")}</SectionLabel>
              <div className="text-sm text-foreground">NVIDIA RTX 4070 Laptop GPU (WSL2 + CUDA)</div>
            </Card>
          </div>
        </section>
      </div>
    </div>
  );
}
