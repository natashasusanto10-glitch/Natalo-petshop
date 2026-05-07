"use client";

import { useEffect } from "react";

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
  // Lock body scroll
  useEffect(() => {
    if (!open) return;
    const original = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = original;
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

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end" aria-modal="true" role="dialog">
      {/* Backdrop */}
      <button
        type="button"
        aria-label="Tutup"
        onClick={onClose}
        className="absolute inset-0 bg-black/40 transition"
      />

      {/* Sheet */}
      <div
        className="relative ml-auto mr-auto w-full max-w-2xl rounded-t-3xl bg-white shadow-2xl"
        style={{
          animation: "slideUp 250ms ease-out",
          maxHeight: "90vh",
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
          className="overflow-y-auto p-5"
          style={{ maxHeight: footer ? "calc(90vh - 180px)" : "calc(90vh - 80px)" }}
        >
          {children}
        </div>

        {/* Footer */}
        {footer && (
          <div className="border-t border-zinc-100 p-4">{footer}</div>
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
    </div>
  );
}
