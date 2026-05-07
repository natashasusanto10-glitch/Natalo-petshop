"use client";

import { usePathname } from "next/navigation";

/**
 * Wrapper untuk komponen yang hanya muncul di halaman customer-facing.
 * Menyembunyikan children di route /admin/* — admin punya UI standalone
 * tanpa header, footer, search bar, dan WhatsApp float.
 */
export function PublicChrome({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  if (pathname?.startsWith("/admin")) return null;
  return <>{children}</>;
}
