import type { Metadata } from "next";
import { Suspense } from "react";
import { ProductSearchBar } from "@/components/products/ProductSearchBar";
import { ProductFilterChips } from "@/components/products/ProductFilterChips";
import { ProductsInfiniteGrid } from "@/components/products/ProductsInfiniteGrid";
import { FALLBACK_BRANDS } from "@/lib/brand-catalog";
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
    brand?: string;
    q?: string;
    new?: string;
    popular?: string;
  }>;
}) {
  const { kategori, brand, q, new: newParam, popular: popularParam } = await searchParams;
  const newFilter = asNewFilter(newParam);
  const popularFilter = asPopularFilter(popularParam);

  const [categories, activeBrand] = await Promise.all([
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
    brand
      ? prisma.brand
          .findUnique({ where: { slug: brand }, select: { name: true } })
          .catch(() => null)
      : Promise.resolve(null),
  ]);
  const fallbackBrandName = brand
    ? FALLBACK_BRANDS.find((item) => item.slug === brand)?.name
    : undefined;
  const activeBrandName = activeBrand?.name ?? fallbackBrandName;
  const title = activeBrandName ? `Produk ${activeBrandName}` : "Katalog Produk";

  return (
    <div className="mx-auto max-w-6xl px-4 pb-[calc(6rem+env(safe-area-inset-bottom))] md:py-10">
      <div className="sticky top-[calc(var(--natalo-mobile-header-min-height)+env(safe-area-inset-top))] z-50 -mx-4 mb-4 rounded-b-3xl bg-white px-4 pb-3 pt-3 shadow-[0_8px_24px_rgba(15,23,42,0.06)] md:static md:mx-0 md:mb-5 md:rounded-none md:bg-transparent md:px-0 md:pb-0 md:pt-0 md:shadow-none">
        {activeBrandName && (
          <div className="mb-3">
            <h1 className="text-2xl font-black tracking-tight text-slate-950">{title}</h1>
            <p className="mt-1 text-sm font-semibold text-slate-500">
              Produk dari brand pilihanmu.
            </p>
          </div>
        )}
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
