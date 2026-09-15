/** The 4-across stat-block pattern (label, big number, optional hint,
 * optional caution tone) — was redefined per view with drifting padding
 * and radius. One definition, used by every dashboard-style page. */
export function StatCard({
  label,
  value,
  tone,
  hint,
}: {
  label: string;
  value: number | string | undefined;
  tone?: "caution";
  hint?: string;
}) {
  const isCaution = tone === "caution" && Boolean(value) && value !== 0;
  return (
    <div
      className={`relative overflow-hidden rounded-xl border p-4 ${
        isCaution ? "border-caution/40 bg-caution-soft" : "border-border bg-surface"
      }`}
    >
      {isCaution && <span aria-hidden className="absolute inset-y-0 left-0 w-0.5 bg-caution" />}
      <div className="font-mono text-2xs uppercase tracking-wide text-muted">{label}</div>
      <div
        className={`mt-1.5 font-serif text-3xl font-medium tabular-nums tracking-tight ${
          isCaution ? "text-caution" : "text-foreground"
        }`}
      >
        {value ?? "—"}
      </div>
      {hint && <div className="mt-0.5 text-2xs text-muted">{hint}</div>}
    </div>
  );
}
