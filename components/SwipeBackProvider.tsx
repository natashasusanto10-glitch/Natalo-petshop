"use client";

/**
 * Global swipe-back gesture provider untuk aplikasi mobile web.
 *
 * Cara kerja:
 * - User swipe dari tepi kiri layar (startX <= EDGE_SIZE) ke kanan
 * - Kalau swipe valid (deltaX > SWIPE_THRESHOLD, |deltaY| < MAX_VERTICAL),
 *   trigger router.back() — atau router.push("/") kalau no history
 *
 * Cross-platform behavior:
 * - iOS Capacitor native app: SKIP — gesture sudah dihandle native via
 *   SwipeBackPlugin (allowsBackForwardNavigationGestures). JS gesture
 *   bakal double-fire kalau aktif di sini.
 * - iOS Safari browser, Chrome Android, PWA: ACTIVE — JS gesture handle.
 *
 * Opt-out per element:
 *   <div data-no-swipe-back="true">...</div>
 *   atau tag input/textarea/select/button (auto)
 *
 * Opt-out global temporary (modal/sheet open):
 *   document.body.classList.add("modal-open" | "bottom-sheet-open")
 *
 * Confirmation flow (mis. checkout):
 *   document.body.dataset.swipeBackConfirm = "true";
 *   // optional copy override:
 *   document.body.dataset.swipeBackConfirmTitle = "Keluar dari checkout?";
 *   document.body.dataset.swipeBackConfirmMessage = "Data...";
 * → Saat swipe valid, modal konfirmasi muncul. Klik "Keluar" lanjut back,
 *   "Tetap di Halaman" cancel.
 */

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

type Props = {
  children: ReactNode;
};

const EDGE_SIZE = 30;
const SWIPE_THRESHOLD = 80;
const MAX_VERTICAL_MOVE = 40;

function isIOSCapacitorNative(): boolean {
  if (typeof window === "undefined") return false;
  // @ts-expect-error — Capacitor global injected at runtime di iOS WebView
  const cap = window.Capacitor;
  if (!cap) return false;
  try {
    return (
      typeof cap.isNativePlatform === "function" &&
      cap.isNativePlatform() &&
      typeof cap.getPlatform === "function" &&
      cap.getPlatform() === "ios"
    );
  } catch {
    return false;
  }
}

function shouldIgnoreSwipe(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (
    target.closest("input") ||
    target.closest("textarea") ||
    target.closest("select") ||
    target.closest("[data-no-swipe-back='true']") ||
    target.closest('[data-no-swipe-back="true"]')
  ) {
    return true;
  }
  // Modal / bottom sheet open — gesture jangan bentrok
  if (
    document.body.classList.contains("modal-open") ||
    document.body.classList.contains("bottom-sheet-open") ||
    document.body.classList.contains("voucher-modal-open") ||
    document.body.classList.contains("nat-modal-open")
  ) {
    return true;
  }
  return false;
}

export function SwipeBackProvider({ children }: Props) {
  const router = useRouter();
  const startX = useRef(0);
  const startY = useRef(0);
  const isEdgeSwipe = useRef(false);

  // Confirmation modal state (untuk halaman dgn data berisiko hilang)
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [confirmTitle, setConfirmTitle] = useState("Keluar dari halaman ini?");
  const [confirmMessage, setConfirmMessage] = useState(
    "Data yang belum disimpan mungkin hilang.",
  );

  // Native iOS Capacitor cek sekali saat mount — gesture handled native
  const skipGesture = useRef(false);
  useEffect(() => {
    skipGesture.current = isIOSCapacitorNative();
  }, []);

  function performBack() {
    if (typeof window !== "undefined" && window.history.length > 1) {
      router.back();
    } else {
      router.push("/");
    }
  }

  function handleTouchStart(e: React.TouchEvent<HTMLDivElement>) {
    if (skipGesture.current) return;
    if (shouldIgnoreSwipe(e.target)) {
      isEdgeSwipe.current = false;
      return;
    }
    const touch = e.touches[0];
    startX.current = touch.clientX;
    startY.current = touch.clientY;
    isEdgeSwipe.current = touch.clientX <= EDGE_SIZE;
  }

  function handleTouchEnd(e: React.TouchEvent<HTMLDivElement>) {
    if (skipGesture.current) return;
    if (!isEdgeSwipe.current) return;

    const touch = e.changedTouches[0];
    const deltaX = touch.clientX - startX.current;
    const deltaY = Math.abs(touch.clientY - startY.current);

    isEdgeSwipe.current = false;

    const isSwipeBack = deltaX > SWIPE_THRESHOLD && deltaY < MAX_VERTICAL_MOVE;
    if (!isSwipeBack) return;

    // Cek apakah halaman saat ini opt-in confirmation
    const needsConfirm =
      typeof document !== "undefined" &&
      document.body.dataset.swipeBackConfirm === "true";

    if (needsConfirm) {
      const customTitle = document.body.dataset.swipeBackConfirmTitle;
      const customMsg = document.body.dataset.swipeBackConfirmMessage;
      if (customTitle) setConfirmTitle(customTitle);
      if (customMsg) setConfirmMessage(customMsg);
      setConfirmOpen(true);
      return;
    }

    performBack();
  }

  function handleConfirm() {
    setConfirmOpen(false);
    performBack();
  }

  function handleCancel() {
    setConfirmOpen(false);
  }

  return (
    <>
      <div
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
        style={{ minHeight: "100dvh" }}
      >
        {children}
      </div>

      {confirmOpen &&
        typeof document !== "undefined" &&
        createPortal(
          <ExitConfirmModal
            title={confirmTitle}
            message={confirmMessage}
            onCancel={handleCancel}
            onConfirm={handleConfirm}
          />,
          document.body,
        )}
    </>
  );
}

function ExitConfirmModal({
  title,
  message,
  onCancel,
  onConfirm,
}: {
  title: string;
  message: string;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onCancel();
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.removeEventListener("keydown", onKey);
    };
  }, [onCancel]);

  return (
    <div
      className="fixed inset-0 z-[9999] flex items-center justify-center px-4"
      role="dialog"
      aria-modal="true"
    >
      <button
        type="button"
        aria-label="Tutup"
        onClick={onCancel}
        className="absolute inset-0 bg-black/30 backdrop-blur-sm animate-in fade-in duration-200"
      />
      <div className="relative w-full max-w-sm rounded-2xl bg-white p-5 shadow-xl animate-in fade-in zoom-in-95 duration-200">
        <h3 className="text-center text-lg font-bold text-slate-900">{title}</h3>
        <p className="mt-2 text-center text-sm leading-6 text-slate-500">{message}</p>
        <div className="mt-6 grid grid-cols-2 gap-3">
          <button
            type="button"
            onClick={onCancel}
            className="h-11 rounded-xl border border-slate-200 bg-white text-sm font-semibold text-slate-700 transition active:scale-[0.98]"
          >
            Tetap di Halaman
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className="h-11 rounded-xl bg-red-500 text-sm font-semibold text-white transition active:scale-[0.98] active:bg-red-600"
          >
            Keluar
          </button>
        </div>
      </div>
    </div>
  );
}

export default SwipeBackProvider;
