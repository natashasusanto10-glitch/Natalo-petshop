"use client";

import { useEffect } from "react";
import { createPortal } from "react-dom";

interface Props {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
  /** Tombol di footer, optional. Misal "Apply" / "Reset" */
  footer?: React.ReactNode;
}

/**
 * Bottom sheet drawer dari bawah — mobile-friendly.
 * Backdrop klik untuk close. Esc juga close.
 * Body scroll di-lock saat open.
 */
export function BottomSheet({ open, onClose, title, children, footer }: Props) {
  // Lock body scroll and hide app-level fixed navigation while the sheet owns the screen.
  useEffect(() => {
    if (!open) return;
    const original = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.body.classList.add("nat-modal-open");
    return () => {
      document.body.style.overflow = original;
      document.body.classList.remove("nat-modal-open");
    };
  }, [open]);

  // Esc close
  useEffect(() => {
    if (!open) return;
    function handler(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open, onClose]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className="fixed inset-0 z-[2000] flex items-end overflow-hidden" aria-modal="true" role="dialog">
      {/* Backdrop */}
      <button
        type="button"
        aria-label="Tutup"
        onClick={onClose}
        className="absolute inset-0 bg-black/45 transition"
      />

      {/* Sheet */}
      <div
        className="relative ml-auto mr-auto flex max-h-[90dvh] w-full max-w-2xl flex-col overflow-hidden rounded-t-3xl bg-white shadow-2xl"
        style={{
          animation: "slideUp 250ms ease-out",
        }}
      >
        {/* Drag handle */}
        <div className="flex justify-center py-2">
          <div className="h-1.5 w-10 rounded-full bg-zinc-300" />
        </div>

        {/* Header */}
        {title && (
          <div className="flex items-center justify-between border-b border-zinc-100 px-5 pb-3">
            <h2 className="text-lg font-black text-zinc-950">{title}</h2>
            <button
              type="button"
              onClick={onClose}
              aria-label="Tutup"
              className="rounded-full p-1 text-zinc-400 hover:bg-zinc-100 hover:text-zinc-950"
            >
              ✕
            </button>
          </div>
        )}

        {/* Content (scrollable) */}
        <div
          className="min-h-0 flex-1 overflow-y-auto p-5"
        >
          {children}
        </div>

        {/* Footer */}
        {footer && (
          <div className="sticky bottom-0 z-10 shrink-0 border-t border-zinc-100 bg-white px-4 pt-4 [padding-bottom:calc(16px+env(safe-area-inset-bottom))]">
            {footer}
          </div>
        )}
      </div>

      {/* Inline animation keyframes */}
      <style jsx global>{`
        @keyframes slideUp {
          from {
            transform: translateY(100%);
          }
          to {
            transform: translateY(0);
          }
        }
      `}</style>
    </div>,
    document.body
  );
}
