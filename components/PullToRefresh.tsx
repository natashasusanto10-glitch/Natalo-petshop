"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Haptics, ImpactStyle, NotificationType } from "@capacitor/haptics";

const TRIGGER_DISTANCE = 80; // px pull sebelum trigger refresh
const MAX_PULL = 120; // hard cap (resistance setelah trigger)
const RESISTANCE_FACTOR = 0.45; // setelah threshold, pull jadi lebih berat

/** Native iOS UIImpactFeedbackGenerator (atau Android HapticFeedback). No-op di
 * browser web non-Capacitor — plugin handle platform detection internally. */
async function hapticImpact(style: ImpactStyle = ImpactStyle.Medium) {
  try {
    await Haptics.impact({ style });
  } catch {
    // Web / unsupported — silent fail
  }
}

async function hapticNotification(type: NotificationType = NotificationType.Success) {
  try {
    await Haptics.notification({ type });
  } catch {}
}

/**
 * Pull-to-refresh wrapper untuk seluruh app.
 *
 * Pasang di root layout (di dalam StoreOnly). Listen global touch events,
 * detect pull dari top of page, show indicator. Saat user release past threshold,
 * trigger router.refresh() (refetch server components) + dispatch event
 * "app-refresh" supaya client components yang punya state lokal bisa listen
 * dan refetch data mereka sendiri.
 *
 * Behavior:
 * - Active hanya saat scrollY === 0 (di top page)
 * - Disabled saat refresh in-flight
 * - Cancel kalau user scroll up saat sudah pulling
 * - Resistance setelah TRIGGER_DISTANCE (lebih berat ditarik, max MAX_PULL)
 *
 * Untuk halaman tertentu yang gak butuh pull (mis. checkout form),
 * pasang prop `disabled`.
 */
