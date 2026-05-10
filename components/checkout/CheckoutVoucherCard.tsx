"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { formatRupiah } from "@/lib/format";

export type EligibleVoucher = {
  code: string;
  description: string | null;
  discount: number;
  minimumOrder: number;
  expiresAt: string | Date | null;
  status?: "available";
};

export type IneligibleVoucher = {
  code: string;
  description: string | null;
  minimumOrder: number;
  shortfall: number;
  expiresAt: string | Date | null;
  reason?: string;
  status?: "unavailable";
};

export type AppliedVoucher = {
  code: string;
  discount: number;
  description: string;
  autoApplied?: boolean;
};

type Props = {
  applied: AppliedVoucher | null;
  eligible: EligibleVoucher[];
  ineligible: IneligibleVoucher[];
  /** Pesan kalau voucher sebelumnya jadi tidak valid karena context berubah */
  invalidatedMessage?: string | null;
  loading?: boolean;
  onApply: (code: string, discount: number, description: string) => void;
  onRemove: () => void;
  /** Fallback: input kode manual (untuk voucher publik / promo dari poster) */
  onApplyManualCode: (code: string) => Promise<{ ok: boolean; error?: string }>;
};

function describeBenefit(v: { discount?: number; description: string | null }) {
  if (typeof v.discount === "number" && v.discount > 0) {
    return `Hemat ${formatRupiah(v.discount)}`;
  }
  return v.description ?? "Voucher spesial";
}

