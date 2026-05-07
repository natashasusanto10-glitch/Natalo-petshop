"use client";

import { useEffect } from "react";

export function PWARegister() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

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
