"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/**
 * Intercept klik <a> internal + wrap navigasi dengan
 * `document.startViewTransition()` supaya cross-fade halus muncul antar
 * halaman (Chrome 111+ / Capacitor WebView modern).
 *
 * Pakai capture phase supaya kita dapat event SEBELUM Next.js Link handler.
 * Browser non-support → langsung router.push (no-op fallback).
 *
 * Catatan:
 * - Hanya intercept link internal (start dgn /) tanpa target=_blank dan
 *   tanpa modifier key (cmd/ctrl/shift).
 * - rel="external" / download attribute → biarkan default browser handle.
 * - <ViewTransition> dari React belum di stable React 19.2 (still canary).
 *   Pendekatan event-listener ini lebih portable dan bekerja tanpa
 *   modifikasi setiap Link.
 */
export function ViewTransitionsProvider() {
  const router = useRouter();

  useEffect(() => {
    if (typeof document.startViewTransition !== "function") return;
    if (typeof window === "undefined") return;

    function shouldIntercept(target: HTMLAnchorElement, event: MouseEvent): string | null {
      if (event.defaultPrevented) return null;
      if (event.button !== 0) return null; // hanya left-click
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return null;
      if (target.target && target.target !== "_self") return null;
      if (target.hasAttribute("download")) return null;
      if (target.getAttribute("rel")?.includes("external")) return null;
      const href = target.getAttribute("href");
      if (!href) return null;
      // Hanya internal navigation — link yg start dgn / dan bukan //
      if (!href.startsWith("/") || href.startsWith("//")) return null;
      // Skip anchor jump dalam halaman
      if (href.startsWith("/#")) return null;
      return href;
    }

    function handleClick(event: MouseEvent) {
      const anchor = (event.target as HTMLElement | null)?.closest?.("a");
      if (!anchor || !(anchor instanceof HTMLAnchorElement)) return;
      const href = shouldIntercept(anchor, event);
      if (!href) return;

      event.preventDefault();
      // startViewTransition snapshot DOM saat ini, jalankan callback,
      // lalu snapshot DOM baru → cross-fade antar dua snapshot.
      document.startViewTransition(() => {
        router.push(href);
      });
    }

    document.addEventListener("click", handleClick, true);
    return () => document.removeEventListener("click", handleClick, true);
  }, [router]);

  return null;
}
