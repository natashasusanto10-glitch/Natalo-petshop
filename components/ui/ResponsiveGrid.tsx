import type { ReactNode } from "react";
import { gridColsClass } from "@/lib/responsive";

type Props = {
  children: ReactNode;
  cols?: Parameters<typeof gridColsClass>[0];
  className?: string;
  compact?: boolean;
};

export function ResponsiveGrid({ children, cols, className = "", compact = false }: Props) {
  return (
    <div className={`grid ${compact ? "gap-2 sm:gap-2.5" : "gap-3 sm:gap-4 lg:gap-5"} ${gridColsClass(cols)} ${className}`}>
      {children}
    </div>
  );
}
