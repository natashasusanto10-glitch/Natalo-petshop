"use client";

import Link from "next/link";

/**
 * Empty state hangat — copy disamakan dengan app Flutter supaya pengalaman
 * web & app terasa satu suara.
 */
export function ProductsEmptyState({
  hasActiveFilters,
  onReset,
}: {
  hasActiveFilters: boolean;
  onReset: () => void;
}) {
  return (
    <div className="rounded-[var(--radius-xl)] border border-natalo-100 bg-natalo-50/60 px-6 py-12 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-white text-3xl shadow-[var(--shadow-card)]">
        🐾
      </div>
      <h2 className="mt-4 text-lg font-extrabold text-natalo-900">
        Produk tidak ditemukan
      </h2>
      <p className="mx-auto mt-1 max-w-sm text-sm text-zinc-600">
        Coba kata kunci lain atau ubah filter pencarian.
      </p>
      <div className="mt-5 flex flex-wrap items-center justify-center gap-2">
        {hasActiveFilters && (
          <button
            type="button"
            onClick={onReset}
            className="rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-black text-white transition active:scale-95 hover:bg-natalo-700"
          >
            Reset Filter
          </button>
        )}
        <Link
          href="/products"
          className="rounded-full border border-natalo-200 bg-white px-5 py-2.5 text-sm font-bold text-natalo-700 transition hover:bg-natalo-50"
        >
          Lihat semua produk
        </Link>
      </div>
    </div>
  );
}
