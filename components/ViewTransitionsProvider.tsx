"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/**
 * Intercept klik <a> internal + wrap navigasi dengan
 * `document.startViewTransition()` supaya transisi iOS-style muncul antar
 * halaman (Chrome 111+ / Capacitor WebView modern).
 *
 * Direksional:
 * - Klik link (forward) → set <html data-nav-direction="push"> → CSS
 *   apply slide-in-from-right (lihat globals.css ::view-transition-*).
 * - popstate (router.back / swipe-back / browser back) → set
 *   data-nav-direction="pop" → slide-out-to-right.
 *
 * Capture phase supaya kita dapat event SEBELUM Next.js Link handler.
 * Browser non-support → langsung router.push (no-op fallback).
 *
 * Catatan:
 * - Hanya intercept link internal (start dgn /) tanpa target=_blank dan
 *   tanpa modifier key (cmd/ctrl/shift).
 * - rel="external" / download attribute → biarkan default browser handle.
 * - Atribut data-nav-direction tetap di DOM sampai navigasi berikutnya
 *   meng-overwrite. Aman karena selector `::view-transition-*` hanya
 *   aktif saat transisi sedang berjalan.
 */
export function ViewTransitionsProvider() {
  const router = useRouter();

  useEffect(() => {
    if (typeof document === "undefined") return;
    if (typeof document.startViewTransition !== "function") return;

    function setDirection(direction: "push" | "pop") {
      document.documentElement.dataset.navDirection = direction;
    }

    function shouldIntercept(target: HTMLAnchorElement, event: MouseEvent): string | null {
      if (event.defaultPrevented) return null;
      if (event.button !== 0) return null; // hanya left-click
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return null;
      if (target.target && target.target !== "_self") return null;
      if (target.hasAttribute("download")) return null;
      if (target.getAttribute("rel")?.includes("external")) return null;
      const href = target.getAttribute("href");
      if (!href) return null;
      if (!href.startsWith("/") || href.startsWith("//")) return null;
      if (href.startsWith("/#")) return null;
      return href;
    }

    function handleClick(event: MouseEvent) {
      const anchor = (event.target as HTMLElement | null)?.closest?.("a");
      if (!anchor || !(anchor instanceof HTMLAnchorElement)) return;
      const href = shouldIntercept(anchor, event);
      if (!href) return;

      event.preventDefault();
      setDirection("push");
      document.startViewTransition(() => {
        router.push(href);
      });
    }

    function handlePopState() {
      // router.back / swipe back / browser back / hardware back semua
      // trigger popstate. Next.js 16 (experimental.viewTransition: true)
      // auto-wrap route change dalam startViewTransition — kita hanya
      // perlu set direction sebelum animasi mulai.
      setDirection("pop");
    }

    document.addEventListener("click", handleClick, true);
    window.addEventListener("popstate", handlePopState);
    return () => {
      document.removeEventListener("click", handleClick, true);
      window.removeEventListener("popstate", handlePopState);
    };
  }, [router]);

  return null;
}
