"use client";

/**
 * Voucher claim bar di halaman keranjang. Muncul di atas daftar produk
 * sebagai entry point ke bottom sheet pemilihan voucher member.
 *
 * Voucher private/manual tidak muncul di cart; kode khusus penjual hanya
 * dimasukkan di checkout.
 */

import { formatRupiah } from "@/lib/format";

type Props = {
  isLoggedIn: boolean;
  memberVoucher: { code: string; discount: number; kind?: string } | null;
  memberVoucherCount?: number;
  memberVoucherSummary?: string;
  previewVoucher?: { discount: number; minimumOrder: number; kind?: string } | null;
  onClick: () => void;
};

export function VoucherClaimBar({
  isLoggedIn,
  memberVoucher,
  memberVoucherCount = memberVoucher ? 1 : 0,
  memberVoucherSummary,
  previewVoucher,
  onClick,
}: Props) {
  const summary = memberVoucherCount > 0
    ? memberVoucherSummary ??
      (memberVoucher?.kind === "FREE_SHIPPING"
        ? "Voucher member dipakai · Gratis ongkir"
        : `Voucher member dipakai · Hemat ${formatRupiah(memberVoucher?.discount ?? 0)}`)
    : null;
  const preview = previewVoucher?.kind === "FREE_SHIPPING"
    ? "Gratis Ongkir"
    : previewVoucher?.discount
    ? `Diskon ${formatRupiah(previewVoucher.discount)}`
    : "Voucher Member Natalo";
  const previewMinOrder =
    previewVoucher && previewVoucher.minimumOrder > 0
      ? `Min. belanja ${formatRupiah(previewVoucher.minimumOrder)}`
      : "Eksklusif khusus member Natalo";

  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-left shadow-sm transition active:bg-amber-100"
      aria-label="Buka pilihan voucher"
    >
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white text-amber-600 shadow-sm">
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
              {memberVoucherCount} voucher dipakai
            </span>
            <span className="mt-0.5 block truncate text-xs font-semibold text-amber-700">
              {summary}
            </span>
          </>
        ) : (
          <>
            <span className="block text-sm font-extrabold text-amber-950">
              {isLoggedIn ? preview : "Voucher Member Natalo"}
            </span>
            <span className="mt-0.5 block text-xs font-semibold text-amber-700">
              {isLoggedIn
                ? previewMinOrder
                : "Login dulu untuk klaim voucher member"}
            </span>
          </>
        )}
      </span>
      <span className="flex shrink-0 items-center gap-1 text-xs font-extrabold text-amber-700">
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
