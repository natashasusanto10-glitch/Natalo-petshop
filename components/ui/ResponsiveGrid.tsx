import type { ReactNode } from "react";
import { gridColsClass } from "@/lib/responsive";

type Props = {
  children: ReactNode;
  cols?: Parameters<typeof gridColsClass>[0];
  className?: string;
};

export function ResponsiveGrid({ children, cols, className = "" }: Props) {
  return (
    <div className={`grid gap-3 sm:gap-4 lg:gap-5 ${gridColsClass(cols)} ${className}`}>
      {children}
    </div>
  );
}
