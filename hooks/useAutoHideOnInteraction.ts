"use client";

import { useEffect, useRef, useState } from "react";

type Options = {
  delay?: number;
  enabled?: boolean;
};

function shouldIgnoreAutoHide(event: Event) {
  const target = event.target;
  return target instanceof Element && Boolean(target.closest("[data-auto-hide-ignore='true']"));
}

export function useAutoHideOnInteraction({
  delay = 650,
  enabled = true,
}: Options = {}) {
  const [isVisible, setIsVisible] = useState(true);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    if (!enabled) {
      setIsVisible(false);
      return;
    }

    setIsVisible(true);

    const clearTimer = () => {
      if (!timerRef.current) return;
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    };

    const scheduleShow = () => {
      clearTimer();
      timerRef.current = window.setTimeout(() => {
        setIsVisible(true);
      }, delay);
    };

    const hideBar = (event: Event) => {
      if (shouldIgnoreAutoHide(event)) return;
      setIsVisible(false);
      scheduleShow();
    };

    const showBar = (event: Event) => {
      if (shouldIgnoreAutoHide(event)) return;
      scheduleShow();
    };

    window.addEventListener("scroll", hideBar, { passive: true });
    window.addEventListener("touchstart", hideBar, { passive: true });
    window.addEventListener("touchmove", hideBar, { passive: true });
    window.addEventListener("touchend", showBar, { passive: true });
    window.addEventListener("wheel", hideBar, { passive: true });

    return () => {
      window.removeEventListener("scroll", hideBar);
      window.removeEventListener("touchstart", hideBar);
      window.removeEventListener("touchmove", hideBar);
      window.removeEventListener("touchend", showBar);
      window.removeEventListener("wheel", hideBar);
      clearTimer();
    };
  }, [delay, enabled]);

  return isVisible;
}
