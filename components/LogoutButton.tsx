"use client";

import type { ReactNode } from "react";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { FiLogOut } from "react-icons/fi";
import { clearLocalCart } from "@/lib/cart";

interface LogoutButtonProps {
  redirectTo: string;
  className?: string;
  children?: ReactNode;
  confirmBeforeLogout?: boolean;
}

export function LogoutButton({
  redirectTo,
  className = "",
  children,
  confirmBeforeLogout = false,
}: LogoutButtonProps) {
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [loggingOut, setLoggingOut] = useState(false);

  useEffect(() => {
    if (!confirmOpen) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !loggingOut) {
        setConfirmOpen(false);
      }
    }

    document.addEventListener("keydown", handleKeyDown);

    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [confirmOpen, loggingOut]);

  async function handleLogout() {
    setLoggingOut(true);
    await fetch("/api/auth/logout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        scope: redirectTo.startsWith("/admin") ? "ADMIN" : "CUSTOMER",
      }),
    }).catch(() => {});
    clearLocalCart();
    window.location.replace(redirectTo);
  }

  function handleClick() {
    if (confirmBeforeLogout) {
      setConfirmOpen(true);
      return;
    }

    void handleLogout();
  }

  const confirmationModal =
    confirmOpen && typeof document !== "undefined"
      ? createPortal(
          <div
            className="fixed inset-0 z-[9999] flex items-center justify-center px-4"
            role="dialog"
            aria-modal="true"
            aria-labelledby="logout-confirmation-title"
            aria-describedby="logout-confirmation-description"
          >
            <button
              type="button"
              aria-label="Tutup konfirmasi logout"
              onClick={() => {
                if (!loggingOut) setConfirmOpen(false);
              }}
              className="absolute inset-0 bg-black/35"
            />

            <div className="relative w-full max-w-sm rounded-[24px] bg-white p-5 text-center shadow-[0_24px_60px_rgba(15,23,42,0.24)]">
              <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-red-50 text-red-500">
                <FiLogOut className="h-6 w-6" aria-hidden="true" />
              </div>

              <h2
                id="logout-confirmation-title"
                className="mt-4 text-lg font-black leading-tight text-slate-950"
              >
                Keluar dari akun?
              </h2>

              <div
                id="logout-confirmation-description"
                className="mt-2 space-y-2 text-sm font-semibold leading-6 text-slate-500"
              >
                <p>
                  Kamu perlu masuk kembali untuk melihat pesanan, poin, voucher, wishlist, dan
                  data akunmu.
                </p>
              </div>

              <div className="mt-6 grid grid-cols-2 gap-3">
                <button
                  type="button"
                  onClick={() => setConfirmOpen(false)}
                  disabled={loggingOut}
                  className="h-11 rounded-2xl border border-slate-200 bg-white text-sm font-black text-slate-700 transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  Batal
                </button>

                <button
                  type="button"
                  onClick={() => void handleLogout()}
                  disabled={loggingOut}
                  className="h-11 rounded-2xl bg-red-500 text-sm font-black text-white shadow-sm transition hover:bg-red-600 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {loggingOut ? "Memproses..." : "Keluar"}
                </button>
              </div>
            </div>
          </div>,
          document.body,
        )
      : null;

  return (
    <>
      <button
        type="button"
        onClick={handleClick}
        disabled={loggingOut}
        className={`rounded-full border border-gray-200 px-5 py-2.5 text-sm font-semibold text-gray-700 transition hover:border-red-300 hover:text-red-500 disabled:cursor-not-allowed disabled:opacity-70 ${className}`}
      >
        {children ?? "Keluar"}
      </button>
      {confirmationModal}
    </>
  );
}
