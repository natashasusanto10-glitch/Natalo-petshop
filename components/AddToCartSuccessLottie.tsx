"use client";

import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const ADD_TO_CART_SUCCESS_LOTTIE_SRC =
  "/assets/lottie/add_to_cart_success_natalo_blue.json";

export function AddToCartSuccessLottie() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function loadAnimation() {
      try {
        const [lottie, response] = await Promise.all([
          import("lottie-web"),
          fetch(ADD_TO_CART_SUCCESS_LOTTIE_SRC, { cache: "force-cache" }),
        ]);

        if (!response.ok) throw new Error("Add-to-cart Lottie asset not found");
        const animationData = await response.json();
        if (cancelled || !containerRef.current) return;

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

        // Asset is authored at 1.2s; play slightly faster to land within
        // the 0.6–1.0s micro-interaction window from the spec.
        animation.setSpeed(1.2);
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
  }, []);

  return (
    <span className="cart-success-toast__visual" aria-hidden="true">
      <span
        ref={containerRef}
        className={`cart-success-toast__lottie ${failed ? "hidden" : ""}`}
      />
      {failed ? (
        <span className="cart-success-toast__fallback">
          <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path
              d="M6.8 8.2h10.4l-.8 8.1a2 2 0 0 1-2 1.8H9.6a2 2 0 0 1-2-1.8L6.8 8.2Z"
              fill="currentColor"
              opacity="0.18"
            />
            <path
              d="M8 8.2a4 4 0 0 1 8 0M6.8 8.2h10.4l-.8 8.1a2 2 0 0 1-2 1.8H9.6a2 2 0 0 1-2-1.8L6.8 8.2Z"
              stroke="currentColor"
              strokeWidth="1.8"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            <path
              d="m10 13.2 1.5 1.5 3-3.2"
              stroke="#22C55E"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </span>
      ) : null}
    </span>
  );
}
