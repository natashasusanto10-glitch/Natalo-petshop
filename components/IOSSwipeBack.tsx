"use client";

/**
 * IOSSwipeBack — JS-based swipe-back gesture untuk iOS WebView (Capacitor
 * TestFlight build) dan iOS PWA standalone.
 *
 * Kenapa JS dan bukan native:
 * - Native `allowsBackForwardNavigationGestures` di WKWebView kadang tidak
 *   reliable di TestFlight build (depend iOS version + WebView content).
 * - JS handler memberikan UX konsisten cross-platform.
 *
 * Scope aktivasi:
 * - iOS Capacitor native (TestFlight .ipa): YES — JS handles, native plugin
 *   di-disable on mount supaya tidak double-fire.
 * - iOS PWA installed (Add to Home Screen, navigator.standalone): YES.
 * - iOS Safari browser biasa: NO — biarkan native Safari swipe-back ambil
 *   alih (browser sudah punya gesture built-in).
 * - Android: NO — handled by SwipeBackProvider.
 *
 * Edge cases yg di-handle:
 * - Hanya gesture dari edge kiri (<= EDGE_SIZE px)
 * - Min swipe distance + vertical limit
 * - Skip kalau target = input/textarea/select/button/a/role=button
 * - Skip kalau target di dalam [data-no-swipe-back="true"] atau
 *   [data-modal="true"], [data-drawer="true"],
 *   [data-horizontal-scroll="true"]
 * - Skip kalau body class indicator modal/drawer/sheet aktif
 * - Hindari double-fire via hasTriggered ref
 */

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

type Props = {
  /** Force disable (mis. saat checkout sedang submit payment). */
  disabled?: boolean;
};

const EDGE_SIZE = 30;
const MIN_SWIPE_DISTANCE = 70;
const MAX_VERTICAL_MOVEMENT = 45;

function isIOSDevice(): boolean {
  if (typeof window === "undefined") return false;
  const ua = window.navigator.userAgent;
  const platform = window.navigator.platform;
  return (
    /iPad|iPhone|iPod/.test(ua) ||
    (platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
  );
}

function isIOSCapacitorNative(): boolean {
  if (typeof window === "undefined") return false;
  // @ts-expect-error — Capacitor global di-inject runtime di iOS WebView
  const cap = window.Capacitor;
  if (!cap) return false;
  try {
    return (
      typeof cap.isNativePlatform === "function" &&
      cap.isNativePlatform() &&
      typeof cap.getPlatform === "function" &&
      cap.getPlatform() === "ios"
    );
  } catch {
    return false;
  }
}

function isIOSStandalonePWA(): boolean {
  if (typeof window === "undefined") return false;
  // iOS PWA: navigator.standalone === true (non-standard, iOS only)
  const nav = window.navigator as Navigator & { standalone?: boolean };
  return nav.standalone === true;
}

function shouldActivate(): boolean {
  if (!isIOSDevice()) return false;
  // iOS Capacitor: aktif (TestFlight). iOS PWA standalone: aktif. iOS
  // Safari browser biasa: tidak aktif (browser native swipe sudah ada).
  return isIOSCapacitorNative() || isIOSStandalonePWA();
}

function isInteractiveTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return Boolean(
    target.closest(
      [
        "input",
        "textarea",
        "select",
        "button",
        "a",
        "[role='button']",
        '[role="button"]',
        "[data-no-swipe-back='true']",
        '[data-no-swipe-back="true"]',
        "[data-modal='true']",
        '[data-modal="true"]',
        "[data-drawer='true']",
        '[data-drawer="true"]',
        "[data-horizontal-scroll='true']",
        '[data-horizontal-scroll="true"]',
      ].join(","),
    ),
  );
}

function isBodyOverlayOpen(): boolean {
  if (typeof document === "undefined") return false;
  const cls = document.body.classList;
  return (
    cls.contains("modal-open") ||
    cls.contains("bottom-sheet-open") ||
    cls.contains("voucher-modal-open") ||
    cls.contains("nat-modal-open") ||
    cls.contains("top-drawer-open") ||
    cls.contains("product-image-viewer-open")
  );
}

export default function IOSSwipeBack({ disabled = false }: Props) {
  const router = useRouter();
  const startX = useRef(0);
  const startY = useRef(0);
  const tracking = useRef(false);
  const hasTriggered = useRef(false);

  useEffect(() => {
    if (!shouldActivate()) return;

    // Disable native plugin (SwipeBackPlugin via @capacitor) supaya tidak
    // double-fire dgn JS handler ini. Kalau plugin tidak ada (web /
    // non-Capacitor), import gagal silent.
    let pluginDisabled = false;
    (async () => {
      try {
        const mod = await import("@/lib/native/swipe-back");
        await mod.SwipeBack.disable();
        pluginDisabled = true;
      } catch {
        // ignore
      }
    })();

    function onTouchStart(event: TouchEvent) {
      if (disabled) return;
      if (event.touches.length !== 1) return;
      if (isInteractiveTarget(event.target)) return;
      if (isBodyOverlayOpen()) return;

      const touch = event.touches[0];
      if (touch.clientX > EDGE_SIZE) return;

      startX.current = touch.clientX;
      startY.current = touch.clientY;
      tracking.current = true;
      hasTriggered.current = false;
    }

    function onTouchMove(event: TouchEvent) {
      if (disabled) return;
      if (!tracking.current) return;
      if (hasTriggered.current) return;
      if (event.touches.length !== 1) return;

      const touch = event.touches[0];
      const diffX = touch.clientX - startX.current;
      const diffY = Math.abs(touch.clientY - startY.current);

      if (diffX > MIN_SWIPE_DISTANCE && diffY < MAX_VERTICAL_MOVEMENT) {
        hasTriggered.current = true;
        tracking.current = false;
        if (window.history.length > 1) {
          router.back();
        } else {
          router.push("/");
        }
      }
    }

    function reset() {
      tracking.current = false;
      hasTriggered.current = false;
    }

    window.addEventListener("touchstart", onTouchStart, { passive: true });
    window.addEventListener("touchmove", onTouchMove, { passive: true });
    window.addEventListener("touchend", reset, { passive: true });
    window.addEventListener("touchcancel", reset, { passive: true });

    return () => {
      window.removeEventListener("touchstart", onTouchStart);
      window.removeEventListener("touchmove", onTouchMove);
      window.removeEventListener("touchend", reset);
      window.removeEventListener("touchcancel", reset);
      // Re-enable native plugin saat unmount supaya tidak leak state
      // (mis. saat HMR di dev).
      if (pluginDisabled) {
        (async () => {
          try {
            const mod = await import("@/lib/native/swipe-back");
            await mod.SwipeBack.enable();
          } catch {
            // ignore
          }
        })();
      }
    };
  }, [disabled, router]);

  return null;
}