export function PullToRefresh({ disabled = false }: { disabled?: boolean }) {
  const router = useRouter();
  const [pullDistance, setPullDistance] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const startYRef = useRef(0);
  const isPullingRef = useRef(false);
  const refreshingRef = useRef(false);
  // Track apakah pull sudah pernah past threshold di gesture saat ini, biar
  // haptic cuma fire SEKALI saat transition (gak spam tiap touchmove).
  const wasPastThresholdRef = useRef(false);

  // Sync state ke ref biar event handler dapat nilai terbaru tanpa rebind
  refreshingRef.current = refreshing;

  useEffect(() => {
    if (disabled) return;

    function isAtTop(): boolean {
      const scrollTop =
        window.scrollY ||
        document.documentElement.scrollTop ||
        document.body.scrollTop ||
        0;
      return scrollTop <= 0;
    }

    function handleTouchStart(e: TouchEvent) {
      if (refreshingRef.current) return;
      if (!isAtTop()) return;
      // Skip kalau gesture origin di element scrollable (mis. carousel)
      const target = e.target as HTMLElement;
      if (target.closest?.("[data-no-pull]")) return;
      startYRef.current = e.touches[0].clientY;
      isPullingRef.current = true;
      wasPastThresholdRef.current = false; // Reset state per-gesture
    }

    function handleTouchMove(e: TouchEvent) {
      if (!isPullingRef.current || refreshingRef.current) return;

      const delta = e.touches[0].clientY - startYRef.current;
      if (delta <= 0) {
        // User scroll up — cancel pull state
        isPullingRef.current = false;
        setPullDistance(0);
        return;
      }

      // Apply resistance setelah threshold
      const adjusted =
        delta < TRIGGER_DISTANCE
          ? delta
          : TRIGGER_DISTANCE + (delta - TRIGGER_DISTANCE) * RESISTANCE_FACTOR;
      const clamped = Math.min(adjusted, MAX_PULL);
      setPullDistance(clamped);

      // Haptic feedback saat pull pertama kali crossing threshold ke atas.
      // Match iOS native pull-to-refresh — getaran "click" memberitahu user
      // mereka boleh release sekarang.
      const isPastNow = clamped >= TRIGGER_DISTANCE;
      if (isPastNow && !wasPastThresholdRef.current) {
        hapticImpact(ImpactStyle.Medium);
      }
      wasPastThresholdRef.current = isPastNow;

      // Prevent native overscroll bounce conflict — hanya saat actively pulling
      if (clamped > 5 && e.cancelable) {
        e.preventDefault();
      }
    }

    async function handleTouchEnd() {
      if (!isPullingRef.current) return;
      isPullingRef.current = false;

      if (pullDistance >= TRIGGER_DISTANCE) {
        setRefreshing(true);
        try {
          // Refetch server components Next.js
          router.refresh();
          // Dispatch event-event existing untuk trigger refetch di client components
          // yang punya state lokal (cart, wishlist, auth, member info di Header).
          window.dispatchEvent(new CustomEvent("app-refresh"));
          window.dispatchEvent(new CustomEvent("auth-updated"));
          window.dispatchEvent(new CustomEvent("cart-updated"));
          window.dispatchEvent(new CustomEvent("wishlist-updated"));
          // Hold spinner ~800ms biar user lihat feedback
          await new Promise<void>((resolve) => setTimeout(resolve, 800));
          // Haptic success — UINotificationFeedbackGenerator success pattern,
          // memberi tahu user bahwa refresh sudah selesai
          hapticNotification(NotificationType.Success);
        } finally {
          setRefreshing(false);
          setPullDistance(0);
        }
      } else {
        setPullDistance(0);
      }
      wasPastThresholdRef.current = false;
    }

    document.addEventListener("touchstart", handleTouchStart, { passive: true });
    document.addEventListener("touchmove", handleTouchMove, { passive: false });
    document.addEventListener("touchend", handleTouchEnd, { passive: true });
    document.addEventListener("touchcancel", handleTouchEnd, { passive: true });

    return () => {
      document.removeEventListener("touchstart", handleTouchStart);
      document.removeEventListener("touchmove", handleTouchMove);
      document.removeEventListener("touchend", handleTouchEnd);
      document.removeEventListener("touchcancel", handleTouchEnd);
    };
  }, [pullDistance, disabled, router]);

  // Visible distance untuk render indicator (saat refreshing, force ke threshold)
  const visibleDistance = refreshing ? TRIGGER_DISTANCE : pullDistance;
  const indicatorOpacity = Math.min(visibleDistance / TRIGGER_DISTANCE, 1);
  const isPastThreshold = pullDistance >= TRIGGER_DISTANCE;
  const arrowRotation = isPastThreshold ? 180 : 0;

  if (visibleDistance <= 0) return null;

  const isAnimating = pullDistance === 0 || refreshing;

  return (
    <div
      aria-hidden="true"
      className="fixed inset-x-0 top-0 z-[60] flex justify-center pointer-events-none"
      style={{
        height: visibleDistance,
        opacity: indicatorOpacity,
        transition: isAnimating ? "height 240ms ease-out, opacity 240ms ease-out" : "none",
        paddingTop: "max(0.75rem, env(safe-area-inset-top))",
      }}
    >
      <div className="flex h-10 w-10 items-center justify-center rounded-full bg-white shadow-md">
        {refreshing ? (
          <svg
            className="h-5 w-5 animate-spin text-natalo-600"
            viewBox="0 0 24 24"
            fill="none"
          >
            <circle
              cx="12"
              cy="12"
              r="9"
              stroke="currentColor"
              strokeWidth="2.5"
              strokeOpacity="0.25"
            />
            <path
              d="M12 3a9 9 0 0 1 9 9"
              stroke="currentColor"
              strokeWidth="2.5"
              strokeLinecap="round"
            />
          </svg>
        ) : (
          <svg
            className="h-5 w-5 text-natalo-600 transition-transform duration-200"
            style={{ transform: `rotate(${arrowRotation}deg)` }}
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M12 19V5M5 12l7-7 7 7" />
          </svg>
        )}
      </div>
    </div>
  );
}
