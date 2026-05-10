"use client";

import { useEffect } from "react";

type IconColor = "dark" | "light";

type Props = {
  /**
   * Warna ICON status bar (time, battery, signal indicator).
   * - "dark" = ikon hitam, untuk halaman dengan background TERANG (most pages, default)
   * - "light" = ikon putih, untuk halaman dengan background GELAP (mis. hero foto, brand blue full bg)
   */
  iconColor?: IconColor;
  /**
   * Warna meta theme-color: untuk PWA standalone status bar bg & Safari URL bar.
   * Default: "#ffffff" (selaras dengan header putih kebanyakan halaman).
   */
  themeColor?: string;
};

/**
 * Per-page status bar style controller.
 *
 * Mount sekali di layout root sebagai default app-wide. Per halaman bisa override
 * dengan mount lagi di page itu — instance yang ter-mount terakhir menang
 * sampai di-unmount (cleanup restore previous state).
 *
 * Apa yang di-update:
 * - iOS native (TestFlight / .ipa): UIStatusBar style via @capacitor/status-bar.
 *   Style.Dark = darkContent (icon hitam, untuk light bg).
 *   Style.Light = lightContent (icon putih, untuk dark bg).
 * - PWA standalone & browser: meta theme-color tag — update semua existing
 *   meta theme-color (termasuk variant light/dark media query).
 *
 * Web non-Capacitor: plugin import gagal silently, theme-color tetap update.
 */
export function PageStatusBar({ iconColor = "dark", themeColor = "#ffffff" }: Props) {
  useEffect(() => {
    // 1. Update theme-color meta (semua existing tag)
    const metas = document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]');
    const previousContents: string[] = Array.from(metas).map((m) => m.content);
    metas.forEach((m) => {
      m.content = themeColor;
    });
    // Tambah baru kalau belum ada (e.g., per-page mount tanpa metadata layout)
    let injectedMeta: HTMLMetaElement | null = null;
    if (metas.length === 0) {
      injectedMeta = document.createElement("meta");
      injectedMeta.name = "theme-color";
      injectedMeta.content = themeColor;
      document.head.appendChild(injectedMeta);
    }

    // 2. Update iOS native status bar via Capacitor plugin
    let cancelled = false;
    (async () => {
      try {
        const { StatusBar, Style } = await import("@capacitor/status-bar");
        if (cancelled) return;
        await StatusBar.setStyle({
          style: iconColor === "dark" ? Style.Dark : Style.Light,
        });
      } catch {
        // Web / browser tanpa Capacitor — silent no-op
      }
    })();

    return () => {
      cancelled = true;
      // Restore theme-color meta state sebelumnya (penting saat navigate antar page)
      const currentMetas = document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]');
      currentMetas.forEach((m, i) => {
        if (previousContents[i] !== undefined) {
          m.content = previousContents[i];
        }
      });
      if (injectedMeta && injectedMeta.parentNode) {
        injectedMeta.parentNode.removeChild(injectedMeta);
      }
    };
  }, [iconColor, themeColor]);

  return null;
}
