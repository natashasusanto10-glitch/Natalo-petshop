"use client";

import { useEffect } from "react";

/**
 * SW Cleanup component (dulu: PWARegister).
 *
 * Natalo Petshop sudah lepas PWA — mobile experience pindah ke Flutter native
 * (via Codemagic → TestFlight / App Store). Service Worker di web cuma jadi
 * sumber stale-cache bug (chunk JS lama dilayani SW setelah deploy → blank
 * screen).
 *
 * Tugas komponen ini sekarang cuma satu: kalau browser user masih punya SW
 * lama (dari sebelum cleanup), unregister + clear cache, lalu reload.
 *
 * Logic ini aman jalan setiap page mount — kalau tidak ada SW, no-op. Setelah
 * user existing sudah bersih (~30 hari coverage), file ini bisa dihapus
 * total bareng `/sw.js` self-destruct.
 */
export function PWARegister() {
  useEffect(() => {
    if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) {
      return;
    }

    // Guard supaya tidak infinite reload loop: cuma satu kali per session.
    const RELOAD_KEY = "natalo-sw-cleaned";
    const alreadyCleaned = sessionStorage.getItem(RELOAD_KEY);

    navigator.serviceWorker
      .getRegistrations()
      .then(async (registrations) => {
        let didWork = false;

        if (registrations.length > 0) {
          await Promise.all(registrations.map((r) => r.unregister()));
          didWork = true;
        }

        try {
          const cacheKeys = await caches.keys();
          const ours = cacheKeys.filter((k) => k.startsWith("natalo-"));
          if (ours.length > 0) {
            await Promise.all(ours.map((k) => caches.delete(k)));
            didWork = true;
          }
        } catch {
          /* caches API tidak tersedia di beberapa privacy mode — skip. */
        }

        if (didWork && !alreadyCleaned) {
          sessionStorage.setItem(RELOAD_KEY, "1");
          window.location.reload();
        }
      })
      .catch(() => {
        /* Best-effort. */
      });
  }, []);

  return null;
}
