"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { SwipeBack } from "@/lib/native/swipe-back";

/**
 * The native WKWebView swipe gesture jumps history immediately, so keep it
 * disabled. Interactive page dragging is handled by SwipeBackProvider.
 */
export function useSwipeBack() {
  const pathname = usePathname();

  useEffect(() => {
    void SwipeBack.disable();
    return () => {
      void SwipeBack.disable();
    };
  }, [pathname]);
}
