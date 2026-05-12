import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ProductActions } from "@/components/ProductActions";
import { ProductImageCarousel } from "@/components/ProductImageCarousel";
import { ProductPurchaseButtons } from "@/components/ProductPurchaseButtons";
import { VariantSelector } from "@/components/VariantSelector";
import { StickyAddToCartBar } from "@/components/products/StickyAddToCartBar";
import { PriceBlock } from "@/components/products/PriceBlock";
import { SocialProofRow } from "@/components/products/SocialProofRow";
import { TrustInfoCard } from "@/components/products/TrustInfoCard";
import { VoucherCard } from "@/components/products/VoucherCard";
import { ProductTabs } from "@/components/products/ProductTabs";
import { formatRupiah } from "@/lib/format";
import { getProductBySlug, getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { ReviewForm } from "@/components/ReviewForm";
import { ReviewList } from "@/components/ReviewList";
import { PageStatusBar } from "@/components/PageStatusBar";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";

// Cache HTML 60 detik di Vercel CDN — page lebih dingin & cepat. Voucher
// member yang per-user di-load client-side oleh <VoucherCard /> via fetch
// /api/products/[slug]/vouchers (session cookie ikut).
export const revalidate = 60;

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

  // Voucher load di-pindah ke client-side (VoucherCard fetch sendiri)
  // supaya halaman ini bisa cacheable di Vercel CDN. getSession() yg dulu
  // dipakai utk filter voucher per-user juga tidak diperlukan di server.
  const [productWithCategory, allProducts] = await Promise.all([
    prisma.product.findUnique({ where: { slug }, include: { category: true } }).catch(() => null),
    getProducts({ category: product.categorySlug ?? undefined, take: 12 }),
  ]);
  const favoriteIds: string[] = [];

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
    .slice(0, 6)
    .map((p) => ({
      id: p.id,
      slug: p.slug,
      name: p.name,
      price: p.price,
      discountPrice: p.discountPrice ?? null,
      imageUrl: p.imageUrl ?? null,
    }));

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
  // imageUrl = thumbnail utama (slide pertama, ditandai "Utama" di admin).
  // gallery = gambar tambahan yg di-upload via MultiImageUpload.
  const productImages = [product.imageUrl, ...(product.gallery ?? [])].filter(
    Boolean,
  ) as string[];

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
      {/* Status bar override per-product. Default app-wide = dark icons + white
          themeColor. Untuk produk dengan hero photo gelap atau brand-themed
          card di top, ganti ke iconColor="light" themeColor="#1E5FBF" supaya
          icon putih kontras dengan content gelap. Di sini default OK karena
          mobile header bar putih sticky di atas product image. */}
      <PageStatusBar iconColor="dark" themeColor="#ffffff" />
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
          <ProductImageCarousel
            images={productImages}
            alt={product.name}
            transitionName={`nat-prod-${product.slug}`}
          />

          <section className="bg-white px-4 py-4 md:rounded-3xl md:border md:border-gray-100 md:p-6">
            {/* 1. Blok harga jangkar */}
            <PriceBlock
              productId={product.id}
              price={price}
              originalPrice={hasDiscount ? product.price : null}
              discountPercent={percent}
              initialFavorited={favoriteIds.includes(product.id)}
            />

            {/* 2. Judul produk — ukuran sedang, weight 600 */}
            <h1 className="mt-3 line-clamp-2 text-base font-semibold leading-snug text-gray-900 md:text-xl md:font-bold">
              {product.name}
            </h1>

            {/* 3. Bukti sosial satu baris */}
            <SocialProofRow
              avgRating={product.avgRating}
              reviewCount={product.reviewCount}
            />

            {/* 4. Voucher card */}
            <VoucherCard productSlug={slug} />

            {/* 5. Trust info — garansi + stok */}
            <TrustInfoCard stock={product.stock} outOfStock={outOfStock} />

            {/* 6. Variant selector / quantity actions */}
            {product.hasVariants && product.variantAttrs && product.variants ? (
              <div id="beli" className="mt-4 scroll-mt-20 rounded-2xl border border-gray-100 p-4">
                <VariantSelector
                  product={{ id: product.id, slug: product.slug, name: product.name, imageUrl: product.imageUrl }}
                  attrs={product.variantAttrs}
                  variants={product.variants}
                />
              </div>
            ) : (
              <div id="beli" className="scroll-mt-20">
                <ProductActions product={product} />
              </div>
            )}

            {/* 7. Tombol pembelian inline (desktop only) */}
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

        {/* 8. Tabs Deskripsi / Rekomendasi */}
        <section className="mt-2 bg-white md:mt-10 md:rounded-3xl md:border md:border-gray-100">
          <ProductTabs description={product.description} related={related} />
        </section>

        {/* 9. Ulasan tetap section terpisah di bawah agar tab tidak overload */}
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
      </div>

      {/* Sticky bottom bar — selalu terlihat di mobile */}
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
