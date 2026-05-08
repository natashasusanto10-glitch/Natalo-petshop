import type { Metadata } from "next";
import { Suspense } from "react";
import { ProductCard } from "@/components/ProductCard";
import { ProductSearchInput } from "@/components/ProductSearchInput";

export const revalidate = 60;

export const metadata: Metadata = {
  title: "Katalog Produk",
  description: "Temukan pakan ikan, aksesoris kucing, anjing, burung, kelinci, dan kebutuhan aquarium lengkap dengan harga terjangkau.",
  openGraph: {
    title: "Katalog Produk",
    description: "Semua kebutuhan hewan peliharaan kamu tersedia di sini. Produk original, harga bersaing.",
  },
};
import { getProducts, getProductsCount } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import Link from "next/link";

const PAGE_SIZE = 24;

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ kategori?: string; q?: string; page?: string }>;
}) {
  const { kategori, q, page: pageStr } = await searchParams;
  const page = Math.max(1, parseInt(pageStr ?? "1", 10) || 1);

  // Catatan: tidak panggil getSession() agar route bisa di-cache di edge.
  // Highlight "favorited" di-handle client-side oleh WishlistButton (localStorage).
  const [filteredProducts, total, categories] = await Promise.all([
    getProducts({
      category: kategori,
      search: q,
      take: PAGE_SIZE,
      skip: (page - 1) * PAGE_SIZE,
    }),
    getProductsCount({ category: kategori, search: q }),
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
  ]);
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
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
                ? "border-blue-500 bg-blue-500 text-white"
                : "border-gray-200 bg-white text-gray-600 hover:border-blue-400 hover:text-blue-600"
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
                  ? "border-blue-500 bg-blue-500 text-white"
                  : "border-gray-200 bg-white text-gray-600 hover:border-blue-400 hover:text-blue-600"
              }`}
            >
              {cat.name}
            </Link>
          ))}
        </div>
      )}

      {/* Products grid */}
      {filteredProducts.length > 0 ? (
        <>
          <p className="mb-3 text-xs text-gray-500">
            Menampilkan {(page - 1) * PAGE_SIZE + 1}–
            {(page - 1) * PAGE_SIZE + filteredProducts.length} dari {total} produk
          </p>
          <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4">
            {filteredProducts.map((product, index) => (
              <ProductCard
                key={product.id}
                product={product}
                priority={index === 0}
              />
            ))}
          </div>
          {totalPages > 1 && (
            <Pagination
              page={page}
              totalPages={totalPages}
              kategori={kategori}
              q={q}
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
}: {
  page: number;
  totalPages: number;
  kategori?: string;
  q?: string;
}) {
  function buildHref(p: number) {
    const params = new URLSearchParams();
    if (kategori) params.set("kategori", kategori);
    if (q) params.set("q", q);
    if (p > 1) params.set("page", String(p));
    const qs = params.toString();
    return `/products${qs ? `?${qs}` : ""}`;
  }

  // Build page list: first 2, current ±1, last 2 (with ellipsis)
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
