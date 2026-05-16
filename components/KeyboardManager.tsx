"use client";

import { useEffect } from "react";

/**
 * Keyboard manager untuk shell native. Feed/Reels comment sheet mengatur
 * keyboard inset sendiri, tetapi WebView scroll harus tetap aktif untuk
 * halaman normal seperti Produk, Akun, Cart, dan Checkout.
 */
export function KeyboardManager() {
  useEffect(() => {
    if (typeof window === "undefined") return;

    (async () => {
      try {
        const [{ Capacitor }, { Keyboard, KeyboardResize }] = await Promise.all([
          import("@capacitor/core"),
          import("@capacitor/keyboard"),
        ]);

        if (Capacitor.getPlatform() !== "ios") return;

        await Keyboard.setResizeMode({ mode: KeyboardResize.None });
        await Keyboard.setScroll({ isDisabled: false });

        if (process.env.NODE_ENV !== "production") {
          // Membantu validasi di TestFlight/devtools tanpa mengubah UX.
          console.log("Keyboard resize mode:", await Keyboard.getResizeMode());
        }
      } catch {
        // Web / non-Capacitor — silent no-op.
      }
    })();
  }, []);

  return null;
}
