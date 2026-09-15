import type { ReactNode } from "react";

/** The dashed-border centered placeholder pattern — used for "queue is
 * clear", "select an item", "no results", etc. across every list view. */
export function EmptyState({
  icon,
  title,
  subtitle,
  tone = "neutral",
}: {
  icon?: ReactNode;
  title: string;
  subtitle?: string;
  tone?: "neutral" | "positive";
}) {
  return (
    <div className="flex min-h-64 flex-col items-center justify-center rounded-2xl border border-dashed border-border-strong text-center">
      {icon && (
        <div
          className={`flex h-12 w-12 items-center justify-center rounded-full ${
            tone === "positive" ? "bg-positive-soft text-positive" : "text-muted"
          }`}
        >
          {icon}
        </div>
      )}
      <p className={`mt-3 text-[15px] font-medium ${tone === "positive" ? "text-foreground" : "text-muted"}`}>{title}</p>
      {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
    </div>
  );
}
