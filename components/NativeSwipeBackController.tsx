"use client";

/**
 * Mount-only component yg jalankan useSwipeBack hook untuk auto-toggle
 * iOS native edge-swipe gesture berdasarkan pathname.
 *
 * Render null. Mount sekali di root layout supaya berjalan global.
 * Lihat hooks/useSwipeBack.ts untuk daftar pathname yg disable gesture.
 */

import { useSwipeBack } from "@/hooks/useSwipeBack";

export function NativeSwipeBackController() {
  useSwipeBack();
  return null;
}
