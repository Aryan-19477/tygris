import type { ReactNode } from "react";

/**
 * The one card shell for the app. Every view used to hand-roll its own
 * "rounded-xl border bg-surface p-4" or "rounded-2xl border bg-surface p-5"
 * with slightly different values — this is the single definition so density
 * and radius stay consistent everywhere a card appears.
 */
export function Card({
  children,
  padding = "md",
  interactive = false,
  className = "",
  ...rest
}: {
  children: ReactNode;
  padding?: "sm" | "md" | "lg";
  interactive?: boolean;
  className?: string;
} & React.HTMLAttributes<HTMLDivElement>) {
  const paddingClass = { sm: "p-3", md: "p-4", lg: "p-5" }[padding];
  return (
    <div
      className={`rounded-2xl border border-border bg-surface ${paddingClass} ${
        interactive ? "transition-colors hover:border-border-strong" : ""
      } ${className}`}
      {...rest}
    >
      {children}
    </div>
  );
}
