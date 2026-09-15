import type { ReactNode } from "react";

/** The "eyebrow" label pattern (font-mono, uppercase, tracked) repeated by
 * hand in nearly every view — one place to define it. */
export function SectionLabel({ children, icon, className = "" }: { children: ReactNode; icon?: ReactNode; className?: string }) {
  return (
    <div className={`flex items-center gap-2 font-mono text-2xs uppercase tracking-wide text-muted ${className}`}>
      {icon}
      {children}
    </div>
  );
}
