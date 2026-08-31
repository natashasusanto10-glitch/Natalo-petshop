import Link from "next/link";
import { paginationRange } from "@/lib/admin/pagination-range";

/**
 * Paginasi bernomor untuk daftar admin.
 *
 * Sebelumnya semua daftar hanya punya "← Sebelumnya / Selanjutnya →". Katalog
 * produk 29 halaman berarti 28 klik untuk sampai ke halaman terakhir, dan tak
 * ada cara tahu sedang di mana selain membaca teksnya.
 *
 * `hrefFor` sengaja diminta dari pemanggil, bukan dirakit di sini: tiap halaman
 * admin punya kombinasi filternya sendiri (status, tab, pencarian) yang WAJIB
 * ikut terbawa — kalau komponen ini merakit URL sendiri, klik nomor halaman
 * akan diam-diam membuang filter yang sedang aktif.
 */
export function Pagination({
  currentPage,
  totalPages,
  hrefFor,
  summary,
}: {
  currentPage: number;
  totalPages: number;
  hrefFor: (page: number) => string;
  /** Teks kecil di kiri, mis. "1.405 produk". */
  summary?: string;
}) {
  if (totalPages <= 1) return null;

  const slots = paginationRange(currentPage, totalPages);

  return (
    <nav
      aria-label="Navigasi halaman"
      className="mt-6 flex flex-wrap items-center justify-between gap-3"
    >
      <p className="text-sm text-zinc-500">
        Halaman <span className="font-black text-zinc-950">{currentPage}</span> dari{" "}
        <span className="font-black text-zinc-950">{totalPages}</span>
        {summary ? ` · ${summary}` : ""}
      </p>

      <div className="flex flex-wrap items-center gap-1">
        {currentPage > 1 && (
          <Link
            href={hrefFor(currentPage - 1)}
            aria-label="Halaman sebelumnya"
            className="inline-flex h-11 min-w-11 items-center justify-center rounded-full border border-zinc-300 px-3 text-sm font-bold text-zinc-700 transition hover:bg-zinc-50"
          >
            ←
          </Link>
        )}

        {slots.map((slot, i) =>
          slot === "gap" ? (
            <span
              // Dua "gap" bisa muncul bersamaan, jadi kuncinya pakai posisi.
              key={`gap-${i}`}
              aria-hidden="true"
              className="px-1 text-sm font-bold text-zinc-400"
            >
              …
            </span>
          ) : slot === currentPage ? (
            <span
              key={slot}
              aria-current="page"
              className="inline-flex h-11 min-w-11 items-center justify-center rounded-full bg-natalo-600 px-3 text-sm font-black text-white"
            >
              {slot}
            </span>
          ) : (
            <Link
              key={slot}
              href={hrefFor(slot)}
              aria-label={`Halaman ${slot}`}
              className="inline-flex h-11 min-w-11 items-center justify-center rounded-full border border-zinc-300 px-3 text-sm font-bold text-zinc-700 transition hover:bg-zinc-50"
            >
              {slot}
            </Link>
          ),
        )}

        {currentPage < totalPages && (
          <Link
            href={hrefFor(currentPage + 1)}
            aria-label="Halaman berikutnya"
            className="inline-flex h-11 min-w-11 items-center justify-center rounded-full border border-zinc-300 px-3 text-sm font-bold text-zinc-700 transition hover:bg-zinc-50"
          >
            →
          </Link>
        )}
      </div>
    </nav>
  );
}
