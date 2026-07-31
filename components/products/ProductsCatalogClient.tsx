"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { BottomSheet } from "@/components/BottomSheet";
import { ProductCard } from "@/components/ProductCard";
import {
  SearchFilters,
  type ActiveFilters,
  type Facets,
} from "@/components/SearchFilters";
import { ProductsActiveFilterChips } from "@/components/products/ProductsActiveFilterChips";
import { ProductsEmptyState } from "@/components/products/ProductsEmptyState";
import { ProductsGridSkeleton } from "@/components/products/ProductsGridSkeleton";
import { ProductsSortControl } from "@/components/products/ProductsSortControl";
import {
  buildApiSearchParams,
  buildProductsHref,
  parseProductsParams,
  PRODUCTS_PER_PAGE,
  type ProductsCatalogParams,
} from "@/lib/products-search-params";
import { searchDocToStoreProduct } from "@/lib/search-doc-to-product";
import type { ProductSearchDoc } from "@/lib/search";

type SearchResponse = {
  items: ProductSearchDoc[];
  total: number;
  page: number;
  per_page: number;
  facets: Facets | null;
};

const EMPTY_FACETS: Facets = {
  categories: [],
  brands: [],
  price_range: { min: 0, max: 0 },
  weights: [],
};

export function ProductsCatalogClient() {
  const router = useRouter();
  const sp = useSearchParams();
  const params = useMemo(() => parseProductsParams(new URLSearchParams(sp.toString())), [sp]);
  const key = buildApiSearchParams(params).toString();

  const [items, setItems] = useState<ProductSearchDoc[]>([]);
  const [total, setTotal] = useState(0);
  const [facets, setFacets] = useState<Facets | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loadMoreError, setLoadMoreError] = useState<string | null>(null);
  const [loadMoreBlocked, setLoadMoreBlocked] = useState(false);
  const [filterOpen, setFilterOpen] = useState(false);
  const [retryNonce, setRetryNonce] = useState(0);

  // Model paginasi digerakkan RESPONS, bukan items.length: nextPage = halaman
  // berikutnya yang akan diminta, reachedEnd = benar-benar sudah habis menurut
  // server. Ini mencegah loop tak berhenti saat /products?page=3 (items.length
  // start jauh di bawah total) atau dedupe menjatuhkan dokumen duplikat.
  const [nextPage, setNextPage] = useState(params.page + 1);
  const [reachedEnd, setReachedEnd] = useState(false);
  const loaderRef = useRef<HTMLDivElement | null>(null);
  const requestIdRef = useRef(0);
  // Kunci konkuren sinkron: state loadingMore belum ter-update dalam tick
  // yang sama, jadi dua panggilan berbarengan (klik tombol + observer) bisa
  // lolos guard berbasis state dan sama-sama fetch halaman yang sama.
  const loadingMoreRef = useRef(false);

  useEffect(() => {
    const requestId = ++requestIdRef.current;
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    // Reset state paginasi bersamaan dengan mulainya fetch baru, bukan lewat
    // efek terpisah — supaya urutannya selalu konsisten dengan `key`.
    setNextPage(params.page + 1);
    setReachedEnd(false);
    setLoadMoreError(null);
    setLoadMoreBlocked(false);

    fetch(`/api/search?${key}`, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error("Gagal memuat produk");
        return response.json() as Promise<SearchResponse>;
      })
      .then((data) => {
        if (requestId !== requestIdRef.current) return;
        setItems(data.items ?? []);
        setTotal(data.total ?? 0);
        setFacets(data.facets ?? EMPTY_FACETS);
        const totalPages = Math.max(1, Math.ceil((data.total ?? 0) / PRODUCTS_PER_PAGE));
        setReachedEnd((data.items ?? []).length < PRODUCTS_PER_PAGE || params.page >= totalPages);
      })
      .catch((cause) => {
        if (cause instanceof Error && cause.name === "AbortError") return;
        if (requestId !== requestIdRef.current) return;
        setError("Gagal memuat produk");
      })
      .finally(() => {
        if (!controller.signal.aborted && requestId === requestIdRef.current) setLoading(false);
      });

    return () => controller.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, retryNonce]);

  const loadedCount = items.length;
  const hasMore = !reachedEnd;

  const loadMore = useCallback(async () => {
    if (loadingMore || loading || reachedEnd || loadMoreBlocked || loadingMoreRef.current) return;
    loadingMoreRef.current = true;
    const totalPages = Math.max(1, Math.ceil(total / PRODUCTS_PER_PAGE));
    if (nextPage > totalPages) {
      setReachedEnd(true);
      loadingMoreRef.current = false;
      return;
    }
    setLoadingMore(true);
    setLoadMoreError(null);
    setLoadMoreBlocked(false);
    // Tangkap requestId SEBELUM fetch: kalau filter/sort berubah selagi
    // permintaan ini masih berjalan, requestIdRef.current akan berbeda saat
    // respons datang, dan SEMUA penulisan state di bawah dibatalkan supaya
    // produk dari filter lama tidak menempel ke hasil filter baru.
    const requestId = requestIdRef.current;
    const nextKey = buildApiSearchParams({ ...params, page: nextPage }).toString();
    try {
      const response = await fetch(`/api/search?${nextKey}`);
      if (!response.ok) throw new Error("Gagal memuat produk");
      const data = (await response.json()) as SearchResponse;
      if (requestId !== requestIdRef.current) return;
      setItems((prev) => {
        const seen = new Set(prev.map((item) => item.id));
        return [...prev, ...(data.items ?? []).filter((item) => !seen.has(item.id))];
      });
      setNextPage((value) => value + 1);
      if ((data.items ?? []).length < PRODUCTS_PER_PAGE || nextPage >= totalPages) {
        setReachedEnd(true);
      }
    } catch {
      if (requestId !== requestIdRef.current) return;
      setLoadMoreError("Gagal memuat produk tambahan");
      setLoadMoreBlocked(true);
    } finally {
      // Ref dilepas tanpa syarat: permintaan basi pun wajib melepas kunci,
      // supaya konkurensi tidak nyangkut selamanya.
      loadingMoreRef.current = false;
      if (requestId === requestIdRef.current) setLoadingMore(false);
    }
  }, [loading, loadingMore, loadMoreBlocked, nextPage, params, reachedEnd, total]);

  useEffect(() => {
    const node = loaderRef.current;
    if (!node || !hasMore || loadMoreBlocked) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) void loadMore();
      },
      { rootMargin: "320px" },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [hasMore, loadMore, loadMoreBlocked]);

  function apply(next: ProductsCatalogParams) {
    router.replace(buildProductsHref({ ...next, page: 1 }), { scroll: false });
  }

  function reset() {
    router.replace(
      buildProductsHref({
        ...params,
        categorySlugs: [],
        brandSlugs: [],
        minPrice: undefined,
        maxPrice: undefined,
        inStock: false,
        minRating: undefined,
        discountOnly: false,
        page: 1,
      }),
      { scroll: false },
    );
  }

  const filters: ActiveFilters = {
    categorySlugs: params.categorySlugs,
    brandSlugs: params.brandSlugs,
    minPrice: params.minPrice,
    maxPrice: params.maxPrice,
    inStock: params.inStock,
    minRating: params.minRating,
  };

  function onFiltersChange(next: ActiveFilters) {
    apply({
      ...params,
      // Kategori di /products single-select walau backend dukung multi.
      categorySlugs: next.categorySlugs.slice(-1),
      brandSlugs: next.brandSlugs,
      minPrice: next.minPrice,
      maxPrice: next.maxPrice,
      inStock: next.inStock,
      minRating: next.minRating,
    });
  }

  const discountToggle = (
    <label className="mt-4 flex cursor-pointer items-center gap-2 rounded-lg px-2 py-1.5 text-sm hover:bg-natalo-50">
      <input
        type="checkbox"
        checked={params.discountOnly}
        onChange={(event) => apply({ ...params, discountOnly: event.target.checked })}
        className="h-4 w-4 accent-natalo-600"
      />
      <span className="text-zinc-700">Sedang diskon</span>
    </label>
  );

  const filtersPanel = (
    <>
      <SearchFilters
        facets={facets}
        filters={filters}
        onFiltersChange={onFiltersChange}
        onReset={reset}
      />
      {discountToggle}
    </>
  );

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-gray-500">
          {loading ? (
            "Memuat produk..."
          ) : (
            <>
              Menampilkan <span className="font-black text-natalo-700">{loadedCount}</span> dari{" "}
              <span className="font-black text-natalo-700">{total}</span> produk
            </>
          )}
        </p>
        <div className="flex items-center gap-2">
          <ProductsSortControl
            sort={params.sort}
            onSortChange={(next) => apply({ ...params, sort: next })}
          />
          <button
            type="button"
            onClick={() => setFilterOpen(true)}
            className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 active:bg-gray-50 md:hidden"
          >
            Filter
          </button>
        </div>
      </div>

      <ProductsActiveFilterChips
        params={params}
        facets={facets}
        onChange={apply}
        onReset={reset}
      />

      <div className="mt-4 gap-6 md:grid md:grid-cols-[248px_1fr]">
        <aside className="hidden md:block">
          <div className="sticky top-24 max-h-[calc(100vh-6rem)] overflow-y-auto rounded-2xl border border-gray-100 bg-white p-4">
            <h2 className="mb-4 text-sm font-black text-gray-950">Filter</h2>
            {filtersPanel}
          </div>
        </aside>

        <section className="min-w-0">
          {loading ? (
            <ProductsGridSkeleton />
          ) : error ? (
            <div className="rounded-2xl border border-red-100 bg-red-50 p-8 text-center">
              <p className="text-sm font-bold text-red-600">Gagal memuat produk</p>
              <button
                type="button"
                onClick={() => setRetryNonce((value) => value + 1)}
                className="mt-3 rounded-full bg-red-600 px-4 py-2 text-xs font-black text-white"
              >
                Coba lagi
              </button>
            </div>
          ) : items.length === 0 ? (
            <ProductsEmptyState
              hasActiveFilters={
                params.categorySlugs.length > 0 ||
                params.brandSlugs.length > 0 ||
                params.inStock ||
                params.discountOnly ||
                params.minRating !== undefined ||
                params.minPrice !== undefined ||
                params.maxPrice !== undefined
              }
              onReset={reset}
            />
          ) : (
            <>
              <div className="nat-content-fade-in grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:grid-cols-4">
                {items.map((doc, index) => (
                  <ProductCard
                    key={doc.id}
                    product={searchDocToStoreProduct(doc)}
                    priority={index < 4}
                    showRating
                  />
                ))}
              </div>

              <div ref={loaderRef} className="h-10" aria-hidden="true" />

              {hasMore && (
                <div className="flex flex-col items-center gap-2 py-6">
                  {loadMoreError && (
                    <div className="flex items-center gap-2 text-xs font-semibold text-red-600">
                      <span>{loadMoreError}</span>
                      <button
                        type="button"
                        onClick={() => {
                          // Cukup lepas blokir + error: observer akan menembak
                          // ulang secara alami karena sentinel masih terlihat,
                          // menghindari closure loadMore yang masih membaca
                          // loadMoreBlocked lama kalau dipanggil langsung di sini.
                          setLoadMoreError(null);
                          setLoadMoreBlocked(false);
                        }}
                        className="rounded-full border border-red-200 bg-white px-3 py-1 font-black text-red-600"
                      >
                        Coba lagi
                      </button>
                    </div>
                  )}
                  <button
                    type="button"
                    onClick={() => void loadMore()}
                    disabled={loadingMore || loadMoreBlocked}
                    className="rounded-full border border-natalo-200 bg-white px-6 py-2.5 text-sm font-bold text-natalo-700 transition hover:bg-natalo-50 disabled:opacity-60"
                  >
                    {loadingMore ? "Memuat produk..." : "Muat lebih banyak"}
                  </button>
                </div>
              )}

              {!hasMore && params.page > 1 && (
                <p className="py-6 text-center text-sm font-semibold text-gray-500">
                  Menampilkan sebagian katalog mulai halaman {params.page}.{" "}
                  <Link href="/products" className="font-bold text-natalo-700 underline">
                    Lihat dari awal
                  </Link>
                </p>
              )}

              {!hasMore && params.page <= 1 && (
                <p className="py-6 text-center text-sm font-semibold text-gray-400">
                  Semua produk sudah ditampilkan.
                </p>
              )}
            </>
          )}
        </section>
      </div>

      <BottomSheet
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        title="Filter Produk"
        footer={
          <button
            type="button"
            onClick={() => setFilterOpen(false)}
            className="h-11 w-full rounded-full bg-natalo-600 text-sm font-black text-white active:bg-natalo-700"
          >
            {loading ? "Menampilkan hasil..." : `Tampilkan ${total} produk`}
          </button>
        }
      >
        {filtersPanel}
      </BottomSheet>
    </>
  );
}
