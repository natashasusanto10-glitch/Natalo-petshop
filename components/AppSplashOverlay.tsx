"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const SEEN_KEY = "natalo:splash-shown";
const SPLASH_LOTTIE_SRC = "/assets/lottie/splash_natalo_petshop.json";
const SPLASH_MAX_MS = 1500;
const SPLASH_FADE_MS = 180;

export function AppSplashOverlay() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [visible, setVisible] = useState(true);
  const [leaving, setLeaving] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;

    try {
      if (sessionStorage.getItem(SEEN_KEY)) {
        setVisible(false);
        return;
      }
      sessionStorage.setItem(SEEN_KEY, "1");
    } catch {
      // Storage can be unavailable in some WebViews; the splash still self-dismisses.
    }

    const dismiss = () => {
      setLeaving(true);
      window.setTimeout(() => setVisible(false), SPLASH_FADE_MS);
    };

    const hardStop = window.setTimeout(dismiss, SPLASH_MAX_MS);

    async function loadSplash() {
      try {
        const [lottie, response] = await Promise.all([
          import("lottie-web"),
          fetch(SPLASH_LOTTIE_SRC, { cache: "force-cache" }),
        ]);

        if (!response.ok) throw new Error("Splash Lottie asset not found");
        const animationData = await response.json();
        if (!containerRef.current) return;

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
        animation.addEventListener("complete", dismiss);
        animation.addEventListener("data_failed", () => setFailed(true));
      } catch {
        setFailed(true);
      }
    }

    void loadSplash();

    return () => {
      window.clearTimeout(hardStop);
      animationRef.current?.destroy();
      animationRef.current = null;
    };
  }, []);

  if (!visible) return null;

  return (
    <div
      aria-hidden="true"
      className={`natalo-splash-overlay fixed inset-0 z-[9999] grid place-items-center bg-white transition-opacity duration-200 ${
        leaving ? "pointer-events-none opacity-0" : "opacity-100"
      }`}
    >
      <div className="relative h-full w-full max-w-[520px]">
        <div
          ref={containerRef}
          className={`absolute inset-0 h-full w-full ${failed ? "hidden" : ""}`}
        />
        {failed ? (
          <div className="absolute inset-0 grid place-items-center">
            <Image
              src="/logo.png"
              alt=""
              width={600}
              height={196}
              priority
              className="h-auto w-[220px]"
            />
          </div>
        ) : null}
      </div>
    </div>
  );
}
