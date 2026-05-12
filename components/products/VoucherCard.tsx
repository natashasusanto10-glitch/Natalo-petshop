"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

export type VoucherItem = {
  id: string;
  title: string;
  description: string | null;
  label: string;
  type: "member";
  discountPercent: number | null;
  discountAmount: number | null;
  minimumOrder: number;
  minPurchase?: number;
  expiresAt: string | null; // ISO
  visibility?: "member" | "private" | string;
  isPrivate?: boolean;
  isManualOnly?: boolean;
  usedByCurrentUser?: boolean;
  isActive?: boolean;
  isExpired?: boolean;
};

type Props = {
  /** Voucher list. Kalau di-pass dari server, langsung render.
   *  Kalau tidak (server tidak load voucher supaya HTML cacheable), VoucherCard
   *  akan fetch sendiri di client mount via /api/products/[slug]/vouchers. */
  vouchers?: VoucherItem[];
  /** Product slug — wajib kalau vouchers tidak di-pass (untuk client fetch). */
  productSlug?: string;
};

function formatRupiahShort(n: number) {
  return `Rp${new Intl.NumberFormat("id-ID").format(n)}`;
}

function describeBenefit(v: VoucherItem) {
  if (v.title) return v.title;
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

export function VoucherCard({ vouchers: vouchersProp, productSlug }: Props) {
  const [open, setOpen] = useState(false);
  const dialogRef = useRef<HTMLDivElement | null>(null);
  // Kalau vouchers tidak di-pass server-side, fetch sendiri client-side
  // dari /api/products/[slug]/vouchers. Pattern ini supaya halaman produk
  // bisa cacheable di Vercel CDN (HTML static) tanpa breaking voucher
  // display per-user.
  const [fetchedVouchers, setFetchedVouchers] = useState<VoucherItem[] | null>(null);
  const vouchers = vouchersProp ?? fetchedVouchers ?? [];

  useEffect(() => {
    // Skip kalau sudah dapat dari props
    if (vouchersProp || !productSlug) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/products/${productSlug}/vouchers`, {
          credentials: "include", // cookie session ikut → personalized list
        });
        if (!res.ok) return;
        const data = await res.json().catch(() => null);
        if (cancelled || !data?.vouchers) return;
        setFetchedVouchers(data.vouchers as VoucherItem[]);
      } catch {
        // ignore network/CORS errors — silent degrade ke "tidak ada voucher"
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [vouchersProp, productSlug]);

  const visibleProductVouchers = vouchers.filter((voucher) => {
    return (
      voucher.type === "member" &&
      voucher.visibility !== "private" &&
      !voucher.isPrivate &&
      !voucher.isManualOnly &&
      !voucher.usedByCurrentUser &&
      voucher.isActive !== false &&
      !voucher.isExpired
    );
  });

  function closeVoucher() {
    setOpen(false);
  }

  // Tutup dengan tombol Esc untuk aksesibilitas keyboard.
  // PENTING: hook ini harus declare SEBELUM early return supaya hooks count
  // konsisten antar render. Dulu return di atas → bug "Rendered more hooks
  // than during the previous render" muncul saat user login + fetch return
  // vouchers (render pertama 2 hooks, render kedua 4 hooks).
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

  // Jangan render kalau belum ada voucher (fetch belum balik atau memang
  // kosong). Early return WAJIB setelah semua hooks di-declare di atas.
  if (visibleProductVouchers.length === 0) return null;

  function handleUse() {
    closeVoucher();
    window.setTimeout(() => {
      document.getElementById("beli")?.scrollIntoView({
        behavior: "smooth",
        block: "start",
      });
    }, 80);
  }

  const teaser =
    visibleProductVouchers.length > 0
      ? describeBenefit(visibleProductVouchers[0])
      : "Lihat penawaran member";
  const count = visibleProductVouchers.length;

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
                  {visibleProductVouchers.length === 0 ? (
                    <p className="py-8 text-center text-sm text-gray-500">
                      Belum ada voucher member aktif saat ini.
                    </p>
                  ) : (
                    <ul className="space-y-3">
                      {visibleProductVouchers.map((v) => {
                        const expiry = describeExpiry(v.expiresAt);
                        return (
                          <li
                            key={v.id}
                            className="flex items-stretch overflow-hidden rounded-xl border border-orange-200 bg-orange-50/60"
                          >
                            <div className="flex flex-1 flex-col justify-center px-4 py-3">
                              <p className="text-sm font-extrabold text-gray-900">
                                {describeBenefit(v)}
                              </p>
                              <p className="mt-0.5 text-xs text-gray-500">
                                {describeMin(v)}
                              </p>
                              <p className="mt-0.5 text-[11px] font-bold text-orange-700">
                                {v.label}
                              </p>
                              {expiry && (
                                <p className="mt-0.5 text-[11px] font-bold text-orange-600">
                                  {expiry}
                                </p>
                              )}
                            </div>
                            <button
                              type="button"
                              onClick={handleUse}
                              className="shrink-0 px-4 text-sm font-extrabold text-natalo-600 transition active:bg-natalo-50"
                            >
                              Pakai
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
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
