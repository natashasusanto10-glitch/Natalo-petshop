"use client";

import { useEffect, useState } from "react";

const SEEN_KEY = "natalo:splash-shown";

/**
 * Netflix-style splash reveal: "N" muncul dulu, lalu "atalo" smooth sliding in,
 * "PETSHOP" tagline fade in di bawah, lalu seluruh splash fade out.
 *
 * Hanya tampil sekali per session (gate pakai sessionStorage). Ke-trigger saat
 * user pertama buka app — di iOS native via TestFlight, ini overlay setelah
 * Capacitor SplashScreen plugin hide. Di web (PWA / Safari), ini splash tunggal
 * setelah WebView/browser load page pertama kali.
 */
export function AppSplashOverlay() {
  const [phase, setPhase] = useState<
    "hidden" | "show-n" | "reveal-rest" | "show-subtitle" | "fade-out" | "done"
  >("hidden");

  useEffect(() => {
    if (typeof window === "undefined") return;

    // Hanya show sekali per session
    if (sessionStorage.getItem(SEEN_KEY)) {
      setPhase("done");
      return;
    }
    sessionStorage.setItem(SEEN_KEY, "1");

    // Phase 1: "N" zoom-in (next frame, biar smooth)
    requestAnimationFrame(() => setPhase("show-n"));

    const timers: ReturnType<typeof setTimeout>[] = [
      setTimeout(() => setPhase("reveal-rest"), 450), // "atalo" slide in
      setTimeout(() => setPhase("show-subtitle"), 950), // "PETSHOP" fade in
      setTimeout(() => setPhase("fade-out"), 1700), // start fade out splash
      setTimeout(() => setPhase("done"), 2150), // unmount
    ];
    return () => timers.forEach(clearTimeout);
  }, []);

  if (phase === "done") return null;

  const isVisible = phase !== "fade-out";
  const showN = phase !== "hidden";
  const showRest =
    phase === "reveal-rest" || phase === "show-subtitle" || phase === "fade-out";
  const showSubtitle = phase === "show-subtitle" || phase === "fade-out";

  return (
    <div
      aria-hidden="true"
      className={`fixed inset-0 z-[9999] flex flex-col items-center justify-center bg-natalo-500 transition-opacity duration-500 ${
        isVisible ? "opacity-100" : "opacity-0 pointer-events-none"
      }`}
    >
      <div className="flex items-baseline">
        {/* "N" — zoom-in fade-in */}
        <span
          className={`font-black leading-none text-white text-[120px] sm:text-[160px] transition-all duration-500 ease-out ${
            showN
              ? "translate-y-0 scale-100 opacity-100"
              : "translate-y-2 scale-90 opacity-0"
          }`}
        >
          N
        </span>

        {/* "atalo" — slide-in from N's right edge */}
        <div
          className={`overflow-hidden ${
            showRest ? "max-w-[800px] duration-[700ms]" : "max-w-0 duration-0"
          } transition-[max-width] ease-out`}
        >
          <span className="font-black leading-none text-white text-[88px] sm:text-[120px] whitespace-nowrap pl-1">
            atalo
          </span>
        </div>
      </div>

      {/* "PETSHOP" tagline — fade in di bawah */}
      <div
        className={`mt-3 transition-all duration-500 ease-out ${
          showSubtitle ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"
        }`}
      >
        <span className="font-bold text-white/85 text-[16px] sm:text-[22px] tracking-[0.4em]">
          PETSHOP
        </span>
      </div>
    </div>
  );
}
