import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ProductCard } from "@/components/ProductCard";
import { ProductActions } from "@/components/ProductActions";
import { VariantSelector } from "@/components/VariantSelector";
import { StickyAddToCartBar } from "@/components/products/StickyAddToCartBar";
import { FavoriteButton } from "@/components/FavoriteButton";
import { ReviewSection } from "@/components/ReviewSection";
import { formatRupiah } from "@/lib/format";
import { getProductBySlug, getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { ReviewForm } from "@/components/ReviewForm";
import { ReviewList } from "@/components/ReviewList";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";

export const revalidate = 60;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const product = await getProductBySlug(slug);
  if (!product) return { title: "Produk tidak ditemukan" };

  const metadataPrice =
    product.discountPrice !== null && product.discountPrice < product.price
      ? product.discountPrice
      : product.price;
  const shortDescription = product.description.replace(/\s+/g, " ").trim().slice(0, 140);
  const productImage = product.imageUrl
    ? product.imageUrl.startsWith("http")
      ? product.imageUrl
      : `${siteUrl}${product.imageUrl}`
    : `${siteUrl}/icon.svg`;

  return {
    title: `${product.name} | Natalo Petshop Medan`,
    description: `Beli ${product.name} di Natalo Petshop Medan. ${shortDescription} Kirim same-day via Gojek. Harga ${formatRupiah(metadataPrice)}.`,
    alternates: {
      canonical: `${siteUrl}/products/${slug}`,
    },
    openGraph: {
      title: `${product.name} | Natalo Petshop Medan`,
      description: `Beli ${product.name} di Natalo Petshop Medan.`,
      url: `${siteUrl}/products/${slug}`,
      images: [{ url: productImage, alt: product.name }],
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

  // Tidak panggil getSession() agar route bisa di-cache di edge.
  // Highlight favorit di-handle client-side via localStorage (WishlistButton).
  const [productWithCategory, allProducts] = await Promise.all([
    prisma.product.findUnique({ where: { slug }, include: { category: true } }).catch(() => null),
    getProducts({ category: product.categorySlug ?? undefined, take: 12 }),
  ]);
  const favoriteIds: string[] = [];

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

  const hasDiscount = product.discountPrice !== null && product.discountPrice < product.price;
  const price = hasDiscount ? product.discountPrice! : product.price;
  const outOfStock = product.stock === 0;
  const waPhone = (
    process.env.NEXT_PUBLIC_WA_NUMBER ??
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ??
    ""
  ).replace("+", "");

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
    ...(product.avgRating > 0 &&
      product.reviewCount > 0 && {
        aggregateRating: {
          "@type": "AggregateRating",
          ratingValue: product.avgRating.toFixed(1),
          reviewCount: product.reviewCount,
          bestRating: 5,
          worstRating: 1,
        },
      }),
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
            <Link href="/" className="transition hover:text-natalo-600">Beranda</Link>
            <span>/</span>
            <Link href="/products" className="transition hover:text-natalo-600">Produk</Link>
            <span>/</span>
            <span className="text-gray-700">{product.name}</span>
          </nav>
        </div>
      </div>

      {/* Main */}
      <div className="mx-auto max-w-6xl px-4 py-4 pb-24 md:py-10 md:pb-10">
        <div className="grid gap-6 lg:grid-cols-2 lg:gap-10">
          {/* Image */}
          <div className="relative aspect-square overflow-hidden rounded-3xl bg-gray-100">
            {product.imageUrl ? (
              <Image
                src={product.imageUrl}
                alt={product.name}
                fill
                sizes="(min-width: 1024px) 50vw, 100vw"
                className="object-cover"
                priority
              />
            ) : (
              <div className="flex h-full items-center justify-center">
                <span className="text-9xl text-gray-200">🐾</span>
              </div>
            )}
          </div>

          {/* Info */}
          <div className="flex flex-col">
            {/* Category & stock */}
            <div className="flex flex-wrap items-center gap-2">
              {category && (
                <span className="rounded-full bg-natalo-100 px-3 py-1 text-xs font-semibold text-natalo-600">
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

            {/* Name + Favorite */}
            <div className="mt-4 flex items-start justify-between gap-3">
              <h1 className="text-xl font-black leading-tight tracking-tight text-gray-900 md:text-3xl">
                {product.name}
              </h1>
              <FavoriteButton
                productId={product.id}
                initialFavorited={favoriteIds.includes(product.id)}
                size="md"
              />
            </div>

            {/* Price + Actions: variant vs simple */}
            {product.hasVariants && product.variantAttrs && product.variants ? (
              /* ── Produk dengan varian ─────────────────────────── */
              <div id="beli" className="mt-5 scroll-mt-20">
                <VariantSelector
                  product={{ id: product.id, name: product.name, imageUrl: product.imageUrl }}
                  attrs={product.variantAttrs}
                  variants={product.variants}
                />
              </div>
            ) : (
              /* ── Produk sederhana (tanpa varian) ─────────────── */
              <>
                <div id="beli" className="mt-5 scroll-mt-20 rounded-2xl bg-gray-50 p-5">
                  <p className="text-3xl font-black text-blue-600">{formatRupiah(price)}</p>
                  {hasDiscount && (
                    <div className="mt-2 flex flex-wrap items-center gap-3">
                      <p className="text-sm text-gray-400 line-through">
                        {formatRupiah(product.price)}
                      </p>
                      <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-bold text-red-500">
                        Harga Diskon
                      </span>
                    </div>
                  )}
                </div>

                <p className="mt-5 leading-7 text-gray-600 whitespace-pre-line">
                  {product.description}
                </p>

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
              </>
            )}

            {/* WhatsApp — selalu tampil untuk produk varian */}
            {product.hasVariants && (
              <a
                href={`https://wa.me/${waPhone}?text=${encodeURIComponent(`Halo, saya mau tanya tentang ${product.name}.`)}`}
                target="_blank"
                rel="noreferrer"
                className="mt-3 flex w-full items-center justify-center gap-2 rounded-full border border-gray-200 py-3 text-sm font-semibold text-gray-700 transition hover:border-green-400 hover:text-green-600"
              >
                <span>💬</span> Tanya via WhatsApp
              </a>
            )}

            {/* Link ke keranjang setelah tambah */}
            <p className="mt-4 text-center text-xs text-gray-400">
              Sudah di keranjang?{" "}
              <Link href="/cart" className="font-semibold text-natalo-600 hover:underline">
                Lihat keranjang →
              </Link>
            </p>
          </div>
        </div>

        {/* Reviews */}
        <section className="mt-8 md:mt-16">
          <h2 className="text-lg font-black text-gray-900 md:text-xl">Ulasan Produk</h2>
          <div className="mt-4 grid gap-6 md:mt-6 md:gap-8 lg:grid-cols-2">
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
          <section className="mt-8 md:mt-16">
            <h2 className="text-lg font-black text-gray-900 md:text-xl">Produk lainnya</h2>
            <div className="mt-4 grid grid-cols-2 gap-3 md:mt-6 md:gap-5 lg:grid-cols-4">
              {related.map((p) => (
                <ProductCard
                  key={p.id}
                  product={p}
                  isFavorited={favoriteIds.includes(p.id)}
                  variant="compact"
                />
              ))}
            </div>
          </section>
        )}
      </div>

      {/* Mobile sticky bottom CTA — state-aware (scroll ke variant kalau belum dipilih) */}
      <StickyAddToCartBar
        initialState={{
          hasVariants: product.hasVariants,
          // Untuk simple product canAdd langsung true. Untuk variant, false sampai user pilih.
          canAdd: !product.hasVariants && !outOfStock,
          outOfStock,
          price,
        }}
      />
    </div>
  );
}
