import type { Metadata } from "next";
import { ProductCard } from "@/components/ProductCard";

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
  searchParams: Promise<{ kategori?: string }>;
}) {
  const { kategori } = await searchParams;
  const session = await getSession();

  const [products, categories, favoriteIds] = await Promise.all([
    getProducts(),
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
    session
      ? prisma.favorite
          .findMany({ where: { userId: session.sub }, select: { productId: true } })
          .then((f) => f.map((x) => x.productId))
      : Promise.resolve([] as string[]),
  ]);
  const filteredProducts = kategori
    ? products.filter((product) => product.categorySlug === kategori)
    : products;
  const activeCategory = categories.find((cat) => cat.slug === kategori);

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      {/* Page header */}
      <div className="mb-8">
        <h1 className="text-3xl font-black text-gray-900">
          {activeCategory ? `Produk ${activeCategory.name}` : "Katalog Produk"}
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          {activeCategory
            ? "Format ringkas agar produk lebih mudah discan."
            : "Semua kebutuhan hewan peliharaan kamu tersedia di sini."}
        </p>
      </div>

      {/* Category filter pills */}
      {categories.length > 0 && (
        <div className="mb-8 flex flex-wrap gap-2">
          <Link
            href="/products"
            className={`rounded-full border px-4 py-2 text-sm font-medium transition ${
              !kategori
                ? "border-natalo-600 bg-natalo-600 text-white"
                : "border-gray-200 bg-white text-gray-600 hover:border-natalo-400 hover:text-natalo-600"
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
                  ? "border-natalo-600 bg-natalo-600 text-white"
                  : "border-gray-200 bg-white text-gray-600 hover:border-natalo-400 hover:text-natalo-600"
              }`}
            >
              {cat.name}
            </Link>
          ))}
        </div>
      )}

      {/* Products grid */}
      {filteredProducts.length > 0 ? (
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
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
