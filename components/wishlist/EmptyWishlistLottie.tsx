"use client";

import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const WISHLIST_LOTTIE_SRC = "/assets/lottie/empty_wishlist_natalo_blue.json";

function StaticWishlistFallback() {
  return (
    <svg viewBox="0 0 240 190" fill="none" aria-hidden="true" className="h-auto w-full">
      <ellipse cx="120" cy="104" rx="98" ry="66" fill="#EAF3FF" />
      <circle cx="52" cy="48" r="13" fill="#DBEAFE" />
      <circle cx="192" cy="54" r="10" fill="#DBEAFE" />
      <path d="M52 65c5-15 23-15 28 0" stroke="#BFDBFE" strokeWidth="5" strokeLinecap="round" />
      <circle cx="66" cy="86" r="23" fill="#fff" stroke="#BFDBFE" strokeWidth="3" />
      <path d="M50 76l9-17 8 17M75 76l10-17 8 17" fill="#fff" stroke="#BFDBFE" strokeWidth="3" strokeLinejoin="round" />
      <circle cx="58" cy="88" r="2.5" fill="#07112F" />
      <circle cx="74" cy="88" r="2.5" fill="#07112F" />
      <ellipse cx="66" cy="96" rx="4" ry="2.5" fill="#FF8FA3" />
      <circle cx="115" cy="91" r="25" fill="#F8FAFC" stroke="#BFDBFE" strokeWidth="3" />
      <ellipse cx="98" cy="90" rx="8" ry="15" fill="#DBEAFE" />
      <ellipse cx="132" cy="90" rx="8" ry="15" fill="#DBEAFE" />
      <circle cx="107" cy="90" r="2.5" fill="#07112F" />
      <circle cx="123" cy="90" r="2.5" fill="#07112F" />
      <ellipse cx="115" cy="101" rx="5" ry="3" fill="#07112F" />
      <rect x="152" y="70" width="48" height="42" rx="9" fill="#fff" stroke="#93C5FD" strokeWidth="3" />
      <rect x="159" y="78" width="34" height="24" rx="6" fill="#DBEAFE" />
      <path d="M169 90l11-6v12l-11-6Z" fill="#1E73E8" />
      <path d="M183 90l8-5v10l-8-5Z" fill="#60A5FA" />
      <circle cx="193" cy="78" r="2" fill="#fff" />
      <circle cx="188" cy="72" r="2.5" fill="#fff" opacity=".8" />
      <ellipse cx="37" cy="124" rx="14" ry="12" fill="#fff" stroke="#BFDBFE" strokeWidth="3" />
      <ellipse cx="30" cy="108" rx="5" ry="16" fill="#fff" stroke="#BFDBFE" strokeWidth="3" />
      <ellipse cx="44" cy="108" rx="5" ry="16" fill="#fff" stroke="#BFDBFE" strokeWidth="3" />
      <circle cx="32" cy="124" r="2" fill="#07112F" />
      <circle cx="42" cy="124" r="2" fill="#07112F" />
      <ellipse cx="91" cy="137" rx="17" ry="14" fill="#FEF3C7" stroke="#BFDBFE" strokeWidth="3" />
      <circle cx="83" cy="129" r="5" fill="#FEF3C7" stroke="#BFDBFE" strokeWidth="2" />
      <circle cx="99" cy="129" r="5" fill="#FEF3C7" stroke="#BFDBFE" strokeWidth="2" />
      <circle cx="86" cy="137" r="2" fill="#07112F" />
      <circle cx="96" cy="137" r="2" fill="#07112F" />
      <path d="M184 47c5-10 18-10 23 0 5-10 19-7 19 6 0 14-22 26-22 26s-22-12-22-26c0-5 1-8 2-6Z" fill="#FF8FA3" />
      <circle cx="52" cy="156" r="2.3" fill="#4A90E2" />
      <circle cx="60" cy="153" r="2.3" fill="#4A90E2" />
      <circle cx="68" cy="156" r="2.3" fill="#4A90E2" />
      <ellipse cx="60" cy="165" rx="7" ry="5" fill="#4A90E2" />
      <path d="M34 48v12M28 54h12M209 109v12M203 115h12" stroke="#1E73E8" strokeWidth="2.5" strokeLinecap="round" />
    </svg>
  );
}

export function EmptyWishlistLottie() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");

  useEffect(() => {
    let cancelled = false;

    async function loadWishlistAnimation() {
      try {
        const [lottie, response] = await Promise.all([
          import("lottie-web"),
          fetch(WISHLIST_LOTTIE_SRC, { cache: "force-cache" }),
        ]);

        if (!response.ok) throw new Error("Wishlist Lottie asset not found");
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

    void loadWishlistAnimation();

    return () => {
      cancelled = true;
      animationRef.current?.destroy();
      animationRef.current = null;
    };
  }, []);

  return (
    <div className="mx-auto mb-5 grid w-full max-w-[250px] place-items-center">
      <div
        ref={containerRef}
        className={status === "error" ? "hidden" : "h-auto w-full"}
        aria-hidden="true"
      />
      {status !== "ready" ? <StaticWishlistFallback /> : null}
    </div>
  );
}
