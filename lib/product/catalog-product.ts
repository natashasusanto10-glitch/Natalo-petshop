import type { StoreProduct } from "@/lib/products";
import { resolveActiveDiscount } from "@/lib/product-pricing";
import { productVideoPayload } from "@/lib/product/product-video-serialize";

export type CatalogProductInput = {
  id: string;
  name: string;
  slug: string;
  description: string;
  price: number;
  discountPrice: number | null;
  memberPrice: number | null;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  gallery: string[];
  hasVariants: boolean;
  avgRating: number;
  reviewCount: number;
  category: { id: string; slug: string } | null;
  brand: { name: string } | null;
  brandId: string | null;
  flashSaleEndsAt: Date | null;
  videoStatus: string | null;
  videoUrl: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
  variants: Array<{ id: string; price: number; stock: number }>;
  discountItems: Array<{
    variantId: string | null;
    discountedPrice: number;
    discount: { endsAt: Date };
  }>;
};

export function normalizeProductWeight(
  name: string,
  slug: string,
  weightGram: number
) {
  const text = `${name} ${slug}`.toLowerCase();
  if (text.includes("maxi-cat") && text.includes("20kg")) return 20000;
  return weightGram;
}

export function mapCatalogProduct(p: CatalogProductInput): StoreProduct {
  if (p.hasVariants && p.variants.length > 0) {
    // Untuk produk berVarian, pricing per-variant. Hitung MIN effective
    // price dari semua varian aktif setelah apply discount item match.
    const variantPrices = p.variants.map((v) => {
      const variantPromoItems = p.discountItems
        .filter((it) => it.variantId === v.id)
        .map((it) => ({
          discountedPrice: it.discountedPrice,
          endsAt: it.discount.endsAt,
        }));
      const discount = resolveActiveDiscount(
        v.price,
        // Flash Sale ratio applied (untuk variant, kalau Flash Sale ada
        // di parent, pakai ratio dari product.price ke product.discountPrice
        // dan apply ke variant.price)
        flashSaleForVariant(
          p.price,
          p.discountPrice,
          p.flashSaleEndsAt,
          v.price
        ),
        variantPromoItems
      );
      return discount ? discount.effectivePrice : v.price;
    });
    const minPrice = Math.min(...variantPrices);
    const totalStock = p.variants.reduce((s, v) => s + v.stock, 0);
    // discountPrice di-set ke minPrice kalau lebih rendah dari product.price
    // (artinya ada diskon aktif di variant terendah).
    const showDiscount = minPrice < Math.min(...p.variants.map((v) => v.price));

    return {
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price: Math.min(...p.variants.map((v) => v.price)),
      discountPrice: showDiscount ? minPrice : null,
      memberPrice: p.memberPrice,
      stock: totalStock,
      weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
      imageUrl: p.imageUrl,
      gallery: p.gallery ?? [],
      hasVariants: true,
      avgRating: p.avgRating,
      reviewCount: p.reviewCount,
      categoryId: p.category?.id ?? null,
      categorySlug: p.category?.slug ?? null,
      brand: p.brand?.name ?? null,
      brandId: p.brandId ?? null,
      voucherPreview: null,
      shippingVoucherPreview: null,
      flashSaleEndsAt: p.flashSaleEndsAt?.toISOString() ?? null,
      ...productVideoPayload({
        videoStatus: p.videoStatus,
        videoUrl: p.videoUrl,
        videoThumbnailUrl: p.videoThumbnailUrl,
        videoDurationSec: p.videoDurationSec,
      }),
    };
  }

  // Produk single (no variants) — apply discount langsung.
  const promoItems = p.discountItems
    .filter((it) => it.variantId === null)
    .map((it) => ({
      discountedPrice: it.discountedPrice,
      endsAt: it.discount.endsAt,
    }));
  const discount = resolveActiveDiscount(
    p.price,
    { discountPrice: p.discountPrice, endsAt: p.flashSaleEndsAt },
    promoItems
  );

  // Override discountPrice dengan effective dari resolver. Source:
  //  - FLASH_SALE: keep flashSaleEndsAt (countdown timer di customer side)
  //  - PROMO_TOKO: clear flashSaleEndsAt supaya tidak salah tampil
  //    countdown (Promo Toko bukan urgency-driven).
  const effectiveDiscountPrice = discount ? discount.effectivePrice : null;
  const effectiveFlashSaleEndsAt =
    discount?.source === "FLASH_SALE"
      ? p.flashSaleEndsAt?.toISOString() ?? null
      : null;

  return {
    id: p.id,
    name: p.name,
    slug: p.slug,
    description: p.description,
    price: p.price,
    discountPrice: effectiveDiscountPrice,
    memberPrice: p.memberPrice,
    stock: p.stock,
    weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
    imageUrl: p.imageUrl,
    gallery: p.gallery ?? [],
    hasVariants: false,
    avgRating: p.avgRating,
    reviewCount: p.reviewCount,
    categoryId: p.category?.id ?? null,
    categorySlug: p.category?.slug ?? null,
    brand: p.brand?.name ?? null,
    brandId: p.brandId ?? null,
    voucherPreview: null,
    shippingVoucherPreview: null,
    flashSaleEndsAt: effectiveFlashSaleEndsAt,
    ...productVideoPayload({
      videoStatus: p.videoStatus,
      videoUrl: p.videoUrl,
      videoThumbnailUrl: p.videoThumbnailUrl,
      videoDurationSec: p.videoDurationSec,
    }),
  };
}

/**
 * Hitung Flash Sale price untuk variant tertentu — pakai ratio
 * dari (product.discountPrice / product.price) × variant.price.
 * Karena Flash Sale di-set di product level (single discountPrice),
 * tapi setiap variant punya base price sendiri.
 */
export function flashSaleForVariant(
  productPrice: number,
  productDiscountPrice: number | null,
  flashEnd: Date | null,
  variantPrice: number
): { discountPrice: number | null; endsAt: Date | null } {
  if (!flashEnd || !productDiscountPrice || productPrice <= 0) {
    return { discountPrice: null, endsAt: null };
  }
  const ratio = productDiscountPrice / productPrice;
  return {
    discountPrice: Math.round(variantPrice * ratio),
    endsAt: flashEnd,
  };
}
