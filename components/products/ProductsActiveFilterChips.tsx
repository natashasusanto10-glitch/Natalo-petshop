"use client";

import { FilterChip } from "@/components/products/FilterChip";
import { formatRupiah } from "@/lib/format";
import type { Facets } from "@/components/SearchFilters";
import type { ProductsCatalogParams } from "@/lib/products-search-params";

/**
 * Baris chip filter aktif. Nilainya polos ("Whiskas", bukan "Brand: Whiskas")
 * mengikuti aturan badge di spec — jangan ulang nama dimensinya.
 */

// Chip dirender dari params URL sebelum facets datang dari API, jadi nama
// slug mentah bisa sempat tampil; rapikan sebagai cadangan sampai facets siap.
function prettifySlug(slug: string): string {
  return slug
    .split(/[-_]+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}
export function ProductsActiveFilterChips({
  params,
  facets,
  onChange,
  onReset,
}: {
  params: ProductsCatalogParams;
  facets: Facets | null;
  onChange: (next: ProductsCatalogParams) => void;
  onReset: () => void;
}) {
  const hasPrice = params.minPrice !== undefined || params.maxPrice !== undefined;
  const hasAny =
    params.categorySlugs.length > 0 ||
    params.brandSlugs.length > 0 ||
    hasPrice ||
    params.inStock ||
    params.minRating !== undefined ||
    params.discountOnly;

  if (!hasAny) return null;

  return (
    <div className="mt-3 flex flex-wrap items-center gap-2">
      {params.categorySlugs.map((slug) => (
        <FilterChip
          key={`category-${slug}`}
          label={
            facets?.categories.find((c) => c.slug === slug)?.name ?? prettifySlug(slug)
          }
          onRemove={() =>
            onChange({
              ...params,
              categorySlugs: params.categorySlugs.filter((value) => value !== slug),
              page: 1,
            })
          }
        />
      ))}
      {params.brandSlugs.map((slug) => (
        <FilterChip
          key={`brand-${slug}`}
          label={facets?.brands.find((b) => b.slug === slug)?.name ?? prettifySlug(slug)}
          onRemove={() =>
            onChange({
              ...params,
              brandSlugs: params.brandSlugs.filter((value) => value !== slug),
              page: 1,
            })
          }
        />
      ))}
      {hasPrice && (
        <FilterChip
          label={`${params.minPrice ? formatRupiah(params.minPrice) : "Rp0"} - ${
            params.maxPrice ? formatRupiah(params.maxPrice) : "Maks"
          }`}
          onRemove={() =>
            onChange({ ...params, minPrice: undefined, maxPrice: undefined, page: 1 })
          }
        />
      )}
      {params.inStock && (
        <FilterChip
          label="Stok tersedia"
          onRemove={() => onChange({ ...params, inStock: false, page: 1 })}
        />
      )}
      {params.minRating !== undefined && (
        <FilterChip
          label={`Rating ${params.minRating}+`}
          onRemove={() => onChange({ ...params, minRating: undefined, page: 1 })}
        />
      )}
      {params.discountOnly && (
        <FilterChip
          label="Sedang diskon"
          onRemove={() => onChange({ ...params, discountOnly: false, page: 1 })}
        />
      )}
      <button
        type="button"
        onClick={onReset}
        className="h-7 rounded-full px-2 text-xs font-extrabold text-natalo-600 active:bg-natalo-50"
      >
        Hapus semua
      </button>
    </div>
  );
}
