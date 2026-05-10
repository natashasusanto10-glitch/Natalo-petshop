"use client";

import { useEffect } from "react";

/**
 * Keyboard manager untuk iOS native — tambahan logic di atas Capacitor
 * default `resize: "body"` config:
 *
 * 1. Saat keyboard muncul, scroll focused input ke view (scrollIntoView)
 *    dengan padding atas supaya gak nempel banget ke top of viewport.
 *
 * 2. Kalau body sudah di-resize (via Capacitor), Layout shift biasanya
 *    sudah handled. Tapi nested scroll containers (mis. modal/drawer
 *    yang scroll sendiri) butuh manual scrollIntoView.
 *
 * Mount sekali di layout. Listener berlaku app-wide.
 */
export function KeyboardManager() {
  useEffect(() => {
    if (typeof window === "undefined") return;

    let removeListeners: (() => void) | null = null;

    (async () => {
      try {
        const { Keyboard } = await import("@capacitor/keyboard");

        // Saat keyboard sedang muncul, ensure focused element scroll ke view
        const showHandle = await Keyboard.addListener("keyboardWillShow", (info) => {
          const active = document.activeElement as HTMLElement | null;
          if (!active) return;
          if (
            active.tagName === "INPUT" ||
            active.tagName === "TEXTAREA" ||
            active.tagName === "SELECT" ||
            active.isContentEditable
          ) {
            // Delay sedikit biar transisi keyboard up sudah hampir selesai
            setTimeout(() => {
              const rect = active.getBoundingClientRect();
              const visibleHeight = window.innerHeight - info.keyboardHeight;
              // Kalau input ke-cover keyboard, scroll
              if (rect.bottom > visibleHeight - 16) {
                active.scrollIntoView({ behavior: "smooth", block: "center" });
              }
            }, 150);
          }
        });

        const hideHandle = await Keyboard.addListener("keyboardDidHide", () => {
          // Optional: bisa scroll restore atau apa pun di sini
        });

        removeListeners = () => {
          showHandle.remove();
          hideHandle.remove();
        };
      } catch {
        // Web / non-Capacitor — silent no-op (browser handles keyboard scroll natively)
      }
    })();

    return () => {
      removeListeners?.();
    };
  }, []);

  return null;
}
