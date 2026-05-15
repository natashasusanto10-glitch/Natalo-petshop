"use client";

import { useEffect } from "react";
import { SwipeBack } from "@/lib/native/swipe-back";

/**
 * Compatibility mount for older layouts. The actual interactive gesture lives
 * in SwipeBackProvider; this component only prevents native WKWebView swipe
 * from firing an immediate history.back().
 */
export default function IOSSwipeBack() {
  useEffect(() => {
    void SwipeBack.disable();
  }, []);

  return null;
}
