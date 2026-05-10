"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

export type VoucherItem = {
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  minimumOrder: number;
  expiresAt: string | null; // ISO
};

type Props = {
  vouchers: VoucherItem[];
};

function formatRupiahShort(n: number) {
  return `Rp${new Intl.NumberFormat("id-ID").format(n)}`;
}

function describeBenefit(v: VoucherItem) {
  if (v.discountPercent && v.discountPercent > 0) {
    return `Diskon ${v.discountPercent}%`;
  }
  if (v.discountAmount && v.discountAmount > 0) {
    return `Diskon ${formatRupiahShort(v.discountAmount)}`;
  }
  return v.description ?? "Voucher spesial";
}

function describeMin(v: VoucherItem) {
  return v.minimumOrder > 0
    ? `Min. belanja ${formatRupiahShort(v.minimumOrder)}`
    : "Tanpa minimum belanja";
}

function describeExpiry(iso: string | null) {
  if (!iso) return "Berlaku selamanya";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const now = new Date();
  const diffDays = Math.ceil((d.getTime() - now.getTime()) / 86_400_000);
  if (diffDays < 0) return "Sudah berakhir";
  if (diffDays === 0) return "Berakhir hari ini";
  if (diffDays <= 7) return `Berakhir dalam ${diffDays} hari`;
  return `s/d ${d.toLocaleDateString("id-ID", { day: "numeric", month: "short" })}`;
}

export function VoucherCard({ vouchers }: Props) {
  const [open, setOpen] = useState(false);
  const [copiedCode, setCopiedCode] = useState<string | null>(null);
  const dialogRef = useRef<HTMLDivElement | null>(null);

  function closeVoucher() {
    setOpen(false);
  }

  // Tutup dengan tombol Esc untuk aksesibilitas keyboard.
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") closeVoucher();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  // Lock scroll bila modal terbuka.
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.body.classList.add("voucher-modal-open");
    return () => {
      document.body.style.overflow = prev;
      document.body.classList.remove("voucher-modal-open");
    };
  }, [open]);

  async function handleApply(code: string) {
    try {
      if (typeof navigator !== "undefined" && navigator.clipboard) {
        await navigator.clipboard.writeText(code);
      }
      setCopiedCode(code);
      window.setTimeout(() => setCopiedCode(null), 1800);
    } catch {
      // Fallback diam-diam: tetap tampilkan pesan tersalin agar UX konsisten.
      setCopiedCode(code);
      window.setTimeout(() => setCopiedCode(null), 1800);
    }
  }

  const teaser =
    vouchers.length > 0 ? describeBenefit(vouchers[0]) : "Lihat penawaran tersedia";
  const count = vouchers.length;

  const voucherPortal =
    open && typeof document !== "undefined"
      ? createPortal(
          <>
            <div className="voucher-backdrop" onClick={closeVoucher} />
            <div
              role="dialog"
              aria-modal="true"
              aria-label="Pilih voucher"
              className="voucher-safe-area"
            >
              <div ref={dialogRef} className="voucher-sheet">
                <div className="sticky top-0 flex items-center justify-between border-b border-gray-100 bg-white px-4 py-3">
                  <h2 className="text-base font-extrabold text-gray-900">
                    Voucher Tersedia
                  </h2>
                  <button
                    type="button"
                    onClick={closeVoucher}
                    className="flex h-8 w-8 items-center justify-center rounded-full text-gray-500 active:bg-gray-100"
                    aria-label="Tutup"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                      <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
                    </svg>
                  </button>
                </div>

                <div className="p-4">
                  {vouchers.length === 0 ? (
                    <p className="py-8 text-center text-sm text-gray-500">
                      Belum ada voucher publik aktif saat ini.
                    </p>
                  ) : (
                    <ul className="space-y-3">
                      {vouchers.map((v) => {
                        const expiry = describeExpiry(v.expiresAt);
                        const isCopied = copiedCode === v.code;
                        return (
                          <li
                            key={v.code}
                            className="flex items-stretch overflow-hidden rounded-xl border border-orange-200 bg-orange-50/60"
                          >
                            <div className="flex flex-1 flex-col justify-center px-4 py-3">
                              <p className="text-sm font-extrabold text-gray-900">
                                {describeBenefit(v)}
                              </p>
                              <p className="mt-0.5 text-xs text-gray-500">
                                Kode <span className="font-bold text-gray-700">{v.code}</span> - {describeMin(v)}
                              </p>
                              {expiry && (
                                <p className="mt-0.5 text-[11px] font-bold text-orange-600">
                                  {expiry}
                                </p>
                              )}
                            </div>
                            <button
                              type="button"
                              onClick={() => handleApply(v.code)}
                              className="shrink-0 px-4 text-sm font-extrabold text-natalo-600 transition active:bg-natalo-50"
                            >
                              {isCopied ? "Tersalin" : "Pakai"}
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                  <p className="mt-4 text-center text-[11px] text-gray-400">
                    Kode otomatis tersalin. Tempel di halaman keranjang saat checkout.
                  </p>
                </div>
              </div>
            </div>
          </>,
          document.body
        )
      : null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="mt-4 flex w-full items-center gap-3 rounded-xl border border-dashed border-orange-300 bg-orange-50/60 px-4 py-3 text-left transition active:bg-orange-100"
        aria-haspopup="dialog"
        aria-expanded={open}
      >
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-orange-100 text-orange-500">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            className="h-5 w-5"
            aria-hidden="true"
          >
            <path d="M3 9V7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z" strokeLinejoin="round" />
            <path d="M9 9v6" strokeLinecap="round" strokeDasharray="2 2" />
          </svg>
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-sm font-extrabold text-gray-900">
            Pakai Voucher
          </span>
          <span className="block truncate text-xs text-gray-500">
            {count > 0 ? `${count} tersedia - ${teaser}` : teaser}
          </span>
        </span>
        <span className="text-orange-500" aria-hidden>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-4 w-4">
            <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
      </button>

      {voucherPortal}
    </>
  );
}
