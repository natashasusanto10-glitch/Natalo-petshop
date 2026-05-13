"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { StoreProduct } from "@/lib/products";

type UseInfiniteProductsOptions = {
  search?: string;
  category?: string;
  brand?: string;
  newFilter?: string;
  popularFilter?: string;
  limit?: number;
};

type ProductsResponse = {
  items: StoreProduct[];
  nextCursor: string | null;
  hasMore: boolean;
  total: number;
};

export function useInfiniteProducts({
  search = "",
  category = "",
  brand = "",
  newFilter = "",
  popularFilter = "",
  limit = 24,
}: UseInfiniteProductsOptions) {
  const [products, setProducts] = useState<StoreProduct[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const loaderRef = useRef<HTMLDivElement | null>(null);
  const cursorRef = useRef<string | null>(null);
  const hasMoreRef = useRef(true);
  const loadingRef = useRef(false);
  const requestIdRef = useRef(0);

  const loadProducts = useCallback(
    async ({ reset = false } = {}) => {
      if (loadingRef.current && !reset) return;
      if (!hasMoreRef.current && !reset) return;

      const requestId = ++requestIdRef.current;
      loadingRef.current = true;
      setLoading(true);
      setError(null);
      if (reset) setInitialLoading(true);

      try {
        const params = new URLSearchParams();
        params.set("limit", String(limit));

        if (!reset && cursorRef.current) params.set("cursor", cursorRef.current);
        if (search.trim()) params.set("search", search.trim());
        if (category && category !== "all") params.set("category", category);
        if (brand) params.set("brand", brand);
        if (newFilter) params.set("new", newFilter);
        if (popularFilter) params.set("popular", popularFilter);

        const res = await fetch(`/api/products?${params.toString()}`, {
          cache: "no-store",
        });
        if (!res.ok) throw new Error("Gagal mengambil produk");

        const data = (await res.json()) as ProductsResponse;
        if (requestId !== requestIdRef.current) return;

        setProducts((prev) => (reset ? data.items : [...prev, ...data.items]));
        cursorRef.current = data.nextCursor;
        hasMoreRef.current = data.hasMore;
        setCursor(data.nextCursor);
        setHasMore(data.hasMore);
        setTotal(data.total);
      } catch (err) {
        if (requestId === requestIdRef.current) {
          setError(err instanceof Error ? err.message : "Gagal mengambil produk");
        }
      } finally {
        if (requestId === requestIdRef.current) {
          loadingRef.current = false;
          setLoading(false);
          setInitialLoading(false);
        }
      }
    },
    [brand, category, limit, newFilter, popularFilter, search],
  );

  useEffect(() => {
    cursorRef.current = null;
    hasMoreRef.current = true;
    setProducts([]);
    setCursor(null);
    setHasMore(true);
    setTotal(0);
    void loadProducts({ reset: true });
  }, [loadProducts]);

  useEffect(() => {
    const currentLoader = loaderRef.current;
    if (!currentLoader) return;

    const observer = new IntersectionObserver(
      (entries) => {
        const target = entries[0];
        if (target?.isIntersecting && hasMoreRef.current && !loadingRef.current) {
          void loadProducts();
        }
      },
      {
        root: null,
        rootMargin: "320px",
        threshold: 0,
      },
    );

    observer.observe(currentLoader);
    return () => observer.unobserve(currentLoader);
  }, [loadProducts, products.length]);

  return {
    products,
    cursor,
    loading,
    initialLoading,
    hasMore,
    total,
    error,
    loaderRef,
  };
}
