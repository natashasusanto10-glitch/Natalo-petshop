"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { StoreProduct } from "@/lib/products";
import { HomeProductCard, HomeProductSkeleton } from "@/components/home/HomeProductCard";

const NEXT_PAGE_SIZE = 10;

type ProductsResponse = {
  items: StoreProduct[];
  nextCursor: string | null;
  hasMore: boolean;
  total: number;
};

type HomeExploreProductsProps = {
  initialProducts: StoreProduct[];
  initialCursor: string | null;
  initialHasMore: boolean;
  excludeIds?: string[];
};

export function HomeExploreProducts({
  initialProducts,
  initialCursor,
  initialHasMore,
  excludeIds = [],
}: HomeExploreProductsProps) {
  const [products, setProducts] = useState(initialProducts);
  const [cursor, setCursor] = useState(initialCursor);
  const [hasMore, setHasMore] = useState(initialHasMore);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const loaderRef = useRef<HTMLDivElement | null>(null);
  const loadingRef = useRef(false);
  const hasMoreRef = useRef(initialHasMore);
  const cursorRef = useRef(initialCursor);

  useEffect(() => {
    hasMoreRef.current = hasMore;
    cursorRef.current = cursor;
  }, [cursor, hasMore]);

  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMoreRef.current) return;

    loadingRef.current = true;
    setLoading(true);
    setError(null);

    try {
      const params = new URLSearchParams({
        limit: String(NEXT_PAGE_SIZE),
        inStock: "1",
        withImage: "1",
        hasPrice: "1",
      });
      if (cursorRef.current) params.set("cursor", cursorRef.current);
      if (excludeIds.length > 0) params.set("exclude", excludeIds.join(","));

      const response = await fetch(`/api/products?${params.toString()}`, {
        cache: "no-store",
      });
      if (!response.ok) throw new Error("Gagal memuat produk");

      const data = (await response.json()) as ProductsResponse;
      setProducts((current) => {
        const knownIds = new Set(current.map((product) => product.id));
        const freshItems = data.items.filter((product) => !knownIds.has(product.id));
        return [...current, ...freshItems];
      });
      setCursor(data.nextCursor);
      setHasMore(data.hasMore);
      cursorRef.current = data.nextCursor;
      hasMoreRef.current = data.hasMore;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat produk");
    } finally {
      loadingRef.current = false;
      setLoading(false);
    }
  }, [excludeIds]);

  useEffect(() => {
    const currentLoader = loaderRef.current;
    if (!currentLoader) return;

    const observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        if (entry?.isIntersecting) void loadMore();
      },
      { root: null, rootMargin: "420px", threshold: 0 },
    );

    observer.observe(currentLoader);
    return () => observer.unobserve(currentLoader);
  }, [loadMore]);

  if (products.length === 0 && !loading) {
    return (
      <div className="rounded-[18px] border border-dashed border-zinc-200 bg-white px-6 py-10 text-center">
        <h3 className="text-base font-black text-zinc-900">Produk belum tersedia</h3>
        <p className="mt-1 text-sm font-medium text-zinc-500">
          Coba cek kembali nanti atau pilih kategori lainnya.
        </p>
      </div>
    );
  }

  return (
    <>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {products.map((product, index) => (
          <HomeProductCard
            key={product.id}
            product={product}
            badge={product.discountPrice && product.discountPrice < product.price ? "Promo" : undefined}
            priority={index < 4}
          />
        ))}
      </div>

      <div ref={loaderRef} className="h-8" aria-hidden="true" />

      {loading && <HomeProductSkeleton count={4} />}

      {error && (
        <p className="py-4 text-center text-sm font-semibold text-red-500">{error}</p>
      )}

      {!loading && !hasMore && products.length > 0 && (
        <p className="py-6 text-center text-sm font-bold text-zinc-400">
          Semua produk sudah ditampilkan
        </p>
      )}
    </>
  );
}
