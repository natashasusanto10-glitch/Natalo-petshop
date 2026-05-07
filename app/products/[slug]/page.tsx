import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ProductCard } from "@/components/ProductCard";
import { ProductActions } from "@/components/ProductActions";
import { WhatsAppButton } from "@/components/WhatsAppButton";
import { formatRupiah } from "@/lib/format";
import { getProductBySlug, getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { ReviewForm } from "@/components/ReviewForm";
import { ReviewList } from "@/components/ReviewList";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const product = await getProductBySlug(slug);
  if (!product) return { title: "Produk tidak ditemukan" };

  const price = product.memberPrice ?? product.price;

  return {
    title: product.name,
    description: `${product.description.slice(0, 150)}... Harga ${formatRupiah(price)} di ${brand}.`,
    openGraph: {
      title: `${product.name} | ${brand}`,
      description: product.description.slice(0, 150),
      url: `${siteUrl}/products/${slug}`,
      images: product.imageUrl
        ? [{ url: product.imageUrl, alt: product.name }]
        : [{ url: `${siteUrl}/icon.svg`, alt: brand }],
      type: "website",
    },
  };
}

export default async function ProductDetailPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const product = await getProductBySlug(slug);
  if (!product) return notFound();

  // Ambil kategori dan produk terkait
  const [productWithCategory, allProducts] = await Promise.all([
    prisma.product.findUnique({ where: { slug }, include: { category: true } }).catch(() => null),
    getProducts(),
  ]);

  const category = productWithCategory?.category ?? null;
  const related = allProducts
    .filter((p) => p.id !== product.id && (category ? true : true))
    .sort((a, b) => {
      // Prioritize same-category products
      const aMatch = productWithCategory?.categoryId && (a as unknown as { categoryId?: string }).categoryId === productWithCategory.categoryId;
      const bMatch = productWithCategory?.categoryId && (b as unknown as { categoryId?: string }).categoryId === productWithCategory.categoryId;
      if (aMatch && !bMatch) return -1;
      if (!aMatch && bMatch) return 1;
      return 0;
    })
    .slice(0, 4);

  const price = product.memberPrice ?? product.price;
  const savings = product.memberPrice ? product.price - product.memberPrice : 0;
  const outOfStock = product.stock === 0;
  const waPhone = (process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ?? "").replace("+", "");

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "Product",
    name: product.name,
    description: product.description,
    image: product.imageUrl ?? `${siteUrl}/icon.svg`,
    url: `${siteUrl}/products/${slug}`,
    brand: { "@type": "Brand", name: brand },
    offers: {
      "@type": "Offer",
      price: price,
      priceCurrency: "IDR",
      availability: outOfStock
        ? "https://schema.org/OutOfStock"
        : "https://schema.org/InStock",
      seller: { "@type": "Organization", name: brand },
    },
  };

  return (
    <div>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      {/* Breadcrumb */}
      <div className="border-b border-gray-100 bg-white">
        <div className="mx-auto max-w-6xl px-4 py-3">
          <nav className="flex items-center gap-2 text-sm text-gray-400">
            <Link href="/" className="transition hover:text-orange-500">Beranda</Link>
            <span>/</span>
            <Link href="/products" className="transition hover:text-orange-500">Produk</Link>
            <span>/</span>
            <span className="text-gray-700">{product.name}</span>
          </nav>
        </div>
      </div>

      {/* Main */}
      <div className="mx-auto max-w-6xl px-4 py-10">
        <div className="grid gap-10 lg:grid-cols-2">
          {/* Image */}
          <div className="relative aspect-square overflow-hidden rounded-3xl bg-gray-100">
            {product.imageUrl ? (
              <Image
                src={product.imageUrl}
                alt={product.name}
                fill
                className="object-cover"
                priority
              />
            ) : (
              <div className="flex h-full items-center justify-center">
                <span className="text-9xl text-gray-200">🐾</span>
              </div>
            )}
            {product.memberPrice && (
              <span className="absolute left-4 top-4 rounded-full bg-orange-500 px-3 py-1 text-xs font-bold text-white shadow">
                Harga Member
              </span>
            )}
          </div>

          {/* Info */}
          <div className="flex flex-col">
            {/* Category & stock */}
            <div className="flex flex-wrap items-center gap-2">
              {category && (
                <span className="rounded-full bg-orange-100 px-3 py-1 text-xs font-semibold text-orange-500">
                  {category.name}
                </span>
              )}
              <span
                className={`rounded-full px-3 py-1 text-xs font-semibold ${
                  outOfStock
                    ? "bg-red-100 text-red-500"
                    : "bg-green-100 text-green-600"
                }`}
              >
                {outOfStock ? "Stok Habis" : "Tersedia"}
              </span>
            </div>

            {/* Name */}
            <h1 className="mt-4 text-3xl font-black leading-tight tracking-tight text-gray-900">
              {product.name}
            </h1>

            {/* Price */}
            <div className="mt-5 rounded-2xl bg-gray-50 p-5">
              <p className="text-3xl font-black text-orange-500">{formatRupiah(price)}</p>
              {product.memberPrice && (
                <div className="mt-1 flex flex-wrap items-center gap-3">
                  <p className="text-sm text-gray-400 line-through">
                    {formatRupiah(product.price)}
                  </p>
                  <span className="rounded-full bg-orange-100 px-2 py-0.5 text-xs font-bold text-orange-500">
                    Hemat {formatRupiah(savings)}
                  </span>
                </div>
              )}
              {!product.memberPrice && (
                <p className="mt-1 text-xs text-gray-400">
                  Daftar member untuk harga lebih murah.{" "}
                  <Link href="/member/register" className="font-semibold text-orange-500 hover:underline">
                    Daftar gratis →
                  </Link>
                </p>
              )}
            </div>

            {/* Description */}
            <p className="mt-5 leading-7 text-gray-600 whitespace-pre-line">
              {product.description}
            </p>

            {/* Specs */}
            <div className="mt-5 grid grid-cols-2 gap-3">
              <div className="rounded-xl bg-gray-50 p-3 text-sm">
                <p className="text-gray-400">Berat</p>
                <p className="font-semibold text-gray-800">{product.weightGram} gram</p>
              </div>
              <div className="rounded-xl bg-gray-50 p-3 text-sm">
                <p className="text-gray-400">Stok</p>
                <p className="font-semibold text-gray-800">
                  {outOfStock ? "Habis" : `${product.stock} tersedia`}
                </p>
              </div>
            </div>

            {/* Actions */}
            <div className="mt-6 space-y-3">
              <ProductActions product={product} />
              <a
                href={`https://wa.me/${waPhone}?text=${encodeURIComponent(`Halo, saya mau tanya tentang ${product.name}.`)}`}
                target="_blank"
                rel="noreferrer"
                className="flex w-full items-center justify-center gap-2 rounded-full border border-gray-200 py-3 text-sm font-semibold text-gray-700 transition hover:border-green-400 hover:text-green-600"
              >
                <span>💬</span> Tanya via WhatsApp
              </a>
            </div>

            {/* Link ke keranjang setelah tambah */}
            <p className="mt-4 text-center text-xs text-gray-400">
              Sudah di keranjang?{" "}
              <Link href="/cart" className="font-semibold text-orange-500 hover:underline">
                Lihat keranjang →
              </Link>
            </p>
          </div>
        </div>

        {/* Reviews */}
        <section className="mt-16">
          <h2 className="text-xl font-black text-gray-900">Ulasan Produk</h2>
          <div className="mt-6 grid gap-8 lg:grid-cols-2">
            <div>
              <ReviewList productId={product.id} />
            </div>
            <div className="rounded-3xl border border-gray-100 bg-white p-6">
              <h3 className="font-bold text-gray-900">Tulis Ulasan</h3>
              <p className="mt-1 text-sm text-gray-500">Bagikan pengalamanmu dengan produk ini.</p>
              <div className="mt-5">
                <ReviewForm productId={product.id} />
              </div>
            </div>
          </div>
        </section>

        {/* Related products */}
        {related.length > 0 && (
          <section className="mt-16">
            <h2 className="text-xl font-black text-gray-900">Produk lainnya</h2>
            <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
              {related.map((p) => (
                <ProductCard key={p.id} product={p} />
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
