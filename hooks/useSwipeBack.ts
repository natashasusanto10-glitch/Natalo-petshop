"use client";

/**
 * Hook untuk auto-toggle iOS swipe-back gesture berdasarkan pathname.
 *
 * Default: enabled di semua route. Disable di pathname yang punya
 * horizontal carousel/swipe gesture sendiri di edge kiri (supaya tidak
 * konflik / accidental back).
 *
 * Pakai di root layout supaya berjalan di semua page.
 */

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { SwipeBack } from "@/lib/native/swipe-back";

/**
 * Pathname yg disable swipe-back. Edit list ini sesuai kebutuhan UX.
 *
 * Alasan disable:
 * - /login, /onboarding: full-screen flow, history.back() bisa keluar
 *   dari onboarding tanpa save state
 * - /checkout: form panjang dengan banyak step, accidental back =
 *   kehilangan input
 * - /products/[slug]: ada ProductImageCarousel dgn scroll-snap horizontal
 *   di edge — gesture konflik
 */
const DISABLE_ON_PATHNAMES: Array<string | RegExp> = [
  "/login",
  /^\/onboarding/,
  /^\/checkout(\/.*)?$/,
  /^\/products\/[^/]+$/, // /products/:slug — single product detail dgn carousel
  /^\/produk\/[^/]+$/, // legacy URL
];

function shouldDisableSwipeBack(pathname: string): boolean {
  return DISABLE_ON_PATHNAMES.some((pattern) =>
    typeof pattern === "string" ? pathname === pattern : pattern.test(pathname),
  );
}

export function useSwipeBack() {
  const pathname = usePathname();

  useEffect(() => {
    if (!pathname) return;
    if (shouldDisableSwipeBack(pathname)) {
      void SwipeBack.disable();
    } else {
      void SwipeBack.enable();
    }
    // Re-enable saat unmount (route change), supaya next route start dari
    // baseline enabled.
    return () => {
      void SwipeBack.enable();
    };
  }, [pathname]);
}
