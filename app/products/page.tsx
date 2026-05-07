import type { Metadata } from "next";
import { Suspense } from "react";
import { ProductCard } from "@/components/ProductCard";
import { ProductSearchInput } from "@/components/ProductSearchInput";

export const metadata: Metadata = {
  title: "Katalog Produk",
  description: "Temukan pakan ikan, aksesoris kucing, anjing, burung, kelinci, dan kebutuhan aquarium lengkap dengan harga terjangkau.",
  openGraph: {
    title: "Katalog Produk",
    description: "Semua kebutuhan hewan peliharaan kamu tersedia di sini. Produk original, harga bersaing.",
  },
};
import { getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import Link from "next/link";

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ kategori?: string; q?: string }>;
}) {
  const { kategori, q } = await searchParams;
  const session = await getSession("CUSTOMER");

  const [products, categories, favoriteIds] = await Promise.all([
    getProducts({ category: kategori, search: q }),
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
    session
      ? prisma.favorite
          .findMany({ where: { userId: session.sub }, select: { productId: true } })
          .then((f) => f.map((x) => x.productId))
          .catch(() => [] as string[])
      : Promise.resolve([] as string[]),
  ]);
  const filteredProducts = kategori
    ? products.filter((product) => product.categorySlug === kategori)
    : products;
  const activeCategory = categories.find((cat) => cat.slug === kategori);

  return (
    <div className="mx-auto max-w-6xl px-4 py-4 md:py-10">
      {/* Page header */}
      <div className="mb-4 md:mb-6">
        <h1 className="text-2xl font-black text-gray-900 md:text-3xl">Katalog Produk</h1>
        <p className="mt-1 text-sm text-gray-500">
          {activeCategory
            ? "Format ringkas agar produk lebih mudah discan."
            : "Semua kebutuhan hewan peliharaan kamu tersedia di sini."}
        </p>
      </div>

      {/* Search bar */}
      <div className="mb-6">
        <Suspense fallback={<div className="h-12 w-full animate-pulse rounded-2xl bg-gray-100" />}>
          <ProductSearchInput defaultValue={q} />
        </Suspense>
      </div>

      {/* Category filter pills — horizontal scroll on mobile */}
      {categories.length > 0 && (
        <div className="-mx-4 mb-6 flex gap-2 overflow-x-auto px-4 pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden md:mx-0 md:mb-8 md:flex-wrap md:px-0 md:pb-0">
          <Link
            href="/products"
            className={`shrink-0 rounded-full border px-4 py-2 text-sm font-medium transition ${
              !kategori
                ? "border-orange-500 bg-orange-500 text-white"
                : "border-gray-200 bg-white text-gray-600 hover:border-orange-400 hover:text-orange-600"
            }`}
          >
            Semua
          </Link>
          {categories.map((cat) => (
            <Link
              key={cat.id}
              href={`/products?kategori=${cat.slug}`}
              className={`shrink-0 rounded-full border px-4 py-2 text-sm font-medium transition ${
                kategori === cat.slug
                  ? "border-orange-500 bg-orange-500 text-white"
                  : "border-gray-200 bg-white text-gray-600 hover:border-orange-400 hover:text-orange-600"
              }`}
            >
              {cat.name}
            </Link>
          ))}
        </div>
      )}

      {/* Products grid */}
      {filteredProducts.length > 0 ? (
        <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4">
          {filteredProducts.map((product, index) => (
            <ProductCard
              key={product.id}
              product={product}
              priority={index === 0}
              isFavorited={favoriteIds.includes(product.id)}
            />
          ))}
        </div>
      ) : (
        <div className="rounded-2xl bg-gray-50 p-12 text-center">
          <span className="text-5xl">🐾</span>
          <p className="mt-4 text-gray-500">Belum ada produk yang sesuai dengan filter.</p>
          <Link
            href="/products"
            className="mt-4 inline-flex rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white"
          >
            Lihat semua produk
          </Link>
        </div>
      )}
    </div>
  );
}
