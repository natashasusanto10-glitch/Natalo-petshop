import type { Metadata } from "next";
import { Suspense } from "react";
import { EtalaseBand } from "@/components/products/EtalaseBand";
import { ProductCatalogStickyHeader } from "@/components/products/ProductCatalogStickyHeader";
import { ProductsCatalogClient } from "@/components/products/ProductsCatalogClient";
import { ProductsGridSkeleton } from "@/components/products/ProductsGridSkeleton";
import { PageContainer } from "@/components/ui/PageContainer";
import { ETALASE_TRUST, etalaseHeading, etalaseTagline } from "@/lib/etalase";
import { parseProductsParams } from "@/lib/products-search-params";
import { prisma } from "@/lib/prisma";

// Filter per-pengunjung lewat query param. Halaman tetap dinamis supaya state
// filter langsung terlihat sementara grid dimuat di klien.
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

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const resolved = await searchParams;
  const usp = new URLSearchParams();
  for (const [rawKey, rawValue] of Object.entries(resolved)) {
    if (Array.isArray(rawValue)) rawValue.forEach((value) => usp.append(rawKey, value));
    else if (rawValue !== undefined) usp.set(rawKey, rawValue);
  }
  const params = parseProductsParams(usp);
  const isSearchResult = Boolean(params.q);

  const categorySlug = params.categorySlugs[0] ?? null;
  const brandSlug = params.brandSlugs[0] ?? null;

  const [categories, activeBrand, activeCategory] = await Promise.all([
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
    brandSlug
      ? prisma.brand
          .findFirst({ where: { slug: brandSlug, isActive: true }, select: { name: true } })
          .catch(() => null)
      : Promise.resolve(null),
    categorySlug
      ? prisma.category
          .findFirst({ where: { slug: categorySlug }, select: { name: true } })
          .catch(() => null)
      : Promise.resolve(null),
  ]);

  const categoriesForHeader = categories.map((category) => ({
    slug: category.slug,
    name: category.name,
  }));

  const heading = etalaseHeading({
    brandName: activeBrand?.name,
    categoryName: activeCategory?.name,
    isSearch: isSearchResult,
    query: params.q,
  });
  const tagline = etalaseTagline({
    brandName: activeBrand?.name,
    categoryName: activeCategory?.name,
    isSearch: isSearchResult,
  });

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
        activeBrandName={activeBrand?.name}
        query={params.q}
        isSearchResult={isSearchResult}
      />

      <div className="mb-4 hidden md:block">
        <EtalaseBand
          heading={heading}
          tagline={tagline}
          meta={[...ETALASE_TRUST]}
          breadcrumb={[{ label: "Beranda", href: "/" }, { label: "Katalog" }]}
        />
      </div>

      <Suspense fallback={<ProductsGridSkeleton withSidebar />}>
        <ProductsCatalogClient />
      </Suspense>
    </PageContainer>
  );
}
