"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const SEEN_KEY = "natalo:splash-shown";
const SPLASH_LOTTIE_SRC = "/assets/lottie/splash_natalo_petshop.json";
const SPLASH_BASE_MS = 3000;
const SPLASH_IOS_MS = 2800;
const SPLASH_ANDROID_MS = 3000;
const SPLASH_FADE_MS = 220;

function splashDurationMs() {
  if (typeof navigator === "undefined") return SPLASH_ANDROID_MS;
  const ua = navigator.userAgent || "";
  return /iPad|iPhone|iPod/.test(ua) ? SPLASH_IOS_MS : SPLASH_ANDROID_MS;
}

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

    const targetDuration = splashDurationMs();
    const hardStop = window.setTimeout(dismiss, targetDuration + 350);

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
        animation.setSpeed(SPLASH_BASE_MS / targetDuration);
        animation.addEventListener("complete", dismiss);
        animation.addEventListener("data_failed", () => setFailed(true));
      } catch {
        setFailed(true);
        window.setTimeout(dismiss, 1200);
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
      className={`natalo-splash-overlay fixed inset-0 z-[9999] grid place-items-center bg-white px-6 py-[max(32px,env(safe-area-inset-top))] transition-opacity duration-200 [padding-bottom:max(32px,env(safe-area-inset-bottom))] ${
        leaving ? "pointer-events-none opacity-0" : "opacity-100"
      }`}
    >
      <div className="relative h-[min(46dvh,430px)] min-h-[320px] w-[min(86vw,360px)]">
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
