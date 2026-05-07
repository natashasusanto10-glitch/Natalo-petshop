"use client";

import { useEffect } from "react";

export function PWARegister() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

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
