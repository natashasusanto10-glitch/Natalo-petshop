"use client";

import { useRef, useState } from "react";
import type { ReactNode } from "react";

/**
 * Swipe-to-delete wrapper untuk cart row.
 *
 * Pattern iOS native: swipe ke kiri → reveal delete action / full swipe →
 * langsung commit delete. Tap action button = delete. Release tanpa reach
 * threshold = snap back ke posisi 0.
 *
 * Tanpa framer-motion / lucide — pakai native pointer events + CSS transform.
 * touch-action: pan-y supaya vertical scroll page tetap jalan saat user
 * scroll list cart (cuma horizontal yang ditangkap component).
 *
 * Wrapper ini hanya handle gesture + delete action overlay. Konten row
 * di-passing via `children` (tetap render seperti biasa di parent).
 *
 * Parent yang trigger optimistic remove + undo toast (lihat app/cart/page.tsx).
 */
type Props = {
  onDelete: () => void;
  /** Disabled state — saat item lagi pending delete commit (tidak boleh re-swipe) */
  disabled?: boolean;
  children: ReactNode;
};

// Pixel thresholds — kalibrasi feel mirip iOS Mail/WhatsApp
const REVEAL_THRESHOLD = -40;
const COMMIT_THRESHOLD = -180;
const ACTION_WIDTH = 88;
const SNAP_OPEN_X = -ACTION_WIDTH;
const MAX_PULL = -260;

export function SwipeableCartRow({ onDelete, disabled, children }: Props) {
  const [dragX, setDragX] = useState(0);
  const [isOpen, setIsOpen] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const startXRef = useRef<number | null>(null);
  const startYRef = useRef<number | null>(null);
  const isHorizontalRef = useRef<boolean | null>(null);
  const pointerIdRef = useRef<number | null>(null);
  // Guard untuk prevent double-delete: setelah commit threshold reached,
  // setTimeout(onDelete, 160ms) di-schedule untuk animation. User bisa
  // swipe lagi atau tap action button dalam 160ms window → second onDelete
  // fired. Flag ini block subsequent gesture/click selama commit pending.
  const isCommittingRef = useRef(false);

  function reset() {
    startXRef.current = null;
    startYRef.current = null;
    isHorizontalRef.current = null;
    pointerIdRef.current = null;
    setIsDragging(false);
  }

  function commitDelete() {
    if (isCommittingRef.current) return;
    isCommittingRef.current = true;
    setDragX(-500);
    setIsOpen(false);
    setTimeout(() => onDelete(), 160);
  }

  function handlePointerDown(e: React.PointerEvent<HTMLDivElement>) {
    if (disabled || isCommittingRef.current) return;
    // Hanya respond ke touch + mouse left button
    if (e.pointerType === "mouse" && e.button !== 0) return;
    startXRef.current = e.clientX;
    startYRef.current = e.clientY;
    isHorizontalRef.current = null;
    pointerIdRef.current = e.pointerId;
    setIsDragging(true);
  }

  function handlePointerMove(e: React.PointerEvent<HTMLDivElement>) {
    if (startXRef.current === null || startYRef.current === null) return;
    if (pointerIdRef.current !== e.pointerId) return;

    const deltaX = e.clientX - startXRef.current;
    const deltaY = e.clientY - startYRef.current;

    // Decide direction once (5px hysteresis) — supaya vertical scroll page
    // tidak kepotong sama gesture component.
    if (isHorizontalRef.current === null) {
      const absX = Math.abs(deltaX);
      const absY = Math.abs(deltaY);
      if (absX < 5 && absY < 5) return;
      isHorizontalRef.current = absX > absY;
    }

    if (!isHorizontalRef.current) return;

    // Capture pointer setelah konfirmasi horizontal — release control vertical
    // scroll ke browser.
    if (e.currentTarget.hasPointerCapture(e.pointerId) === false) {
      try {
        e.currentTarget.setPointerCapture(e.pointerId);
      } catch {
        // Some browsers may reject; ignore
      }
    }

    // Translate berbasis posisi awal (0 atau -ACTION_WIDTH kalau sudah open)
    const baseX = isOpen ? SNAP_OPEN_X : 0;
    let next = baseX + deltaX;
    if (next > 0) next = 0; // No right-swipe
    if (next < MAX_PULL) next = MAX_PULL; // Hard limit
    setDragX(next);
  }

  function handlePointerUp(e: React.PointerEvent<HTMLDivElement>) {
    if (startXRef.current === null) {
      reset();
      return;
    }

    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch {
      // ignore
    }

    if (!isHorizontalRef.current) {
      reset();
      return;
    }

    const finalX = dragX;

    if (finalX < COMMIT_THRESHOLD) {
      // Full swipe → commit delete. commitDelete() handle dedup via flag.
      commitDelete();
    } else if (finalX < REVEAL_THRESHOLD) {
      // Snap to revealed state — user bisa tap "Hapus" button
      setDragX(SNAP_OPEN_X);
      setIsOpen(true);
    } else {
      // Snap back closed
      setDragX(0);
      setIsOpen(false);
    }

    reset();
  }

  function handleActionClick() {
    if (disabled || isCommittingRef.current) return;
    commitDelete();
  }

  function handleBackdropClick() {
    // Tap di luar row saat terbuka → tutup
    if (isOpen) {
      setDragX(0);
      setIsOpen(false);
    }
  }

  return (
    <div className="relative overflow-hidden">
      {/* Action layer — di belakang row, tampil saat drag/open */}
      <div className="pointer-events-none absolute inset-y-0 right-0 flex items-stretch">
        <button
          type="button"
          onClick={handleActionClick}
          onPointerDown={(e) => e.stopPropagation()}
          aria-label="Hapus item dari keranjang"
          className={`pointer-events-auto flex w-[88px] items-center justify-center bg-red-500 text-white transition-opacity ${
            dragX < REVEAL_THRESHOLD ? "opacity-100" : "opacity-0"
          }`}
        >
          <span className="flex flex-col items-center gap-1">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} className="h-5 w-5">
              <polyline points="3 6 5 6 21 6" strokeLinecap="round" />
              <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" strokeLinecap="round" />
              <path d="M10 11v6M14 11v6" strokeLinecap="round" />
              <path d="M9 6V4h6v2" strokeLinecap="round" />
            </svg>
            <span className="text-[11px] font-bold">Hapus</span>
          </span>
        </button>
      </div>

      {/* Foreground — content row yang bisa di-swipe */}
      <div
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerUp}
        onClick={handleBackdropClick}
        style={{
          transform: `translateX(${dragX}px)`,
          transition: isDragging ? "none" : "transform 220ms cubic-bezier(0.4, 0, 0.2, 1)",
          touchAction: "pan-y",
        }}
        className="relative z-10 bg-white"
      >
        {children}
      </div>
    </div>
  );
}
