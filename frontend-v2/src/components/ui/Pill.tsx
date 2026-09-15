import type { ReactNode } from "react";

const TONES = {
  positive: "bg-positive-soft text-positive",
  caution: "bg-caution-soft text-caution",
  danger: "bg-danger-soft text-danger",
  accent: "bg-accent-soft text-accent",
  neutral: "bg-surface-sunken text-muted",
} as const;

/** The status/urgency badge pattern — rounded pill, mono micro-label,
 * uppercase, tracked. One definition instead of one per view. */
export function Pill({
  children,
  tone = "neutral",
  className = "",
}: {
  children: ReactNode;
  tone?: keyof typeof TONES;
  className?: string;
}) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 font-mono text-2xs font-semibold uppercase tracking-wide ${TONES[tone]} ${className}`}
    >
      {children}
    </span>
  );
}
