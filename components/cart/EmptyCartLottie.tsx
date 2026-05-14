"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const CART_LOTTIE_SRC = "/assets/lottie/empty_cart_natalo_blue.json";
const CART_FALLBACK_SRC = "/assets/images/empty_cart_pets_fullcolor.png";

export function EmptyCartLottie() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");

  useEffect(() => {
    let cancelled = false;

    async function loadAnimation() {
      try {
        const [lottie, response] = await Promise.all([
          import("lottie-web"),
          fetch(CART_LOTTIE_SRC, { cache: "force-cache" }),
        ]);

        if (!response.ok) throw new Error("Empty cart Lottie asset not found");
        const animationData = await response.json();
        if (cancelled || !containerRef.current) return;

        const animation = lottie.default.loadAnimation({
          container: containerRef.current,
          renderer: "svg",
          loop: true,
          autoplay: true,
          animationData,
          rendererSettings: {
            progressiveLoad: true,
            preserveAspectRatio: "xMidYMid meet",
          },
        });

        animationRef.current = animation;
        animation.addEventListener("DOMLoaded", () => {
          if (!cancelled) setStatus("ready");
        });
        animation.addEventListener("data_failed", () => {
          if (!cancelled) setStatus("error");
        });
      } catch {
        if (!cancelled) setStatus("error");
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
    <div className="relative mx-auto mb-5 aspect-[1.27/1] w-full max-w-[280px] overflow-visible">
      <div
        ref={containerRef}
        className={`absolute inset-0 h-full w-full ${status === "error" ? "hidden" : ""}`}
        aria-hidden="true"
      />
      {status !== "ready" ? (
        <Image
          src={CART_FALLBACK_SRC}
          alt=""
          width={1016}
          height={797}
          className="absolute inset-0 h-full w-full object-contain"
          aria-hidden="true"
        />
      ) : null}
    </div>
  );
}