export function CheckoutVoucherCard({
  applied,
  eligible,
  ineligible,
  invalidatedMessage,
  loading = false,
  onApply,
  onRemove,
  onApplyManualCode,
}: Props) {
  const [open, setOpen] = useState(false);
  const [showManualInput, setShowManualInput] = useState(false);
  const [manualCode, setManualCode] = useState("");
  const [manualLoading, setManualLoading] = useState(false);
  const [manualError, setManualError] = useState("");
  const manualInputRef = useRef<HTMLInputElement | null>(null);

  // Tutup dengan Esc + lock scroll body saat sheet terbuka
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.body.classList.add("voucher-modal-open");
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.body.classList.remove("voucher-modal-open");
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;

    function updateKeyboardInset() {
      const viewport = window.visualViewport;
      const inset = viewport
        ? Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop)
        : 0;
      document.documentElement.style.setProperty("--nat-keyboard-inset", `${Math.round(inset)}px`);
    }

    updateKeyboardInset();
    window.visualViewport?.addEventListener("resize", updateKeyboardInset);
    window.visualViewport?.addEventListener("scroll", updateKeyboardInset);
    window.addEventListener("resize", updateKeyboardInset);

    return () => {
      window.visualViewport?.removeEventListener("resize", updateKeyboardInset);
      window.visualViewport?.removeEventListener("scroll", updateKeyboardInset);
      window.removeEventListener("resize", updateKeyboardInset);
      document.documentElement.style.removeProperty("--nat-keyboard-inset");
    };
  }, [open]);

  // Reset manual input state tiap kali sheet ditutup
  useEffect(() => {
    if (!open) {
      setShowManualInput(false);
      setManualCode("");
      setManualError("");
    }
  }, [open]);

  useEffect(() => {
    if (!open || !showManualInput) return;
    const id = window.setTimeout(() => manualInputRef.current?.focus(), 80);
    return () => window.clearTimeout(id);
  }, [open, showManualInput]);

  async function handleApplyManual() {
    if (!manualCode.trim()) return;
    setManualLoading(true);
    setManualError("");
    const result = await onApplyManualCode(manualCode.trim().toUpperCase());
    setManualLoading(false);
    if (result.ok) {
      setOpen(false);
    } else {
      setManualError(result.error ?? "Kode voucher tidak valid.");
    }
  }

  const eligibleCount = eligible.length;
  const hasAnyMine = eligibleCount > 0 || ineligible.length > 0;

  // Render row card sesuai state
  const card = (() => {
    // STATE A: voucher terpakai
    if (applied) {
      return (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="flex w-full items-start gap-3 rounded-2xl border border-natalo-300 bg-natalo-50 px-4 py-3 text-left transition active:bg-natalo-100"
        >
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-white text-natalo-600">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5" aria-hidden>
              <path d="M3 9V7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z" strokeLinejoin="round" />
              <path d="M9 9v6" strokeLinecap="round" strokeDasharray="2 2" />
            </svg>
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-sm font-extrabold text-zinc-950">
              {applied.code} terpakai
            </span>
            <span className="mt-0.5 block truncate text-xs font-semibold text-natalo-700">
              Hemat {formatRupiah(applied.discount)}
              {applied.autoApplied && (
                <span className="ml-2 rounded-full bg-natalo-100 px-1.5 py-0.5 text-[10px] font-bold text-natalo-800">
                  Otomatis
                </span>
              )}
            </span>
          </span>
          <span className="shrink-0 self-center text-xs font-bold text-natalo-700">
            Ubah ›
          </span>
        </button>
      );
    }

    // STATE B: ada voucher bisa digunakan tapi belum dipilih
    if (eligibleCount > 0) {
      return (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="flex w-full items-start gap-3 rounded-2xl border border-natalo-300 bg-natalo-50 px-4 py-3 text-left transition active:bg-natalo-100"
        >
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-white text-natalo-600">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5" aria-hidden>
              <path d="M3 9V7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z" strokeLinejoin="round" />
              <path d="M9 9v6" strokeLinecap="round" strokeDasharray="2 2" />
            </svg>
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-sm font-extrabold text-zinc-950">
              {eligibleCount} voucher bisa digunakan
            </span>
            <span className="mt-0.5 block text-xs text-zinc-500">
              Pilih voucher untuk pesanan ini
            </span>
          </span>
          <span className="shrink-0 self-center text-xs font-bold text-natalo-700">
            Pilih ›
          </span>
        </button>
      );
    }

    if (loading) {
      return (
        <div className="flex w-full items-start gap-3 rounded-2xl border border-zinc-200 bg-white px-4 py-3 text-left">
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-zinc-100 text-zinc-400">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5" aria-hidden>
              <path d="M3 9V7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z" strokeLinejoin="round" />
              <path d="M9 9v6" strokeLinecap="round" strokeDasharray="2 2" />
            </svg>
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-sm font-bold text-zinc-700">
              Mengecek voucher...
            </span>
            <span className="mt-0.5 block text-xs text-zinc-500">
              Menyesuaikan dengan total pesanan
            </span>
          </span>
        </div>
      );
    }

    // STATE C: tidak ada voucher yang bisa digunakan
    // Tetap clickable agar user bisa lihat ineligible / masukkan kode manual
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex w-full items-start gap-3 rounded-2xl border border-zinc-200 bg-white px-4 py-3 text-left transition active:bg-zinc-50"
      >
        <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-zinc-100 text-zinc-400">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5" aria-hidden>
            <path d="M3 9V7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z" strokeLinejoin="round" />
            <path d="M9 9v6" strokeLinecap="round" strokeDasharray="2 2" />
          </svg>
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-sm font-bold text-zinc-700">
            Tidak ada voucher yang bisa digunakan
          </span>
          {hasAnyMine && (
            <span className="mt-0.5 block text-xs text-zinc-500">
              Lihat voucher yang kamu miliki
            </span>
          )}
        </span>
        <span className="shrink-0 self-center text-xs text-zinc-400">›</span>
      </button>
    );
  })();

  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">Voucher</label>
      <div className="mt-1">{card}</div>

      {invalidatedMessage && (
        <p className="mt-2 rounded-xl bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
          {invalidatedMessage}
        </p>
      )}

      {open && typeof document !== "undefined" &&
        createPortal(
          <>
            <div className="voucher-backdrop" onClick={() => setOpen(false)} />
            <div
              className="voucher-safe-area"
              role="dialog"
              aria-modal="true"
              aria-label={showManualInput ? "Masukkan Kode Voucher" : "Pilih Voucher"}
            >
              <div className="voucher-sheet">
                <div className="sticky top-0 z-10 flex items-center justify-between border-b border-zinc-100 bg-white px-4 py-3">
                  <div className="flex items-center gap-2">
                    {showManualInput && (
                      <button
                        type="button"
                        onClick={() => {
                          setShowManualInput(false);
                          setManualError("");
                        }}
                        className="flex h-8 w-8 items-center justify-center rounded-full text-zinc-500 active:bg-zinc-100"
                        aria-label="Kembali"
                      >
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                          <path d="M15 6l-6 6 6 6" strokeLinecap="round" strokeLinejoin="round" />
                        </svg>
                      </button>
                    )}
                    <h2 className="text-base font-extrabold text-zinc-950">
                      {showManualInput ? "Masukkan Kode Voucher" : "Pilih Voucher"}
                    </h2>
                  </div>
                  <button
                    type="button"
                    onClick={() => setOpen(false)}
                    className="flex h-8 w-8 items-center justify-center rounded-full text-zinc-500 active:bg-zinc-100"
                    aria-label="Tutup"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                      <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
                    </svg>
                  </button>
                </div>

                {showManualInput ? (
                  <>
                    <div className="min-h-0 flex-1 overflow-y-auto p-4">
                      <label className="block text-sm font-bold text-zinc-800" htmlFor="manual-voucher-code">
                        Masukkan kode voucher
                      </label>
                      <input
                        ref={manualInputRef}
                        id="manual-voucher-code"
                        type="text"
                        inputMode="text"
                        autoCapitalize="characters"
                        value={manualCode}
                        onChange={(e) => setManualCode(e.target.value.toUpperCase())}
                        placeholder="Masukkan kode voucher"
                        className="mt-2 block w-full rounded-2xl border border-zinc-200 px-4 py-3 text-base uppercase tracking-wide outline-none focus:border-natalo-400"
                        onKeyDown={(e) =>
                          e.key === "Enter" && (e.preventDefault(), handleApplyManual())
                        }
                      />
                      {manualError && (
                        <p className="mt-3 rounded-xl bg-red-50 px-3 py-2 text-xs font-semibold text-red-600">
                          {manualError}
                        </p>
                      )}
                    </div>
                    <div className="sticky bottom-0 z-10 border-t border-zinc-100 bg-white px-4 pt-3 [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
                      <button
                        type="button"
                        onClick={handleApplyManual}
                        disabled={manualLoading || !manualCode.trim()}
                        className="w-full rounded-2xl bg-natalo-600 px-4 py-3 text-sm font-black text-white transition active:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
                      >
                        {manualLoading ? "Menerapkan..." : "Terapkan"}
                      </button>
                    </div>
                  </>
                ) : (
                  <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-4">
                    <section>
                      <h3 className="text-xs font-bold uppercase tracking-wide text-zinc-500">
                        Bisa digunakan
                      </h3>
                      {eligible.length === 0 ? (
                        <p className="mt-2 rounded-xl bg-zinc-50 px-3 py-3 text-sm text-zinc-500">
                          Belum ada voucher yang memenuhi syarat untuk pesanan ini.
                        </p>
                      ) : (
                        <ul className="mt-2 space-y-2">
                          {eligible.map((v) => {
                            const isApplied = applied?.code === v.code;
                            return (
                              <li
                                key={v.code}
                                className={`flex items-stretch overflow-hidden rounded-xl border ${
                                  isApplied
                                    ? "border-natalo-400 bg-natalo-50"
                                    : "border-zinc-200 bg-white"
                                }`}
                              >
                                <div className="flex flex-1 flex-col justify-center px-3 py-3">
                                  <p className="text-sm font-extrabold text-zinc-950">{v.code}</p>
                                  <p className="mt-0.5 text-xs font-semibold text-natalo-700">
                                    {describeBenefit(v)}
                                  </p>
                                  <p className="mt-0.5 text-[11px] text-zinc-500">
                                    {v.minimumOrder > 0
                                      ? `Min. belanja ${formatRupiah(v.minimumOrder)}`
                                      : "Tanpa minimum belanja"}
                                  </p>
                                </div>
                                <button
                                  type="button"
                                  disabled={isApplied}
                                  onClick={() => {
                                    onApply(v.code, v.discount, v.description ?? describeBenefit(v));
                                    setOpen(false);
                                  }}
                                  className={`shrink-0 px-4 text-sm font-extrabold transition ${
                                    isApplied
                                      ? "cursor-default text-natalo-700"
                                      : "text-natalo-600 active:bg-natalo-50"
                                  }`}
                                >
                                  {isApplied ? "Terpakai" : "Pakai"}
                                </button>
                              </li>
                            );
                          })}
                        </ul>
                      )}
                    </section>

                    {ineligible.length > 0 && (
                      <section>
                        <h3 className="text-xs font-bold uppercase tracking-wide text-zinc-500">
                          Belum bisa digunakan
                        </h3>
                        <ul className="mt-2 space-y-2">
                          {ineligible.map((v) => (
                            <li
                              key={v.code}
                              className="rounded-xl border border-zinc-200 bg-zinc-50/60 px-3 py-3"
                            >
                              <p className="text-sm font-bold text-zinc-700">{v.code}</p>
                              <p className="mt-0.5 text-xs text-zinc-500">
                                {v.description ?? `Min. belanja ${formatRupiah(v.minimumOrder)}`}
                              </p>
                              <p className="mt-0.5 text-[11px] font-bold text-amber-700">
                                {v.reason ?? `Belanja kurang ${formatRupiah(v.shortfall)} lagi`}
                              </p>
                            </li>
                          ))}
                        </ul>
                      </section>
                    )}

                    <div className="space-y-2 border-t border-zinc-100 pt-4">
                      {applied && (
                        <button
                          type="button"
                          onClick={() => {
                            onRemove();
                            setOpen(false);
                          }}
                          className="w-full rounded-xl border border-zinc-200 bg-white px-3 py-2.5 text-sm font-bold text-zinc-700 transition active:bg-zinc-50"
                        >
                          Lepas voucher {applied.code}
                        </button>
                      )}

                      <button
                        type="button"
                        onClick={() => setShowManualInput(true)}
                        className="w-full text-center text-xs font-bold text-natalo-600 hover:underline"
                      >
                        Punya kode voucher? Masukkan manual
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </>,
          document.body,
        )}
    </div>
  );
}
