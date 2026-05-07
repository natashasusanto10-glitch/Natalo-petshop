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
import Link from "next/link";

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ kategori?: string; q?: string }>;
}) {
  const { kategori, q } = await searchParams;

  const [products, categories] = await Promise.all([
    getProducts({ category: kategori, search: q }),
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
  ]);

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      {/* Page header */}
      <div className="mb-6">
        <h1 className="text-3xl font-black text-gray-900">Katalog Produk</h1>
        <p className="mt-1 text-sm text-gray-500">
          Semua kebutuhan hewan peliharaan kamu tersedia di sini.
        </p>
      </div>

      {/* Search bar */}
      <div className="mb-6">
        <Suspense fallback={<div className="h-12 w-full animate-pulse rounded-2xl bg-gray-100" />}>
          <ProductSearchInput defaultValue={q} />
        </Suspense>
      </div>

      {/* Category filter pills */}
      {categories.length > 0 && (
        <div className="mb-8 flex flex-wrap gap-2">
          <Link
            href="/products"
            className={`rounded-full border px-4 py-2 text-sm font-medium transition ${
              !kategori
                ? "border-orange-500 bg-orange-500 text-white"
                : "border-gray-200 bg-white text-gray-600 hover:border-orange-400 hover:text-orange-500"
            }`}
          >
            Semua
          </Link>
          {categories.map((cat) => (
            <Link
              key={cat.id}
              href={`/products?kategori=${cat.slug}`}
              className={`rounded-full border px-4 py-2 text-sm font-medium transition ${
                kategori === cat.slug
                  ? "border-orange-500 bg-orange-500 text-white"
                  : "border-gray-200 bg-white text-gray-600 hover:border-orange-400 hover:text-orange-500"
              }`}
            >
              {cat.name}
            </Link>
          ))}
        </div>
      )}

      {/* Products grid */}
      {products.length > 0 ? (
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {products.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      ) : (
        <div className="rounded-2xl bg-gray-50 p-12 text-center">
          <span className="text-5xl">🐾</span>
          <p className="mt-4 text-gray-500">Belum ada produk.</p>
          <Link
            href="/admin/products/new"
            className="mt-4 inline-flex rounded-full bg-orange-500 px-6 py-3 text-sm font-bold text-white"
          >
            Tambah produk
          </Link>
        </div>
      )}
    </div>
  );
}
