"use client";

/**
 * Target brand picker — pengganti input teks bebas "Target product IDs"
 * untuk kasus umum "berlaku untuk semua produk brand X". Admin pilih dari
 * daftar brand asli (via /api/brands, sudah publik + di-cache), bukan
 * ketik nama/ID manual — menghindari bug voucher tidak pernah match
 * karena nama brand diketik ke field yang sebenarnya butuh ID produk.
 *
 * Submit via hidden input `name="eligibleBrandIds"` comma-separated brand
 * ID — konsisten dengan cara field lain (eligibleProductIds dst) di-parse
 * di server action, jadi tidak perlu ubah parsing di page.tsx.
 */
import { useEffect, useMemo, useState } from "react";

type Brand = { id: string; name: string };

export default function BrandTargetPicker({
  defaultSelectedIds = [],
}: {
  defaultSelectedIds?: string[];
}) {
  const [brands, setBrands] = useState<Brand[]>([]);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<Set<string>>(
    new Set(defaultSelectedIds)
  );

  useEffect(() => {
    let cancelled = false;
    fetch("/api/brands")
      .then((res) => res.json())
      .then((data) => {
        if (cancelled) return;
        setBrands(
          Array.isArray(data?.brands)
            ? data.brands.map((b: { id: string; name: string }) => ({
                id: b.id,
                name: b.name,
              }))
            : []
        );
      })
      .catch(() => {
        if (!cancelled) setBrands([]);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return brands;
    return brands.filter((b) => b.name.toLowerCase().includes(q));
  }, [brands, query]);

  const selectedBrands = useMemo(
    () => brands.filter((b) => selected.has(b.id)),
    [brands, selected]
  );

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">
        Target brand
      </label>
      <input
        type="hidden"
        name="eligibleBrandIds"
        value={[...selected].join(",")}
      />

      {selectedBrands.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {selectedBrands.map((b) => (
            <span
              key={b.id}
              className="flex items-center gap-1.5 rounded-full bg-blue-600 py-1 pl-3 pr-1.5 text-xs font-medium text-white"
            >
              {b.name}
              <button
                type="button"
                onClick={() => toggle(b.id)}
                aria-label={`Hapus ${b.name}`}
                className="rounded-full p-0.5 hover:bg-blue-700"
              >
                &times;
              </button>
            </span>
          ))}
        </div>
      )}

      <input
        type="text"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="Cari brand…"
        className="mt-2 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
      />

      <div className="mt-2 max-h-44 overflow-y-auto rounded-xl border border-zinc-300">
        {loading ? (
          <p className="px-4 py-3 text-xs text-zinc-600">Memuat brand…</p>
        ) : filtered.length === 0 ? (
          <p className="px-4 py-3 text-xs text-zinc-600">
            Brand tidak ditemukan.
          </p>
        ) : (
          filtered.map((b) => {
            const isSelected = selected.has(b.id);
            return (
              <button
                key={b.id}
                type="button"
                onClick={() => toggle(b.id)}
                className={`flex w-full items-center justify-between px-4 py-2.5 text-left text-sm ${
                  isSelected ? "bg-blue-50 text-blue-700" : "text-zinc-700"
                }`}
              >
                {b.name}
                {isSelected && <span className="text-blue-600">✓</span>}
              </button>
            );
          })
        )}
      </div>
      <p className="mt-1 text-xs text-zinc-600">
        Dipetik dari daftar brand di katalog. Kosong = berlaku semua brand.
      </p>
    </div>
  );
}
