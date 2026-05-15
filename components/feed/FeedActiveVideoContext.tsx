"use client";

/**
 * Global state untuk single-autoplay: hanya 1 video yang play di seluruh
 * feed. Spec section 10.1 — saat scroll, video lama pause, video baru
 * autoplay. Saat pindah tab/background, semua video pause.
 *
 * Pattern: tiap FeedVideoPlayer register IntersectionObserver, kalau ≥60%
 * visible call setActiveId(myId, myIndex). Player render dgn <video> autoplay
 * kalau activeId === myId, paused kalau bukan. activeIndex dipakai untuk
 * compute 3-tier preload distance (auto/metadata/none) di tiap player.
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { hapticTap } from "@/lib/native/haptics";

type FeedActiveVideoContextValue = {
  activeId: string | null;
  activeIndex: number | null;
  setActive: (id: string | null, index: number | null) => void;
  /**
   * Saat true (e.g. tab/page background, modal open), semua video harus
   * pause regardless activeId. Player baca flag ini untuk override
   * autoplay decision.
   */
  paused: boolean;
};

const FeedActiveVideoContext = createContext<FeedActiveVideoContextValue | null>(null);

export function FeedActiveVideoProvider({ children }: { children: React.ReactNode }) {
  const [activeId, setActiveIdState] = useState<string | null>(null);
  const [activeIndex, setActiveIndexState] = useState<number | null>(null);
  const [paused, setPaused] = useState(false);
  // Skip the haptic on the initial mount-time active set — only fire when
  // the user actually scrolls between videos. Compared by id, not index,
  // so a list re-render that keeps the same active post stays quiet.
  const lastActiveIdRef = useRef<string | null>(null);

  useEffect(() => {
    function onVisibility() {
      setPaused(document.visibilityState !== "visible");
    }
    document.addEventListener("visibilitychange", onVisibility);
    onVisibility();
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, []);

  const setActive = useCallback((id: string | null, index: number | null) => {
    setActiveIdState((current) => (current === id ? current : id));
    setActiveIndexState((current) => (current === index ? current : index));
    // Premium-feel haptic on actual scroll-driven changes only.
    if (id && id !== lastActiveIdRef.current) {
      if (lastActiveIdRef.current !== null) {
        void hapticTap();
      }
      lastActiveIdRef.current = id;
    }
  }, []);

  const value = useMemo(
    () => ({ activeId, activeIndex, setActive, paused }),
    [activeId, activeIndex, setActive, paused],
  );

  return (
    <FeedActiveVideoContext.Provider value={value}>{children}</FeedActiveVideoContext.Provider>
  );
}

export function useFeedActiveVideo() {
  const ctx = useContext(FeedActiveVideoContext);
  if (!ctx) throw new Error("useFeedActiveVideo must be used inside FeedActiveVideoProvider");
  return ctx;
}
