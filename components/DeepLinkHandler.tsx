"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/**
 * Deep link handler untuk Universal Links iOS.
 *
 * Flow lengkap:
 * 1. User klik URL "https://natalo-petshop.vercel.app/products/royal-canin"
 *    di WhatsApp / email / browser lain
 * 2. iOS check AASA file → ya, Natalo claim domain ini
 * 3. iOS open app native + pass URL via @capacitor/app appUrlOpen event
 * 4. Component ini listen event, parse path, navigate via Next.js router
 *
 * Tanpa handler ini, app open ke last route (atau home), URL diabaikan.
 *
 * Mount sekali di layout. Listener active app-wide.
 */
export function DeepLinkHandler() {
  const router = useRouter();

  useEffect(() => {
    let unsubscribe: (() => void) | null = null;

    (async () => {
      try {
        const { App } = await import("@capacitor/app");

        // Listen app being opened via deep link (Universal Link or custom scheme)
        const handle = await App.addListener("appUrlOpen", (event) => {
          // event.url contoh: "https://natalo-petshop.vercel.app/products/royal-canin"
          // Parse jadi pathname relatif lalu router push
          try {
            const url = new URL(event.url);
            // Skip kalau URL bukan domain Natalo (safety check)
            if (!url.hostname.includes("natalo-petshop") && url.hostname !== "natalo-petshop.vercel.app") {
              return;
            }
            const path = url.pathname + url.search + url.hash;
            // Navigate via Next.js router — keep client-side routing
            router.push(path || "/");
          } catch (err) {
            console.warn("DeepLinkHandler: invalid URL", event.url, err);
          }
        });

        unsubscribe = () => handle.remove();
      } catch {
        // Web non-Capacitor — universal links automatically work via browser history
      }
    })();

    return () => {
      unsubscribe?.();
    };
  }, [router]);

  return null;
}
