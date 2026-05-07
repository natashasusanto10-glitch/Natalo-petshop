"use client";

import { useState, useTransition, type ReactNode } from "react";

type Props = {
  action: () => Promise<void> | void;
  children: ReactNode;
  confirmMessage: string;
  confirmTitle?: string;
  confirmLabel?: string;
  variant?: "primary" | "danger" | "success" | "neutral";
  className?: string;
};

const VARIANT_STYLES: Record<NonNullable<Props["variant"]>, string> = {
  primary: "bg-zinc-950 text-white hover:bg-zinc-800",
  danger: "border border-red-200 text-red-600 hover:bg-red-50",
  success: "bg-emerald-600 text-white hover:bg-emerald-700",
  neutral: "border border-zinc-300 text-zinc-700 hover:border-zinc-500",
};

export function ConfirmButton({
  action,
  children,
  confirmMessage,
  confirmTitle = "Konfirmasi",
  confirmLabel = "Ya, lanjutkan",
  variant = "primary",
  className = "",
}: Props) {
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();

  function handleConfirm() {
    setOpen(false);
    startTransition(async () => {
      await action();
    });
  }

  return (
    <>
      <button
        type="button"
        disabled={pending}
        onClick={() => setOpen(true)}
        className={`w-full rounded-full px-5 py-3 text-sm font-bold transition disabled:cursor-not-allowed disabled:opacity-50 ${VARIANT_STYLES[variant]} ${className}`}
      >
        {pending ? "Memproses..." : children}
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
          onClick={() => setOpen(false)}
        >
          <div
            className="w-full max-w-sm rounded-3xl bg-white p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-lg font-black text-zinc-950">{confirmTitle}</h3>
            <p className="mt-2 text-sm text-zinc-600">{confirmMessage}</p>
            <div className="mt-6 flex gap-3">
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="flex-1 rounded-full border border-zinc-300 px-4 py-2.5 text-sm font-bold text-zinc-700 hover:border-zinc-500"
              >
                Batal
              </button>
              <button
                type="button"
                onClick={handleConfirm}
                className={`flex-1 rounded-full px-4 py-2.5 text-sm font-bold ${
                  variant === "danger"
                    ? "bg-red-600 text-white hover:bg-red-700"
                    : "bg-zinc-950 text-white hover:bg-zinc-800"
                }`}
              >
                {confirmLabel}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
