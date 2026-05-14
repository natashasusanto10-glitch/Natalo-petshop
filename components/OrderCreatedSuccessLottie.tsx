"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const ORDER_CREATED_SUCCESS_LOTTIE_SRC =
  "/assets/lottie/order_created_success_natalo_blue.json";
const ORDER_CREATED_SUCCESS_FALLBACK_SRC =
  "/assets/images/order_created_success_fallback.png";

export function OrderCreatedSuccessLottie() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function loadAnimation() {
      try {
        const [lottie, response] = await Promise.all([
          import("lottie-web"),
          fetch(ORDER_CREATED_SUCCESS_LOTTIE_SRC, { cache: "force-cache" }),
        ]);

        if (!response.ok) throw new Error("Order success Lottie asset not found");
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
    <div
      className="relative mx-auto h-[220px] w-full max-w-[280px]"
      aria-hidden="true"
    >
      <div
        ref={containerRef}
        className={`h-full w-full ${failed ? "hidden" : ""}`}
      />
      {failed ? (
        <Image
          src={ORDER_CREATED_SUCCESS_FALLBACK_SRC}
          alt=""
          fill
          sizes="280px"
          className="object-contain"
          priority={false}
        />
      ) : null}
    </div>
  );
}
