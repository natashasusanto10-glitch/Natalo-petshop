import type { Metadata } from "next";
import { Suspense } from "react";
import { ProductCatalogStickyHeader } from "@/components/products/ProductCatalogStickyHeader";
import { ProductsInfiniteGrid } from "@/components/products/ProductsInfiniteGrid";
import { PageContainer } from "@/components/ui/PageContainer";
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

const NEW_FILTERS: NewProductFilter[] = [
  "today",
  "this-week",
  "this-month",
  "last-30-days",
  "newest",
];
const POPULAR_FILTERS: PopularFilter[] = [
  "best-seller",
  "trending",
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
  const categoriesForHeader = categories.map((c) => ({ slug: c.slug, name: c.name }));

  return (
    <PageContainer
      className={
        isSearchResult
          ? "pb-[calc(1.5rem+env(safe-area-inset-bottom))] md:py-8"
          : "pb-[calc(6rem+env(safe-area-inset-bottom))] md:py-10"
      }
    >
      <ProductCatalogStickyHeader
        brandName={process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop"}
        categories={categoriesForHeader}
        activeBrandName={activeBrandName}
        query={q ?? ""}
        activeCategory={kategori ?? null}
        activeNewFilter={newFilter ?? null}
        activePopularFilter={popularFilter ?? null}
        isSearchResult={isSearchResult}
      />

      <Suspense fallback={null}>
        <ProductsInfiniteGrid />
      </Suspense>
    </PageContainer>
  );
}
