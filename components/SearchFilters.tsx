"use client";

import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";

export type Facets = {
  categories: Array<{ slug: string; name: string; count: number }>;
  brands: Array<{ slug: string; name: string; count: number }>;
  price_range: { min: number; max: number };
  weights: Array<{ label: string; min: number; max: number; count: number }>;
};

export type ActiveFilters = {
  categorySlugs: string[];
  brandSlugs: string[];
  minPrice?: number;
  maxPrice?: number;
  inStock: boolean;
  minRating?: number;
};

interface Props {
  facets: Facets | null;
  filters: ActiveFilters;
  onFiltersChange: (next: ActiveFilters) => void;
  onReset: () => void;
}

export function SearchFilters({ facets, filters, onFiltersChange, onReset }: Props) {
  // Local state untuk price input (debounce-friendly)
  const [minPriceInput, setMinPriceInput] = useState(
    filters.minPrice?.toString() ?? ""
  );
  const [maxPriceInput, setMaxPriceInput] = useState(
    filters.maxPrice?.toString() ?? ""
  );

  useEffect(() => {
    setMinPriceInput(filters.minPrice?.toString() ?? "");
    setMaxPriceInput(filters.maxPrice?.toString() ?? "");
  }, [filters.minPrice, filters.maxPrice]);

  // Sync ke parent saat input idle 600ms
  useEffect(() => {
    const t = setTimeout(() => {
      const newMin = minPriceInput ? Number(minPriceInput) : undefined;
      const newMax = maxPriceInput ? Number(maxPriceInput) : undefined;
      if (newMin !== filters.minPrice || newMax !== filters.maxPrice) {
        onFiltersChange({ ...filters, minPrice: newMin, maxPrice: newMax });
      }
    }, 600);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [minPriceInput, maxPriceInput]);

  function toggleCategory(slug: string) {
    const exists = filters.categorySlugs.includes(slug);
    onFiltersChange({
      ...filters,
      categorySlugs: exists
        ? filters.categorySlugs.filter((s) => s !== slug)
        : [...filters.categorySlugs, slug],
    });
  }

  function toggleBrand(slug: string) {
    const exists = filters.brandSlugs.includes(slug);
    onFiltersChange({
      ...filters,
      brandSlugs: exists
        ? filters.brandSlugs.filter((s) => s !== slug)
        : [...filters.brandSlugs, slug],
    });
  }

  return (
    <div className="space-y-6">
      {/* Kategori */}
      <FilterSection title="Kategori">
        {facets?.categories.length ? (
          <div className="space-y-1.5">
            {facets.categories.slice(0, 10).map((c) => {
              const checked = filters.categorySlugs.includes(c.slug);
              const disabled = c.count === 0 && !checked;
              return (
                <label
                  key={c.slug}
                  className={`flex items-center justify-between gap-2 rounded-lg px-2 py-1.5 text-sm transition ${
                    disabled
                      ? "opacity-40 cursor-not-allowed"
                      : "cursor-pointer hover:bg-natalo-50"
                  }`}
                >
                  <div className="flex min-w-0 items-center gap-2">
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={disabled}
                      onChange={() => toggleCategory(c.slug)}
                      className="h-4 w-4 accent-natalo-600"
                    />
                    <span className="truncate text-zinc-700">{c.name}</span>
                  </div>
                  <span className="shrink-0 text-xs text-zinc-400">{c.count}</span>
                </label>
              );
            })}
          </div>
        ) : (
          <p className="text-xs text-zinc-400">—</p>
        )}
      </FilterSection>

      {/* Brand */}
      <FilterSection title="Brand">
        {facets?.brands.length ? (
          <div className="max-h-72 space-y-1.5 overflow-y-auto pr-1">
            {facets.brands.slice(0, 30).map((b) => {
              const checked = filters.brandSlugs.includes(b.slug);
              const disabled = b.count === 0 && !checked;
              return (
                <label
                  key={b.slug}
                  className={`flex items-center justify-between gap-2 rounded-lg px-2 py-1.5 text-sm transition ${
                    disabled
                      ? "opacity-40 cursor-not-allowed"
                      : "cursor-pointer hover:bg-natalo-50"
                  }`}
                >
                  <div className="flex min-w-0 items-center gap-2">
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={disabled}
                      onChange={() => toggleBrand(b.slug)}
                      className="h-4 w-4 accent-natalo-600"
                    />
                    <span className="truncate text-zinc-700">{b.name}</span>
                  </div>
                  <span className="shrink-0 text-xs text-zinc-400">{b.count}</span>
                </label>
              );
            })}
          </div>
        ) : (
          <p className="text-xs text-zinc-400">—</p>
        )}
      </FilterSection>

      {/* Harga */}
      <FilterSection title="Harga">
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <input
              type="number"
              value={minPriceInput}
              onChange={(e) => setMinPriceInput(e.target.value)}
              placeholder="Min"
              min={0}
              className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-xs outline-none focus:border-zinc-600"
            />
            <span className="text-xs text-zinc-400">—</span>
            <input
              type="number"
              value={maxPriceInput}
              onChange={(e) => setMaxPriceInput(e.target.value)}
              placeholder="Max"
              min={0}
              className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-xs outline-none focus:border-zinc-600"
            />
          </div>
          {facets?.price_range && (
            <p className="text-[10px] text-zinc-400">
              Range: {formatRupiah(facets.price_range.min)} —{" "}
              {formatRupiah(facets.price_range.max)}
            </p>
          )}
        </div>
      </FilterSection>

      {/* Lainnya */}
      <FilterSection title="Lainnya">
        <div className="space-y-1.5">
          <label className="flex cursor-pointer items-center gap-2 rounded-lg px-2 py-1.5 text-sm hover:bg-natalo-50">
            <input
              type="checkbox"
              checked={filters.inStock}
              onChange={(e) =>
                onFiltersChange({ ...filters, inStock: e.target.checked })
              }
              className="h-4 w-4 accent-natalo-600"
            />
            <span className="text-zinc-700">Stok tersedia</span>
          </label>
          <label className="flex cursor-pointer items-center gap-2 rounded-lg px-2 py-1.5 text-sm hover:bg-natalo-50">
            <input
              type="checkbox"
              checked={filters.minRating === 4}
              onChange={(e) =>
                onFiltersChange({
                  ...filters,
                  minRating: e.target.checked ? 4 : undefined,
                })
              }
              className="h-4 w-4 accent-natalo-600"
            />
            <span className="text-zinc-700">⭐ Rating 4+</span>
          </label>
        </div>
      </FilterSection>

      {/* Reset */}
      <button
        type="button"
        onClick={onReset}
        className="w-full rounded-full border border-zinc-300 py-2 text-sm font-bold text-zinc-700 hover:bg-zinc-50"
      >
        ✕ Reset semua filter
      </button>
    </div>
  );
}

function FilterSection({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <h3 className="mb-2 text-xs font-bold uppercase tracking-wider text-zinc-500">
        {title}
      </h3>
      {children}
    </div>
  );
}
