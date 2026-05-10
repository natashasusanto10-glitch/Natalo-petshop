"use client";

/**
 * Voucher claim bar di halaman keranjang. Muncul di atas daftar produk
 * sebagai entry point ke bottom sheet pemilihan voucher member + private.
 *
 * Sesuai aturan Natalo: voucher hanya untuk user login (member). Bar tetap
 * tampil untuk guest, tapi klik akan minta login.
 */

import { formatRupiah } from "@/lib/format";

type Props = {
  /** Apakah user sudah login (member). Mempengaruhi text & behavior. */
  isLoggedIn: boolean;
  /** Voucher member yg sudah dipilih (CUSTOMER). */
  memberVoucher: { code: string; discount: number } | null;
  /** Voucher private yg sudah di-apply (SELLER_MANUAL). */
  privateVoucher: { code: string; discount: number } | null;
  /** Klik bar (mobile keseluruhan area) — buka bottom sheet atau redirect login. */
  onClick: () => void;
};

export function VoucherClaimBar({
  isLoggedIn,
  memberVoucher,
  privateVoucher,
  onClick,
}: Props) {
  const totalApplied = (memberVoucher ? 1 : 0) + (privateVoucher ? 1 : 0);
  const totalDiscount =
    (memberVoucher?.discount ?? 0) + (privateVoucher?.discount ?? 0);

  // Summary text saat ada voucher applied
  const summary = (() => {
    if (totalApplied === 0) return null;
    if (memberVoucher && privateVoucher) {
      return `Member + Private dipakai · Hemat ${formatRupiah(totalDiscount)}`;
    }
    if (memberVoucher) {
      return `${memberVoucher.code} dipakai · Hemat ${formatRupiah(memberVoucher.discount)}`;
    }
    if (privateVoucher) {
      return `${privateVoucher.code} dipakai · Hemat ${formatRupiah(privateVoucher.discount)}`;
    }
    return null;
  })();

  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-2xl border border-blue-100 bg-blue-50/70 px-4 py-3 text-left transition active:bg-blue-100/80"
      aria-label="Buka pilihan voucher"
    >
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white text-blue-600">
        <svg
          aria-hidden
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2}
          className="h-5 w-5"
        >
          <path
            d="M3 9V7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z"
            strokeLinejoin="round"
          />
          <path d="M9 9v6" strokeLinecap="round" strokeDasharray="2 2" />
        </svg>
      </span>
      <span className="min-w-0 flex-1">
        {summary ? (
          <>
            <span className="block text-sm font-extrabold text-blue-900">
              {totalApplied} voucher dipakai
            </span>
            <span className="mt-0.5 block truncate text-xs font-semibold text-blue-700">
              {summary}
            </span>
          </>
        ) : (
          <>
            <span className="block text-sm font-extrabold text-blue-900">
              Voucher Gratis Ongkir!
            </span>
            <span className="mt-0.5 block text-xs text-blue-700">
              {isLoggedIn
                ? "Eksklusif Khusus Member Natalo"
                : "Login dulu untuk klaim voucher member"}
            </span>
          </>
        )}
      </span>
      <span className="flex shrink-0 items-center gap-1 text-xs font-extrabold text-blue-700">
        {summary ? "Ubah" : "Klaim"}
        <svg
          aria-hidden
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2.5}
          className="h-4 w-4"
        >
          <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
    </button>
  );
}
