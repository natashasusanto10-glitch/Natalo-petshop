"use client";

import { useEffect } from "react";
import { Button } from "./Button";

/**
 * ConfirmDialog — modal konfirmasi kanonik (ganti window.confirm). Overlay
 * fixed, tutup via tombol Batal / klik luar / Escape. Tombol memakai
 * type="button" supaya TIDAK men-submit form kalau dialog dirender di dalam
 * <form> (pemanggil yang atur submit lewat onConfirm).
 */
export function ConfirmDialog({
  open,
  title = "Konfirmasi",
  message,
  confirmLabel = "Ya, lanjut",
  cancelLabel = "Batal",
  variant = "danger",
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title?: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: "danger" | "primary";
  onConfirm: () => void;
  onCancel: () => void;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onCancel]);

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={title}
      className="fixed inset-0 z-[60] flex items-end justify-center bg-black/50 p-4 sm:items-center"
      onClick={onCancel}
    >
      <div
        className="w-full max-w-sm rounded-3xl bg-white p-5 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-3">
          <div
            className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-full ${
              variant === "danger"
                ? "bg-red-100 text-red-600"
                : "bg-natalo-100 text-natalo-700"
            }`}
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={2}
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-5 w-5"
              aria-hidden="true"
            >
              <path d="M12 9v4M12 17h.01M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z" />
            </svg>
          </div>
          <div className="min-w-0 flex-1 pt-0.5">
            <h2 className="text-base font-black text-zinc-950">{title}</h2>
            <p className="mt-1.5 text-sm leading-relaxed text-zinc-600">{message}</p>
          </div>
        </div>
        <div className="mt-5 flex gap-2.5">
          <Button type="button" variant="secondary" fullWidth onClick={onCancel}>
            {cancelLabel}
          </Button>
          <Button
            type="button"
            variant={variant === "danger" ? "danger" : "primary"}
            fullWidth
            onClick={onConfirm}
          >
            {confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  );
}
