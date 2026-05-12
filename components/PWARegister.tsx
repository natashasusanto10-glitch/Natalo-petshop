"use client";

import { useEffect } from "react";

/**
 * Cek apakah app jalan di dalam Capacitor native WebView (TestFlight .ipa /
 * Android APK). Capacitor inject `window.Capacitor` global runtime.
 */
function isCapacitorNative(): boolean {
  if (typeof window === "undefined") return false;
  // @ts-expect-error — runtime global, no type
  const cap = window.Capacitor;
  if (!cap) return false;
  try {
    return typeof cap.isNativePlatform === "function" && cap.isNativePlatform();
  } catch {
    return false;
  }
}

export function PWARegister() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    // ── Capacitor native (TestFlight / APK): JANGAN register SW ──
    // WKWebView/Android WebView pakai HTTP cache native + Capacitor offline
    // handling. SW di WebView nyebabin stale chunk bug (chunk JS lama serve
    // setelah deploy → React hydration mismatch → "Terjadi Kesalahan").
    // Unregister SW lama + clear cache supaya user yg sudah install build
    // sebelumnya auto-recover di launch berikutnya.
    if (isCapacitorNative()) {
      navigator.serviceWorker
        .getRegistrations()
        .then(async (registrations) => {
          if (registrations.length === 0) return;
          await Promise.all(registrations.map((r) => r.unregister()));
          const keys = await caches.keys();
          await Promise.all(
            keys.filter((k) => k.startsWith("natalo-")).map((k) => caches.delete(k)),
          );
          // Reload sekali supaya page baru di-fetch dari network tanpa SW.
          if (!sessionStorage.getItem("pwa-cap-sw-cleaned")) {
            sessionStorage.setItem("pwa-cap-sw-cleaned", "1");
            window.location.reload();
          }
        })
        .catch(() => {});
      return;
    }

    if (process.env.NODE_ENV !== "production") {
      const reloadKey = "pwa-dev-sw-cleaned";
      navigator.serviceWorker
        .getRegistrations()
        .then(async (registrations) => {
          const keys = await caches.keys();
          await Promise.all(registrations.map((registration) => registration.unregister()));
          await Promise.all(keys.filter((key) => key.startsWith("natalo-")).map((key) => caches.delete(key)));

          if ((registrations.length > 0 || keys.some((key) => key.startsWith("natalo-"))) && !sessionStorage.getItem(reloadKey)) {
            sessionStorage.setItem(reloadKey, "1");
            window.location.reload();
          }
        })
        .catch(() => {});
      return;
    }

    navigator.serviceWorker
      .register("/sw.js")
      .then((registration) => {
        registration.update().catch(() => {});

        if (navigator.serviceWorker.controller) return;

        navigator.serviceWorker.ready
          .then(() => {
            if (sessionStorage.getItem("pwa-sw-ready-reloaded")) return;

            sessionStorage.setItem("pwa-sw-ready-reloaded", "1");
            window.location.reload();
          })
          .catch(() => {});
      })
      .catch(() => {});
  }, []);

  return null;
}
