import type { Metadata } from "next";
import { Suspense } from "react";
import { ProductCard } from "@/components/ProductCard";
import { ProductSearchBar } from "@/components/products/ProductSearchBar";
import { ProductFilterChips } from "@/components/products/ProductFilterChips";
import {
  getProducts,
  getProductsCount,
  type NewProductFilter,
  type PopularFilter,
} from "@/lib/products";
import { prisma } from "@/lib/prisma";
import Link from "next/link";

// Per-user filter state via query params — page tetap dynamic supaya
// filter applied langsung tanpa stale cache.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Katalog Produk",
  description: "Temukan pakan ikan, aksesoris kucing, anjing, burung, kelinci, dan kebutuhan aquarium lengkap dengan harga terjangkau.",
  openGraph: {
    title: "Katalog Produk",
    description: "Semua kebutuhan hewan peliharaan kamu tersedia di sini. Produk original, harga bersaing.",
  },
};

const PAGE_SIZE = 24;

const NEW_FILTERS: NewProductFilter[] = ["today", "this-week", "this-month", "newest"];
const POPULAR_FILTERS: PopularFilter[] = [
  "best-seller",
  "most-searched",
  "highest-rating",
  "most-bought",
];

function asNewFilter(value: string | undefined): NewProductFilter | undefined {
  return value && (NEW_FILTERS as string[]).includes(value)
    ? (value as NewProductFilter)
    : undefined;
}

function asPopularFilter(value: string | undefined): PopularFilter | undefined {
  return value && (POPULAR_FILTERS as string[]).includes(value)
    ? (value as PopularFilter)
    : undefined;
}

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<{
    kategori?: string;
    q?: string;
    page?: string;
    new?: string;
    popular?: string;
  }>;
}) {
  const { kategori, q, page: pageStr, new: newParam, popular: popularParam } =
    await searchParams;
  const page = Math.max(1, parseInt(pageStr ?? "1", 10) || 1);
  const newFilter = asNewFilter(newParam);
  const popularFilter = asPopularFilter(popularParam);

  const [filteredProducts, total, categories] = await Promise.all([
    getProducts({
      category: kategori,
      search: q,
      newFilter,
      popularFilter,
      take: PAGE_SIZE,
      skip: (page - 1) * PAGE_SIZE,
    }),
    getProductsCount({ category: kategori, search: q, newFilter }),
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
  ]);
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="mx-auto max-w-6xl px-4 pb-[calc(6rem+env(safe-area-inset-bottom))] pt-4 md:py-10">
      {/* Page header */}
      <div className="mb-3 md:mb-5">
        <h1 className="text-2xl font-black text-gray-900 md:text-3xl">Katalog Produk</h1>
        <p className="mt-1 text-sm text-gray-500">
          Semua kebutuhan hewan peliharaan kamu tersedia di sini.
        </p>
      </div>

      {/* Compact search bar — no Cari button */}
      <div className="mb-3">
        <Suspense fallback={<div className="h-12 w-full animate-pulse rounded-2xl bg-gray-100" />}>
          <ProductSearchBar defaultValue={q ?? ""} />
        </Suspense>
      </div>

      {/* Filter chips row — Semua + 3 dropdown chips opens top drawer */}
      <div className="mb-4">
        <Suspense fallback={<div className="h-9 w-full animate-pulse rounded-full bg-gray-100" />}>
          <ProductFilterChips
            categories={categories.map((c) => ({ slug: c.slug, name: c.name }))}
            activeCategory={kategori ?? null}
            activeNewFilter={newFilter ?? null}
            activePopularFilter={popularFilter ?? null}
          />
        </Suspense>
      </div>

      {/* Result count */}
      {filteredProducts.length > 0 && (
        <p className="mb-3 text-xs text-gray-500">
          Menampilkan {(page - 1) * PAGE_SIZE + 1}–
          {(page - 1) * PAGE_SIZE + filteredProducts.length} dari {total} produk
        </p>
      )}

      {/* Products grid */}
      {filteredProducts.length > 0 ? (
        <>
          <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4">
            {filteredProducts.map((product, index) => (
              <ProductCard
                key={product.id}
                product={product}
                priority={index < 4}
              />
            ))}
          </div>
          {totalPages > 1 && (
            <Pagination
              page={page}
              totalPages={totalPages}
              kategori={kategori}
              q={q}
              newFilter={newFilter}
              popularFilter={popularFilter}
            />
          )}
        </>
      ) : (
        <div className="rounded-2xl bg-gray-50 p-12 text-center">
          <span className="text-5xl">🐾</span>
          <p className="mt-4 text-gray-500">Belum ada produk yang sesuai dengan filter.</p>
          <Link
            href="/products"
            className="mt-4 inline-flex rounded-full bg-blue-500 px-6 py-3 text-sm font-bold text-white"
          >
            Lihat semua produk
          </Link>
        </div>
      )}
    </div>
  );
}

function Pagination({
  page,
  totalPages,
  kategori,
  q,
  newFilter,
  popularFilter,
}: {
  page: number;
  totalPages: number;
  kategori?: string;
  q?: string;
  newFilter?: NewProductFilter;
  popularFilter?: PopularFilter;
}) {
  function buildHref(p: number) {
    const params = new URLSearchParams();
    if (kategori) params.set("kategori", kategori);
    if (q) params.set("q", q);
    if (newFilter) params.set("new", newFilter);
    if (popularFilter) params.set("popular", popularFilter);
    if (p > 1) params.set("page", String(p));
    const qs = params.toString();
    return `/products${qs ? `?${qs}` : ""}`;
  }

  const visible: Array<number | "..."> = [];
  for (let i = 1; i <= totalPages; i++) {
    if (
      i === 1 ||
      i === totalPages ||
      (i >= page - 1 && i <= page + 1)
    ) {
      visible.push(i);
    } else if (visible[visible.length - 1] !== "...") {
      visible.push("...");
    }
  }

  return (
    <nav className="mt-8 flex flex-wrap items-center justify-center gap-1.5">
      {page > 1 && (
        <Link
          href={buildHref(page - 1)}
          className="rounded-full border border-gray-200 px-4 py-2 text-sm font-medium text-gray-600 hover:border-blue-400"
        >
          ← Prev
        </Link>
      )}
      {visible.map((v, i) =>
        v === "..." ? (
          <span key={`e-${i}`} className="px-2 text-sm text-gray-400">
            …
          </span>
        ) : (
          <Link
            key={v}
            href={buildHref(v)}
            className={`min-w-10 rounded-full px-3 py-2 text-center text-sm font-medium transition ${
              v === page
                ? "bg-blue-500 text-white"
                : "border border-gray-200 text-gray-600 hover:border-blue-400"
            }`}
          >
            {v}
          </Link>
        ),
      )}
      {page < totalPages && (
        <Link
          href={buildHref(page + 1)}
          className="rounded-full border border-gray-200 px-4 py-2 text-sm font-medium text-gray-600 hover:border-blue-400"
        >
          Next →
        </Link>
      )}
    </nav>
  );
}
