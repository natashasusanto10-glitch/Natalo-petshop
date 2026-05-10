"use client";

/**
 * Modal konfirmasi hapus — reusable, mobile-first, premium look.
 *
 * Dipakai di halaman Keranjang untuk:
 * - Hapus selected items (tombol merah atas)
 * - Hapus single item (icon trash per row)
 *
 * Props sesuai contract user spec di task brief.
 */

import { useEffect } from "react";
import { createPortal } from "react-dom";

export type ConfirmDeleteModalProps = {
  open: boolean;
  title: string;
  message: string;
  loading?: boolean;
  /** Custom label tombol hapus (default "Hapus") */
  confirmLabel?: string;
  /** Custom label loading (default "Menghapus...") */
  loadingLabel?: string;
  onCancel: () => void;
  onConfirm: () => void;
};

export function ConfirmDeleteModal({
  open,
  title,
  message,
  loading = false,
  confirmLabel = "Hapus",
  loadingLabel = "Menghapus...",
  onCancel,
  onConfirm,
}: ConfirmDeleteModalProps) {
  // Lock body scroll + ESC to cancel
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !loading) onCancel();
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.removeEventListener("keydown", onKey);
    };
  }, [open, loading, onCancel]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div
      className="fixed inset-0 z-[9999] flex items-center justify-center px-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="confirm-delete-title"
      aria-describedby="confirm-delete-message"
    >
      {/* Overlay — soft gray + blur */}
      <button
        type="button"
        aria-label="Tutup"
        onClick={() => {
          if (!loading) onCancel();
        }}
        className="absolute inset-0 bg-black/30 backdrop-blur-sm transition-opacity animate-in fade-in duration-200"
      />

      {/* Card */}
      <div className="relative w-full max-w-sm rounded-2xl bg-white p-5 shadow-xl animate-in fade-in zoom-in-95 duration-200">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-50">
          <svg
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            className="text-red-500"
            aria-hidden
          >
            <path d="M3 6h18" stroke="currentColor" strokeWidth={2} strokeLinecap="round" />
            <path d="M8 6V4h8v2" stroke="currentColor" strokeWidth={2} strokeLinecap="round" />
            <path
              d="M6 6l1 14h10l1-14"
              stroke="currentColor"
              strokeWidth={2}
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </div>

        <h3 id="confirm-delete-title" className="text-center text-lg font-bold text-slate-900">
          {title}
        </h3>

        <p
          id="confirm-delete-message"
          className="mt-2 text-center text-sm leading-6 text-slate-500"
        >
          {message}
        </p>

        <div className="mt-6 grid grid-cols-2 gap-3">
          <button
            type="button"
            onClick={onCancel}
            disabled={loading}
            className="h-11 rounded-xl border border-slate-200 bg-white text-sm font-semibold text-slate-700 transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-60"
          >
            Batal
          </button>

          <button
            type="button"
            onClick={onConfirm}
            disabled={loading}
            className="h-11 rounded-xl bg-red-500 text-sm font-semibold text-white transition active:scale-[0.98] active:bg-red-600 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {loading ? loadingLabel : confirmLabel}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}

export default ConfirmDeleteModal;
