"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

const ALLOWED_HOSTS = new Set([
  "natalo-petshop.vercel.app",
  "www.natalopetshop.com",
  "natalopetshop.com",
]);

const BLOCKED_PREFIXES = ["/admin"];

function getInternalPath(rawUrl: string) {
  try {
    const url = new URL(rawUrl);

    if (!ALLOWED_HOSTS.has(url.hostname)) return null;
    if (BLOCKED_PREFIXES.some((prefix) => url.pathname === prefix || url.pathname.startsWith(`${prefix}/`))) {
      return null;
    }

    return `${url.pathname || "/"}${url.search}${url.hash}`;
  } catch (err) {
    console.warn("DeepLinkHandler: invalid URL", rawUrl, err);
    return null;
  }
}

export function DeepLinkHandler() {
  const router = useRouter();

  useEffect(() => {
    let cancelled = false;
    let unsubscribe: (() => void) | null = null;

    function openDeepLink(rawUrl: string) {
      const path = getInternalPath(rawUrl);
      if (!path || cancelled) return;

      const currentPath = `${window.location.pathname}${window.location.search}${window.location.hash}`;
      if (path !== currentPath) {
        router.push(path);
      }
    }

    (async () => {
      try {
        const { App } = await import("@capacitor/app");

        const launchUrl = await App.getLaunchUrl();
        if (launchUrl?.url) {
          openDeepLink(launchUrl.url);
        }

        const handle = await App.addListener("appUrlOpen", (event) => {
          openDeepLink(event.url);
        });

        if (cancelled) {
          await handle.remove();
          return;
        }

        unsubscribe = () => {
          void handle.remove();
        };
      } catch {
        // Non-Capacitor web/PWA builds rely on the browser URL directly.
      }
    })();

    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, [router]);

  return null;
}
