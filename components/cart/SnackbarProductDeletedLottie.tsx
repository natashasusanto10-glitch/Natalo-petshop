"use client";

import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const SRC = "/assets/lottie/snackbar_product_deleted_cart_paw.json";

/**
 * Micro Lottie (1.2s, non-looping) for the "produk telah dihapus" snackbar
 * in the cart. Sized 28px by default; the container caller can override
 * via className. Falls back to an inline SVG cart-with-paw icon if the
 * Lottie asset can't be loaded.
 *
 * `triggerKey` — bump this to replay the animation when the snackbar
 * re-mounts (e.g. user deletes another item while one is still showing).
 */
export function SnackbarProductDeletedLottie({
  className = "",
  triggerKey,
}: {
  className?: string;
  triggerKey?: number | string;
}) {
  const containerRef = useRef<HTMLSpanElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function loadAnimation() {
      try {
        const [lottie, response] = await Promise.all([
          import("lottie-web"),
          fetch(SRC, { cache: "force-cache" }),
        ]);

        if (!response.ok) throw new Error("Snackbar Lottie asset not found");
        const animationData = await response.json();
        if (cancelled || !containerRef.current) return;

        animationRef.current?.destroy();
        const animation = lottie.default.loadAnimation({
          container: containerRef.current,
          renderer: "svg",
          loop: false,
          autoplay: true,
          animationData,
          rendererSettings: {
            progressiveLoad: true,
            preserveAspectRatio: "xMidYMid meet",
          },
        });

        animationRef.current = animation;
        animation.addEventListener("data_failed", () => {
          if (!cancelled) setFailed(true);
        });
      } catch {
        if (!cancelled) setFailed(true);
      }
    }

    void loadAnimation();

    return () => {
      cancelled = true;
      animationRef.current?.destroy();
      animationRef.current = null;
    };
    // triggerKey is intentionally included so the effect re-runs and
    // restarts the animation when a new delete event happens.
  }, [triggerKey]);

  return (
    <span
      className={`relative inline-flex h-7 w-7 shrink-0 items-center justify-center ${className}`}
      aria-hidden="true"
    >
      <span
        ref={containerRef}
        className={`absolute inset-0 ${failed ? "hidden" : ""}`}
      />
      {failed && (
        <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5">
          {/* Cart body */}
          <path
            d="M5.4 7.4h13.2l-1.1 8.4a2 2 0 0 1-2 1.7H8.5a2 2 0 0 1-2-1.7L5.4 7.4Z"
            fill="#2563EB"
            opacity="0.92"
          />
          <path
            d="M7.5 7.4a4.5 4.5 0 0 1 9 0"
            stroke="#0B3A8A"
            strokeWidth="1.6"
            strokeLinecap="round"
          />
          {/* Wheels */}
          <circle cx="9" cy="20" r="1.3" fill="#0B3A8A" />
          <circle cx="15" cy="20" r="1.3" fill="#0B3A8A" />
          {/* Paw on cart */}
          <g fill="#FFFFFF" opacity="0.9">
            <ellipse cx="10.5" cy="11.5" rx="1" ry="1.2" />
            <ellipse cx="12" cy="10" rx="1" ry="1.2" />
            <ellipse cx="13.5" cy="11.5" rx="1" ry="1.2" />
            <ellipse cx="12" cy="13.6" rx="2" ry="1.5" />
          </g>
          {/* Sparkle */}
          <path
            d="M18 4v2M17 5h2"
            stroke="#60A5FA"
            strokeWidth="1.4"
            strokeLinecap="round"
          />
        </svg>
      )}
    </span>
  );
}
