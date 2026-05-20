"use client";

import { useMemo, useState } from "react";
import Link from "next/link";

interface EligibleProduct {
  id: string;
  name: string;
  price: number;
  imageUrl: string | null;
  slug: string;
}

interface Props {
  products: EligibleProduct[];
  /** Server action passed dari page.tsx (server component). */
  action: (formData: FormData) => void;
}

/**
 * Client form untuk Buat Flash Sale — search + multi-select produk.
 *
 * Search filter di client side (no API call) — semua produk eligible
 * sudah di-load dari server. Cukup untuk N ≤ 500 produk. Kalau lebih,
 * upgrade ke server-side search via /api endpoint.
 */
export function FlashSaleNewForm({ products, action }: Props) {
  const [search, setSearch] = useState("");
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Filter produk by search query (case-insensitive, contains match)
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return products;
    return products.filter((p) => p.name.toLowerCase().includes(q));
  }, [search, products]);

  function toggle(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleAll() {
    if (filtered.every((p) => selectedIds.has(p.id))) {
      // Semua filtered terpilih → deselect filtered.
      setSelectedIds((prev) => {
        const next = new Set(prev);
        filtered.forEach((p) => next.delete(p.id));
        return next;
      });
    } else {
      // Pilih semua filtered (preserve selections di luar filter).
      setSelectedIds((prev) => {
        const next = new Set(prev);
        filtered.forEach((p) => next.add(p.id));
        return next;
      });
    }
  }

  const allFilteredSelected =
    filtered.length > 0 && filtered.every((p) => selectedIds.has(p.id));

  return (
    <div className="mx-auto max-w-4xl px-4 py-5 md:px-8 md:py-10">
      <Link
        href="/admin/diskon"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke Buat Diskon
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
        Buat Flash Sale
      </h1>
      <p className="mt-1 text-sm text-zinc-500">
        Pilih produk + diskon + waktu berakhir. Produk akan tampil di
        Flash Sale section dengan countdown timer.
      </p>

      <form action={action} className="mt-6 space-y-5">
        {/* Periode + Diskon */}
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-sm font-semibold text-zinc-700">
              <span className="mr-1 text-red-500">•</span>Diskon (%)
            </label>
            <input
              type="number"
              name="discountPercent"
              min={1}
              max={95}
              required
              placeholder="20"
              className="mt-1.5 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-600"
            />
            <p className="mt-1 text-xs text-zinc-500">
              ⓘ Antara 1–95%. Diterapkan ke semua produk yang dipilih.
            </p>
          </div>
          <div>
            <label className="block text-sm font-semibold text-zinc-700">
              <span className="mr-1 text-red-500">•</span>Berakhir
            </label>
            <input
              type="datetime-local"
              name="endsAt"
              required
              className="mt-1.5 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-600"
            />
            <p className="mt-1 text-xs text-zinc-500">
              ⓘ Harus waktu di masa depan. Promosi otomatis berakhir.
            </p>
          </div>
        </div>

        {/* Pilih produk (search + multi-checklist) */}
        <div>
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <label className="block text-sm font-semibold text-zinc-700">
              <span className="mr-1 text-red-500">•</span>Pilih Produk
            </label>
            <span className="text-xs font-semibold text-zinc-500">
              {selectedIds.size} dipilih
              {search && ` • ${filtered.length} cocok dari ${products.length}`}
              {!search && ` dari ${products.length}`}
            </span>
          </div>
          <p className="mt-0.5 text-xs text-zinc-500">
            Hanya produk yang sedang tidak di Flash Sale yang muncul di
            sini.
          </p>

          {/* Search bar + bulk toggle */}
          <div className="mt-2 flex gap-2">
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="🔍 Cari nama produk..."
              className="flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
            />
            <button
              type="button"
              onClick={toggleAll}
              disabled={filtered.length === 0}
              className="rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm font-bold text-zinc-700 hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {allFilteredSelected ? "Batalkan Semua" : "Pilih Semua"}
            </button>
          </div>

          {/* Hidden inputs untuk submit — pakai selectedIds (Set), bukan
              checkbox state HTML (filter UI bisa hide checkbox tapi
              tetap include yang sudah dipilih sebelumnya). */}
          {Array.from(selectedIds).map((id) => (
            <input key={id} type="hidden" name="productIds" value={id} />
          ))}

          {/* Product list */}
          <div className="mt-3 max-h-96 overflow-y-auto rounded-xl border border-zinc-200 bg-white">
            {products.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-zinc-400">
                Semua produk sedang di Flash Sale atau tidak ada produk
                aktif. Tunggu Flash Sale berakhir dulu.
              </p>
            ) : filtered.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-zinc-400">
                Tidak ada produk cocok dengan pencarian{" "}
                <strong>&quot;{search}&quot;</strong>. Coba kata kunci lain.
              </p>
            ) : (
              <div className="divide-y divide-zinc-100">
                {filtered.map((p) => (
                  <label
                    key={p.id}
                    className="flex cursor-pointer items-center gap-3 px-4 py-2.5 hover:bg-zinc-50"
                  >
                    <input
                      type="checkbox"
                      checked={selectedIds.has(p.id)}
                      onChange={() => toggle(p.id)}
                      className="h-4 w-4 rounded border-zinc-300"
                    />
                    {p.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={p.imageUrl}
                        alt=""
                        className="h-10 w-10 rounded border border-zinc-200 object-cover"
                      />
                    ) : (
                      <div className="h-10 w-10 rounded border border-zinc-200 bg-zinc-100" />
                    )}
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold text-zinc-900">
                        {p.name}
                      </p>
                      <p className="text-xs text-zinc-500">
                        Rp {p.price.toLocaleString("id-ID")}
                      </p>
                    </div>
                  </label>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Submit */}
        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Link
            href="/admin/diskon"
            className="rounded-full border border-zinc-300 px-6 py-3 text-center text-sm font-bold"
          >
            Batal
          </Link>
          <button
            type="submit"
            disabled={selectedIds.size === 0}
            className="flex-1 rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-50 sm:flex-none"
          >
            Simpan Flash Sale ({selectedIds.size})
          </button>
        </div>
      </form>
    </div>
  );
}
