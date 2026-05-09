import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ProductCard } from "@/components/ProductCard";
import { ProductActions } from "@/components/ProductActions";
import { ProductDescriptionAccordion } from "@/components/ProductDescriptionAccordion";
import { ProductImageCarousel } from "@/components/ProductImageCarousel";
import { ProductPurchaseButtons } from "@/components/ProductPurchaseButtons";
import { VariantSelector } from "@/components/VariantSelector";
import { StickyAddToCartBar } from "@/components/products/StickyAddToCartBar";
import { FavoriteButton } from "@/components/FavoriteButton";
import { formatRupiah } from "@/lib/format";
import { getProductBySlug, getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { ReviewForm } from "@/components/ReviewForm";
import { ReviewList } from "@/components/ReviewList";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";

export const revalidate = 60;

function formatWeight(weightGram: number) {
  if (weightGram >= 1000 && weightGram % 1000 === 0) return `${weightGram / 1000}KG`;
  if (weightGram >= 1000) return `${(weightGram / 1000).toLocaleString("id-ID")}KG`;
  return `${weightGram} gram`;
}

function discountPercent(price: number, discountPrice: number | null) {
  if (discountPrice === null || discountPrice >= price) return null;
  return Math.round(((price - discountPrice) / price) * 100);
}

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

  const [productWithCategory, allProducts] = await Promise.all([
    prisma.product.findUnique({ where: { slug }, include: { category: true } }).catch(() => null),
    getProducts({ category: product.categorySlug ?? undefined, take: 12 }),
  ]);
  const favoriteIds: string[] = [];

  const category = productWithCategory?.category ?? null;
  const related = allProducts
    .filter((p) => p.id !== product.id)
    .sort((a, b) => {
      const aMatch =
        productWithCategory?.categoryId &&
        (a as unknown as { categoryId?: string }).categoryId === productWithCategory.categoryId;
      const bMatch =
        productWithCategory?.categoryId &&
        (b as unknown as { categoryId?: string }).categoryId === productWithCategory.categoryId;
      if (aMatch && !bMatch) return -1;
      if (!aMatch && bMatch) return 1;
      return 0;
    })
    .slice(0, 4);

  const hasDiscount = product.discountPrice !== null && product.discountPrice < product.price;
  const price = hasDiscount ? product.discountPrice! : product.price;
  const percent = discountPercent(product.price, product.discountPrice);
  const outOfStock = product.stock === 0;
  const waPhone = (
    process.env.NEXT_PUBLIC_WA_NUMBER ??
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ??
    "6281260000000"
  ).replace(/[^\d]/g, "");
  const waHref = `https://wa.me/${waPhone}?text=${encodeURIComponent(
    `Halo Admin Natalo, saya ingin bertanya tentang produk ${product.name}. Apakah produk ini ready?`,
  )}`;
  const productImages = [product.imageUrl].filter(Boolean) as string[];
  const shippingLabel = /gojek/i.test(product.description) ? "Gojek" : "Pengiriman";

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
      price,
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
    <div className="bg-gray-50 md:bg-white">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <div className="hidden border-b border-gray-100 bg-white md:block">
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

      <div className="mx-auto max-w-6xl pb-40 md:px-4 md:py-10 md:pb-10">
        <div className="grid gap-2 bg-gray-50 md:grid-cols-2 md:gap-10 md:bg-white">
          <ProductImageCarousel images={productImages} alt={product.name} />

          <section className="bg-white px-4 py-4 md:rounded-3xl md:border md:border-gray-100 md:p-6">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-2xl font-black leading-none text-natalo-600 md:text-3xl">
                  {formatRupiah(price)}
                </p>
                {hasDiscount && (
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <span className="text-sm font-semibold text-gray-400 line-through">
                      {formatRupiah(product.price)}
                    </span>
                    {percent !== null && (
                      <span className="rounded bg-red-50 px-1.5 py-0.5 text-xs font-black text-red-500">
                        -{percent}%
                      </span>
                    )}
                  </div>
                )}
              </div>
              <FavoriteButton
                productId={product.id}
                initialFavorited={favoriteIds.includes(product.id)}
                size="md"
              />
            </div>

            <h1 className="mt-3 line-clamp-2 text-base font-extrabold leading-snug text-gray-900 md:text-2xl">
              {product.name}
            </h1>

            {product.avgRating > 0 && product.reviewCount > 0 && (
              <p className="mt-2 text-xs font-bold text-amber-500">
                {product.avgRating.toFixed(1)} / 5 dari {product.reviewCount} ulasan
              </p>
            )}

            <div className="mt-3 flex flex-wrap gap-1.5">
              <span className="rounded-full bg-green-50 px-2.5 py-1 text-xs font-extrabold text-green-700">
                {outOfStock ? "Stok Habis" : "Tersedia"}
              </span>
              <span className="rounded-full bg-gray-100 px-2.5 py-1 text-xs font-extrabold text-gray-700">
                {formatWeight(product.weightGram)}
              </span>
              <span className="rounded-full bg-gray-100 px-2.5 py-1 text-xs font-extrabold text-gray-700">
                Stok {product.stock}
              </span>
              {category && (
                <span className="rounded-full bg-natalo-50 px-2.5 py-1 text-xs font-extrabold text-natalo-700">
                  {category.name}
                </span>
              )}
              <span className="rounded-full bg-gray-100 px-2.5 py-1 text-xs font-extrabold text-gray-700">
                {shippingLabel}
              </span>
            </div>

            {product.hasVariants && product.variantAttrs && product.variants ? (
              <div id="beli" className="mt-4 scroll-mt-20 rounded-2xl border border-gray-100 p-4">
                <VariantSelector
                  product={{ id: product.id, name: product.name, imageUrl: product.imageUrl }}
                  attrs={product.variantAttrs}
                  variants={product.variants}
                />
              </div>
            ) : (
              <div id="beli" className="scroll-mt-20">
                <ProductActions product={product} />
              </div>
            )}

            <ProductPurchaseButtons
              waHref={waHref}
              initialState={{
                hasVariants: product.hasVariants,
                canAdd: !product.hasVariants && !outOfStock,
                outOfStock,
                price,
              }}
            />
          </section>
        </div>

        <div className="mt-2 md:mt-8">
          <ProductDescriptionAccordion description={product.description} />
        </div>

        <section className="mt-2 bg-white px-4 py-5 md:mt-10 md:rounded-3xl md:border md:border-gray-100 md:p-6">
          <h2 className="text-base font-black text-gray-900 md:text-xl">Ulasan Produk</h2>
          <div className="mt-4 grid gap-6 md:mt-6 md:gap-8 lg:grid-cols-2">
            <ReviewList productId={product.id} />
            <div className="rounded-2xl border border-gray-100 bg-white p-5">
              <h3 className="font-bold text-gray-900">Tulis Ulasan</h3>
              <p className="mt-1 text-sm text-gray-500">Bagikan pengalamanmu dengan produk ini.</p>
              <div className="mt-5">
                <ReviewForm productId={product.id} />
              </div>
            </div>
          </div>
        </section>

        {related.length > 0 && (
          <section className="mt-2 bg-white px-4 py-5 md:mt-10 md:rounded-3xl md:border md:border-gray-100 md:p-6">
            <h2 className="text-base font-black text-gray-900 md:text-xl">Produk Terkait</h2>
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

      <StickyAddToCartBar
        waHref={waHref}
        initialState={{
          hasVariants: product.hasVariants,
          canAdd: !product.hasVariants && !outOfStock,
          outOfStock,
          price,
        }}
      />
    </div>
  );
}
