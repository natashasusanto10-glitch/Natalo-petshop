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
    brand?: string;
    q?: string;
    new?: string;
    popular?: string;
  }>;
}) {
  const { kategori, brand, q, new: newParam, popular: popularParam } = await searchParams;
  const newFilter = asNewFilter(newParam);
  const popularFilter = asPopularFilter(popularParam);
  const isSearchResult = Boolean(q?.trim());

  const [categories, activeBrand] = await Promise.all([
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
    brand
      ? prisma.brand
          .findFirst({
            where: { slug: brand, isActive: true },
            select: { name: true },
          })
          .catch(() => null)
      : Promise.resolve(null),
  ]);
  const activeBrandName = activeBrand?.name;
  const title = activeBrandName ? `Produk ${activeBrandName}` : "Katalog Produk";

  return (
    <div
      className={`mx-auto max-w-6xl px-4 ${
        isSearchResult
          ? "pb-[calc(1.5rem+env(safe-area-inset-bottom))] md:py-8"
          : "pb-[calc(6rem+env(safe-area-inset-bottom))] md:py-10"
      }`}
    >
      {/* Sticky search + filter row. Non-search mode (Header global tampil):
          pt-0 + -mt-1 (-4px) pulls search bar up untuk tipiskan vertical-
          centering whitespace yang tersisa di dalam Header element
          (.nat-header-inner min-height 60px + items-center vs logo h-10
          menyisakan ~8px whitespace di bawah ikon). Hasil akhir: gap visual
          dari bawah ikon ke search bar ~4px — rapat tapi tetap punya hairline
          breathing space biar tidak menempel kasar. Mengubah min-height
          Header langsung akan affect SEMUA halaman lain, di luar scope.
          Search-result mode (Header hidden via route check di Header.tsx):
          pakai padding-top eksplisit untuk safe-area status bar, tidak butuh
          negative margin. md: reset karena desktop pakai static positioning. */}
      <div
        className={`sticky z-50 -mx-4 mb-3 bg-white px-4 pb-2.5 pt-0 shadow-[0_8px_24px_rgba(15,23,42,0.06)] ${
          isSearchResult
            ? "top-0 [padding-top:calc(0.5rem+env(safe-area-inset-top))]"
            : "-mt-3 top-[calc(var(--natalo-mobile-header-min-height)+env(safe-area-inset-top)-0.5rem)] rounded-b-3xl"
        } md:mt-0 md:static md:mx-0 md:mb-5 md:rounded-none md:bg-transparent md:px-0 md:pb-0 md:pt-0 md:shadow-none`}
      >
        {activeBrandName && (
          <div className="mb-3">
            <h1 className="text-2xl font-black tracking-tight text-slate-950">{title}</h1>
            <p className="mt-1 text-sm font-semibold text-slate-500">
              Produk dari brand pilihanmu.
            </p>
          </div>
        )}
        <div className="mb-1.5">
          <Suspense fallback={<div className="h-10 w-full animate-pulse rounded-full bg-gray-100" />}>
            <ProductSearchBar defaultValue={q ?? ""} showBackButton={isSearchResult} />
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
