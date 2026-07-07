import type { Prisma } from "@prisma/client";
import { resolveActiveDiscount } from "@/lib/product-pricing";

// BUG FIX: dulu const dengan `new Date()` di module load level — sekarang
// wrap di function supaya fresh per call (sama pattern dengan lib/products.ts).
export function cartRecommendationProductInclude() {
  const now = new Date();
  return {
    category: { select: { id: true, name: true, slug: true } },
    brand: { select: { id: true, name: true, slug: true } },
    variantAttrs: {
      orderBy: { position: "asc" as const },
      include: { options: { orderBy: { position: "asc" as const } } },
    },
    variants: {
      where: { deletedAt: null, isActive: true },
      include: { options: { select: { optionId: true } } },
      orderBy: { createdAt: "asc" as const },
    },
    discountItems: {
      where: {
        isItemActive: true,
        discount: {
          isActive: true,
          startsAt: { lte: now },
          endsAt: { gt: now },
        },
      },
      select: {
        variantId: true,
        discountedPrice: true,
        discount: { select: { endsAt: true } },
      },
    },
  } satisfies Prisma.ProductInclude;
}

export type CartRecommendationProductRow = Prisma.ProductGetPayload<{
  include: ReturnType<typeof cartRecommendationProductInclude>;
}>;

export function cartRecommendationWhere(excludeIds: string[] = []): Prisma.ProductWhereInput {
  // Filter `imageUrl: { not: null }` dihapus — sebelumnya produk dummy
  // tanpa foto menyebabkan section "Yuk dilihat lagi", "Rekomendasi
  // Untuk Kamu", dan cart recommendations jadi sepi saat testing. Card
  // di Flutter sudah punya placeholder fallback untuk imageUrl null,
  // jadi UX tetap acceptable. Saat real foto sudah upload, behavior
  // tetap normal (semua produk pasti punya imageUrl).
  return {
    isActive: true,
    price: { gt: 0 },
    ...(excludeIds.length > 0 ? { id: { notIn: excludeIds } } : {}),
    OR: [
      { hasVariants: false, stock: { gt: 0 } },
      {
        hasVariants: true,
        variants: { some: { isActive: true, deletedAt: null, stock: { gt: 0 } } },
      },
    ],
  };
}

export function effectiveProductPrice(product: CartRecommendationProductRow) {
  if (product.hasVariants && product.variants.length > 0) {
    // Per-variant pricing dengan resolveActiveDiscount.
    const variantPrices = product.variants.map((v) => {
      const variantPromoItems = product.discountItems
        .filter((it) => it.variantId === v.id)
        .map((it) => ({
          discountedPrice: it.discountedPrice,
          endsAt: it.discount.endsAt,
        }));
      const discount = resolveActiveDiscount(
        v.price,
        // Variant flash sale via ratio dari product level.
        product.flashSaleEndsAt && product.discountPrice
          ? {
              discountPrice: Math.round(
                v.price * (product.discountPrice / product.price),
              ),
              endsAt: product.flashSaleEndsAt,
            }
          : { discountPrice: null, endsAt: null },
        variantPromoItems,
      );
      return discount ? discount.effectivePrice : v.price;
    });
    return Math.min(...variantPrices);
  }
  // Single product — apply Flash Sale + Promo Toko priority.
  const promoItems = product.discountItems
    .filter((it) => it.variantId === null)
    .map((it) => ({
      discountedPrice: it.discountedPrice,
      endsAt: it.discount.endsAt,
    }));
  const discount = resolveActiveDiscount(
    product.price,
    { discountPrice: product.discountPrice, endsAt: product.flashSaleEndsAt },
    promoItems,
  );
  return discount ? discount.effectivePrice : product.price;
}

export function effectiveProductStock(product: CartRecommendationProductRow) {
  if (product.hasVariants && product.variants.length > 0) {
    return product.variants.reduce((sum, variant) => sum + variant.stock, 0);
  }
  return product.stock;
}

export function serializeCartRecommendationProduct(product: CartRecommendationProductRow) {
  const price = effectiveProductPrice(product);
  // normalPrice = base price (sebelum diskon apa pun). Untuk produk
  // berVarian, ambil MIN base price; untuk single, product.price.
  const baseMinPrice =
    product.hasVariants && product.variants.length > 0
      ? Math.min(...product.variants.map((v) => v.price))
      : product.price;
  const normalPrice = price < baseMinPrice ? baseMinPrice : null;
  const discountPercent =
    normalPrice && normalPrice > price
      ? Math.round(((normalPrice - price) / normalPrice) * 100)
      : null;

  return {
    id: product.id,
    slug: product.slug,
    name: product.name,
    price,
    normal_price: normalPrice,
    // discount_price = effective price (yang sudah include Promo Toko).
    // Sebelumnya field ini cuma product.discountPrice (legacy Flash Sale).
    discount_price: price < baseMinPrice ? price : null,
    discount_percent: discountPercent,
    image: product.imageUrl,
    stock: effectiveProductStock(product),
    weightGram: product.weightGram,
    rating: product.avgRating,
    sold_count: product.reviewCount,
    hasVariants: product.hasVariants,
    categoryId: product.categoryId,
    categorySlug: product.category?.slug ?? null,
    category: product.category?.name ?? null,
    brand: product.brand?.name ?? null,
    // brandId WAJIB diteruskan — voucherMatchesProduct mencocokkan voucher
    // brand-exclusive lewat product.brandId. Tanpa ini, badge "Brand Eksklusif"
    // hilang di kartu rekomendasi / recently-viewed (bug class sama dgn
    // getProductBySlug jalur non-varian).
    brandId: product.brandId ?? null,
    variantAttrs: product.variantAttrs.map((attr) => ({
      id: attr.id,
      name: attr.name,
      position: attr.position,
      options: attr.options.map((option) => ({
        id: option.id,
        value: option.value,
        position: option.position,
      })),
    })),
    variants: product.variants.map((variant) => ({
      id: variant.id,
      sku: variant.sku,
      price: variant.price,
      stock: variant.stock,
      weightGram: variant.weightGram,
      imageUrl: variant.imageUrl,
      isActive: variant.isActive,
      deletedAt: variant.deletedAt,
      options: variant.options.map((option) => ({ optionId: option.optionId })),
    })),
  };
}
