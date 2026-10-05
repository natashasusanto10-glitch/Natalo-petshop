"use client";

import { usePathname } from "next/navigation";

export function StoreOnly({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  if (pathname?.startsWith("/admin")) return null;
  // Standalone campaign detail also serves older Flutter embedded browsers.
  if (pathname?.replace(/\/+$/, "") === "/services/kawan-setia") return null;
  return <>{children}</>;
}
