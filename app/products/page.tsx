import type { Metadata } from "next";
import { Suspense } from "react";
import { ProductSearchBar } from "@/components/products/ProductSearchBar";
import { ProductFilterChips } from "@/components/products/ProductFilterChips";
import { ProductsInfiniteGrid } from "@/components/products/ProductsInfiniteGrid";
import type { NewProductFilter, PopularFilter } from "@/lib/products";
import { prisma } from "@/lib/prisma";

// Per-user filter state via query params. Page stays dynamic so search/filter
// state is reflected immediately while the product grid loads client-side.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Katalog Produk",
  description:
    "Temukan pakan ikan, aksesoris kucing, anjing, burung, kelinci, dan kebutuhan aquarium lengkap dengan harga terjangkau.",
  openGraph: {
    title: "Katalog Produk",
    description:
      "Semua kebutuhan hewan peliharaan kamu tersedia di sini. Produk original, harga bersaing.",
  },
};

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
    new?: string;
    popular?: string;
  }>;
}) {
  const { kategori, q, new: newParam, popular: popularParam } = await searchParams;
  const newFilter = asNewFilter(newParam);
  const popularFilter = asPopularFilter(popularParam);

  const categories = await prisma.category
    .findMany({ orderBy: { name: "asc" } })
    .catch(() => []);

  return (
    <div className="mx-auto max-w-6xl px-4 pb-[calc(6rem+env(safe-area-inset-bottom))] pt-4 md:py-10">
      <div className="mb-3 md:mb-5">
        <h1 className="text-2xl font-black text-gray-900 md:text-3xl">Katalog Produk</h1>
        <p className="mt-1 text-sm text-gray-500">
          Semua kebutuhan hewan peliharaan kamu tersedia di sini.
        </p>
      </div>

      <div className="sticky top-[calc(96px+env(safe-area-inset-top))] z-20 -mx-4 mb-4 bg-white/95 px-4 pb-3 pt-2 backdrop-blur md:static md:mx-0 md:bg-transparent md:px-0 md:pb-0 md:pt-0 md:backdrop-blur-none">
        <div className="mb-3">
          <Suspense fallback={<div className="h-12 w-full animate-pulse rounded-2xl bg-gray-100" />}>
            <ProductSearchBar defaultValue={q ?? ""} />
          </Suspense>
        </div>

        <Suspense fallback={<div className="h-9 w-full animate-pulse rounded-full bg-gray-100" />}>
          <ProductFilterChips
            categories={categories.map((c) => ({ slug: c.slug, name: c.name }))}
            activeCategory={kategori ?? null}
            activeNewFilter={newFilter ?? null}
            activePopularFilter={popularFilter ?? null}
          />
        </Suspense>
      </div>

      <Suspense fallback={null}>
        <ProductsInfiniteGrid />
      </Suspense>
    </div>
  );
}
