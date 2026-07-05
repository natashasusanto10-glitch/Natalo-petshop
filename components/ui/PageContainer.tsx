// components/ui/PageContainer.tsx
import type { ReactNode } from "react";

type Props = {
  children: ReactNode;
  className?: string;
  as?: "div" | "section" | "main";
  /** When true, drops the max-width (for full-bleed hero rows). */
  wide?: boolean;
};

export function PageContainer({ children, className = "", as = "div", wide = false }: Props) {
  const Tag = as;
  return (
    <Tag
      className={`mx-auto w-full px-[var(--nat-gutter)] ${wide ? "max-w-none" : "max-w-[var(--nat-container)]"} ${className}`}
    >
      {children}
    </Tag>
  );
}
