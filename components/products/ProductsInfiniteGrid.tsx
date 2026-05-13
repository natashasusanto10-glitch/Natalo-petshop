"use client";

import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { ProductCard } from "@/components/ProductCard";
import { useInfiniteProducts } from "@/hooks/useInfiniteProducts";

const PAGE_SIZE = 24;

function ProductGridSkeleton() {
  return (
    <div className="grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:grid-cols-4">
      {[...Array(8)].map((_, i) => (
        <div key={i} className="overflow-hidden rounded-2xl border border-gray-100 bg-white">
          <div className="aspect-square animate-pulse bg-gray-100" />
          <div className="space-y-2 p-3 md:p-4">
            <div className="h-4 w-3/4 animate-pulse rounded-lg bg-gray-100" />
            <div className="mt-3 h-5 w-1/3 animate-pulse rounded-lg bg-gray-100" />
            <div className="h-8 w-full animate-pulse rounded-full bg-gray-100" />
          </div>
        </div>
      ))}
    </div>
  );
}

export function ProductsInfiniteGrid() {
  const searchParams = useSearchParams();
  const search = searchParams.get("q") ?? "";
  const category = searchParams.get("kategori") ?? searchParams.get("category") ?? "";
  const brand = searchParams.get("brand") ?? "";
  const newFilter = searchParams.get("new") ?? "";
  const popularFilter = searchParams.get("popular") ?? "";
  const { products, loading, initialLoading, hasMore, total, error, loaderRef } =
    useInfiniteProducts({
      search,
      category,
      brand,
      newFilter,
      popularFilter,
      limit: PAGE_SIZE,
    });

  if (initialLoading) {
    return (
      <>
        <div className="mb-3 h-3 w-40 animate-pulse rounded bg-gray-100" />
        <ProductGridSkeleton />
      </>
    );
  }

  if (error) {
    return (
      <div className="rounded-2xl bg-red-50 p-8 text-center">
        <p className="text-sm font-semibold text-red-600">{error}</p>
      </div>
    );
  }

  if (products.length === 0) {
    return (
      <div className="rounded-2xl bg-gray-50 p-12 text-center">
        <span className="text-5xl">🐾</span>
        <p className="mt-4 text-gray-500">Produk tidak ditemukan.</p>
        <Link
          href="/products"
          className="mt-4 inline-flex rounded-full bg-blue-500 px-6 py-3 text-sm font-bold text-white transition-transform duration-100 active:scale-95"
        >
          Lihat semua produk
        </Link>
      </div>
    );
  }

  return (
    <>
      <p className="mb-3 text-xs text-gray-500">
        Menampilkan {products.length} dari {total} produk
      </p>
      <div className="nat-content-fade-in nat-content-fade-in--stagger grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:grid-cols-4">
        {products.map((product, index) => (
          <ProductCard key={product.id} product={product} priority={index < 4} />
        ))}
      </div>

      <div ref={loaderRef} className="h-10" aria-hidden="true" />

      {loading && (
        <p className="py-6 text-center text-sm font-semibold text-gray-500">
          Memuat produk...
        </p>
      )}

      {!loading && !hasMore && (
        <p className="py-6 text-center text-sm font-semibold text-gray-400">
          Semua produk sudah ditampilkan.
        </p>
      )}
    </>
  );
}
