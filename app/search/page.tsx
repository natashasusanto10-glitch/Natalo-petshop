"use client";

import { useEffect, useMemo, useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { formatRupiah } from "@/lib/format";
import {
  SearchFilters,
  type Facets,
  type ActiveFilters,
} from "@/components/SearchFilters";
import { BottomSheet } from "@/components/BottomSheet";
import {
  EmptySearch,
  ProductGridSkeleton,
} from "@/components/LoadingEmptyStates";

type SearchResult = {
  items: Array<{
    id: string;
    slug: string;
    name: string;
    image_url: string | null;
    price_min: number;
    price_max: number;
    total_stock: number;
    brand_name: string | null;
    brand_slug: string | null;
    category_name: string | null;
    avg_rating: number;
    review_count: number;
  }>;
  total: number;
  page: number;
  per_page: number;
  took_ms: number;
};

type Sort = "relevance" | "price_asc" | "price_desc" | "newest" | "rating_desc";

const SORT_OPTIONS: { value: Sort; label: string }[] = [
  { value: "relevance", label: "Relevansi" },
  { value: "price_asc", label: "Termurah" },
  { value: "price_desc", label: "Termahal" },
  { value: "newest", label: "Terbaru" },
  { value: "rating_desc", label: "Rating tertinggi" },
];

function SearchPageContent() {
  const router = useRouter();
  const sp = useSearchParams();
  const q = sp.get("q") ?? "";
  const page = Math.max(1, Number(sp.get("page")) || 1);
  const sort = (sp.get("sort") ?? "relevance") as Sort;
  const categorySlugs = sp.getAll("category");
  const brandSlugs = sp.getAll("brand");
  const minPrice = sp.get("min_price") ? Number(sp.get("min_price")) : undefined;
  const maxPrice = sp.get("max_price") ? Number(sp.get("max_price")) : undefined;
  const inStock = sp.get("in_stock") === "true";
  const minRating = sp.get("min_rating") ? Number(sp.get("min_rating")) : undefined;

  const filters: ActiveFilters = useMemo(
    () => ({
      categorySlugs,
      brandSlugs,
      minPrice,
      maxPrice,
      inStock,
      minRating,
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      categorySlugs.join(","),
      brandSlugs.join(","),
      minPrice,
      maxPrice,
      inStock,
      minRating,
    ]
  );

  const [data, setData] = useState<SearchResult | null>(null);
  const [facets, setFacets] = useState<Facets | null>(null);
  const [loading, setLoading] = useState(true);
  const [filterOpen, setFilterOpen] = useState(false);

  // Build query string untuk API
  function buildSearchParams(includePage = true) {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    categorySlugs.forEach((c) => params.append("category", c));
    brandSlugs.forEach((b) => params.append("brand", b));
    if (minPrice !== undefined) params.set("min_price", String(minPrice));
    if (maxPrice !== undefined) params.set("max_price", String(maxPrice));
    if (inStock) params.set("in_stock", "true");
    if (minRating !== undefined) params.set("min_rating", String(minRating));
    params.set("sort", sort);
    if (includePage) {
      params.set("page", String(page));
      params.set("per_page", "24");
    }
    return params;
  }

  // Fetch search + facets parallel
  useEffect(() => {
    setLoading(true);
    const searchParams = buildSearchParams(true);
    const facetsParams = buildSearchParams(false);

    Promise.all([
      fetch(`/api/search?${searchParams}`).then((r) => r.json()),
      fetch(`/api/search/facets?${facetsParams}`).then((r) => r.json()),
    ])
      .then(([searchData, facetsData]) => {
        setData(searchData);
        setFacets(facetsData);
      })
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    q,
    sort,
    page,
    categorySlugs.join(","),
    brandSlugs.join(","),
    minPrice,
    maxPrice,
    inStock,
    minRating,
  ]);

  function applyFilters(next: ActiveFilters) {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    next.categorySlugs.forEach((c) => params.append("category", c));
    next.brandSlugs.forEach((b) => params.append("brand", b));
    if (next.minPrice !== undefined) params.set("min_price", String(next.minPrice));
    if (next.maxPrice !== undefined) params.set("max_price", String(next.maxPrice));
    if (next.inStock) params.set("in_stock", "true");
    if (next.minRating !== undefined) params.set("min_rating", String(next.minRating));
    if (sort !== "relevance") params.set("sort", sort);
    // page reset to 1 saat filter berubah
    router.push(`/search?${params}`);
  }

  function resetFilters() {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    if (sort !== "relevance") params.set("sort", sort);
    router.push(`/search?${params}`);
  }

  function updateParam(key: string, value: string | null) {
    const next = new URLSearchParams(sp);
    if (value === null || value === "") next.delete(key);
    else next.set(key, value);
    if (key !== "page") next.delete("page");
    router.push(`/search?${next}`);
  }

  function removeFilterChip(type: "category" | "brand", value: string) {
    const next = new URLSearchParams(sp);
    const all = next.getAll(type);
    next.delete(type);
    all.filter((v) => v !== value).forEach((v) => next.append(type, v));
    next.delete("page");
    router.push(`/search?${next}`);
  }

  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.per_page)) : 1;
  const hasActiveFilters =
    categorySlugs.length > 0 ||
    brandSlugs.length > 0 ||
    minPrice !== undefined ||
    maxPrice !== undefined ||
    inStock ||
    minRating !== undefined;

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black text-zinc-950">
            {q ? `Hasil pencarian "${q}"` : "Semua produk"}
          </h1>
          {data && !loading && (
            <p className="mt-1 text-sm text-zinc-500">
              {data.total} produk ditemukan · {data.took_ms}ms
            </p>
          )}
        </div>

        {/* Sort */}
        <select
          value={sort}
          onChange={(e) => updateParam("sort", e.target.value)}
          className="rounded-full border border-zinc-300 bg-white px-4 py-2 text-sm font-medium outline-none focus:border-zinc-600"
        >
          {SORT_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              Urut: {opt.label}
            </option>
          ))}
        </select>
      </div>

      {/* Active filter chips */}
      {hasActiveFilters && (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <span className="text-xs text-zinc-400">Filter aktif:</span>
          {categorySlugs.map((slug) => {
            const cat = facets?.categories.find((c) => c.slug === slug);
            return (
              <button
                key={`c-${slug}`}
                onClick={() => removeFilterChip("category", slug)}
                className="flex items-center gap-1 rounded-full bg-natalo-100 px-3 py-1 text-xs font-semibold text-natalo-800 hover:bg-natalo-200"
              >
                🏷️ {cat?.name ?? slug} <span>✕</span>
              </button>
            );
          })}
          {brandSlugs.map((slug) => {
            const br = facets?.brands.find((b) => b.slug === slug);
            return (
              <button
                key={`b-${slug}`}
                onClick={() => removeFilterChip("brand", slug)}
                className="flex items-center gap-1 rounded-full bg-purple-100 px-3 py-1 text-xs font-semibold text-purple-700 hover:bg-purple-200"
              >
                🏭 {br?.name ?? slug} <span>✕</span>
              </button>
            );
          })}
          {(minPrice !== undefined || maxPrice !== undefined) && (
            <button
              onClick={() => {
                const next = new URLSearchParams(sp);
                next.delete("min_price");
                next.delete("max_price");
                next.delete("page");
                router.push(`/search?${next}`);
              }}
              className="flex items-center gap-1 rounded-full bg-green-100 px-3 py-1 text-xs font-semibold text-green-700 hover:bg-green-200"
            >
              💰 {minPrice ? formatRupiah(minPrice) : "0"} -{" "}
              {maxPrice ? formatRupiah(maxPrice) : "∞"} <span>✕</span>
            </button>
          )}
          {inStock && (
            <button
              onClick={() => updateParam("in_stock", null)}
              className="flex items-center gap-1 rounded-full bg-natalo-100 px-3 py-1 text-xs font-semibold text-natalo-700 hover:bg-natalo-200"
            >
              📦 Stok ada <span>✕</span>
            </button>
          )}
          {minRating !== undefined && (
            <button
              onClick={() => updateParam("min_rating", null)}
              className="flex items-center gap-1 rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-200"
            >
              ⭐ Rating {minRating}+ <span>✕</span>
            </button>
          )}
          <button
            onClick={resetFilters}
            className="text-xs font-semibold text-red-500 hover:underline"
          >
            Reset semua
          </button>
        </div>
      )}

      {/* Mobile: tombol Filter */}
      <button
        type="button"
        onClick={() => setFilterOpen(true)}
        className="mt-4 flex items-center gap-2 rounded-full border border-zinc-300 bg-white px-4 py-2 text-sm font-bold text-zinc-700 hover:border-natalo-400 md:hidden"
      >
        ⚙️ Filter
        {hasActiveFilters && (
          <span className="rounded-full bg-natalo-600 px-2 py-0.5 text-[10px] font-bold text-white">
            {categorySlugs.length +
              brandSlugs.length +
              (minPrice !== undefined ? 1 : 0) +
              (maxPrice !== undefined ? 1 : 0) +
              (inStock ? 1 : 0) +
              (minRating !== undefined ? 1 : 0)}
          </span>
        )}
      </button>

      {/* Layout */}
      <div className="mt-6 gap-8 md:grid md:grid-cols-[260px_1fr]">
        {/* Sidebar filter — desktop */}
        <aside className="hidden md:block">
          <div className="sticky top-24 max-h-[calc(100vh-6rem)] overflow-y-auto pr-2">
            <h2 className="mb-4 text-lg font-black text-zinc-950">Filter</h2>
            <SearchFilters
              facets={facets}
              filters={filters}
              onFiltersChange={applyFilters}
              onReset={resetFilters}
            />
          </div>
        </aside>

        {/* Results */}
        <div>
          {loading ? (
            <ProductGridSkeleton n={6} />
          ) : data && data.items.length === 0 ? (
            <div className="rounded-2xl border border-zinc-100 bg-zinc-50">
              <EmptySearch query={q} onReset={resetFilters} />
            </div>
          ) : data ? (
            <>
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {data.items.map((item) => {
                  const isOut = item.total_stock === 0;
                  const priceLabel =
                    item.price_min === item.price_max
                      ? formatRupiah(item.price_min)
                      : `Mulai ${formatRupiah(item.price_min)}`;
                  return (
                    <Link
                      key={item.id}
                      href={`/products/${item.slug}`}
                      className="group overflow-hidden rounded-2xl border border-zinc-100 bg-white shadow-sm transition hover:shadow"
                    >
                      <div className="relative aspect-square bg-zinc-50">
                        {item.image_url ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            src={item.image_url}
                            alt={item.name}
                            className="h-full w-full object-cover transition group-hover:scale-105"
                          />
                        ) : (
                          <div className="flex h-full items-center justify-center text-5xl text-zinc-200">
                            🐾
                          </div>
                        )}
                        {isOut && (
                          <span className="absolute left-3 top-3 rounded-full bg-zinc-700 px-2 py-0.5 text-xs font-bold text-white">
                            Habis
                          </span>
                        )}
                      </div>
                      <div className="p-3">
                        {item.brand_name && (
                          <p className="text-[10px] font-bold uppercase tracking-wider text-purple-500">
                            {item.brand_name}
                          </p>
                        )}
                        <p className="mt-0.5 line-clamp-2 text-sm font-semibold text-zinc-900 group-hover:text-natalo-700">
                          {item.name}
                        </p>
                        <div className="mt-2 flex items-center justify-between">
                          <p className="text-sm font-bold text-natalo-600">
                            {priceLabel}
                          </p>
                          {item.review_count > 0 && (
                            <p className="text-xs text-zinc-500">
                              ⭐ {item.avg_rating.toFixed(1)} ({item.review_count})
                            </p>
                          )}
                        </div>
                      </div>
                    </Link>
                  );
                })}
              </div>

              {/* Pagination */}
              {totalPages > 1 && (
                <div className="mt-8 flex items-center justify-center gap-2">
                  {page > 1 && (
                    <button
                      onClick={() => updateParam("page", String(page - 1))}
                      className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-semibold hover:bg-zinc-50"
                    >
                      ← Sebelumnya
                    </button>
                  )}
                  <span className="px-3 text-sm font-semibold text-zinc-600">
                    Halaman {page} dari {totalPages}
                  </span>
                  {page < totalPages && (
                    <button
                      onClick={() => updateParam("page", String(page + 1))}
                      className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-semibold hover:bg-zinc-50"
                    >
                      Selanjutnya →
                    </button>
                  )}
                </div>
              )}
            </>
          ) : null}
        </div>
      </div>

      {/* Mobile bottom sheet filter */}
      <BottomSheet
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        title="⚙️ Filter Produk"
        footer={
          <button
            type="button"
            onClick={() => setFilterOpen(false)}
            className="w-full rounded-full bg-natalo-600 py-3 text-sm font-bold text-white hover:bg-natalo-700"
          >
            Lihat hasil ({data?.total ?? 0})
          </button>
        }
      >
        <SearchFilters
          facets={facets}
          filters={filters}
          onFiltersChange={applyFilters}
          onReset={resetFilters}
        />
      </BottomSheet>
    </div>
  );
}

export default function SearchPage() {
  return (
    <Suspense
      fallback={
        <div className="mx-auto max-w-6xl px-4 py-8">
          <ProductGridSkeleton n={6} />
        </div>
      }
    >
      <SearchPageContent />
    </Suspense>
  );
}
