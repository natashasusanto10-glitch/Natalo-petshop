import type { ReactNode } from "react";

// Match homepage card widths using the available space, including sidebars.
export const PRODUCT_GRID_CLASS = "grid grid-cols-2 gap-2 sm:gap-2.5 sm:[grid-template-columns:repeat(auto-fill,minmax(180px,1fr))]";

export function ProductGrid({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={PRODUCT_GRID_CLASS + " " + className}>{children}</div>;
}
