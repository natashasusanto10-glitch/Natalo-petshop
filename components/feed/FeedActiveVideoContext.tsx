"use client";

/**
 * Global state untuk single-autoplay: hanya 1 video yang play di seluruh
 * feed. Spec section 10.1 — saat scroll, video lama pause, video baru
 * autoplay. Saat pindah tab/background, semua video pause.
 *
 * Pattern: tiap FeedVideoPlayer register IntersectionObserver, kalau ≥60%
 * visible call setActiveId(myId). Player render dgn <video> autoplay
 * kalau activeId === myId, paused kalau bukan.
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

type FeedActiveVideoContextValue = {
  activeId: string | null;
  setActiveId: (id: string | null) => void;
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
  const [paused, setPaused] = useState(false);

  // Pause SEMUA video saat app masuk background (sesuai spec 10.13).
  // Saat foreground kembali, biarkan player pickup state berdasarkan
  // viewport visibility — JANGAN auto-resume tanpa user intent.
  useEffect(() => {
    function onVisibility() {
      setPaused(document.visibilityState !== "visible");
    }
    document.addEventListener("visibilitychange", onVisibility);
    onVisibility();
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, []);

  const setActiveId = useCallback((id: string | null) => {
    setActiveIdState((current) => (current === id ? current : id));
  }, []);

  const value = useMemo(
    () => ({ activeId, setActiveId, paused }),
    [activeId, setActiveId, paused],
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
