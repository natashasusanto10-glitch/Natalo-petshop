import type { Prisma } from "@prisma/client";

export const cartRecommendationProductInclude = {
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
};

export type CartRecommendationProductRow = Prisma.ProductGetPayload<{
  include: typeof cartRecommendationProductInclude;
}>;

export function cartRecommendationWhere(excludeIds: string[] = []): Prisma.ProductWhereInput {
  return {
    isActive: true,
    imageUrl: { not: null },
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
    return Math.min(...product.variants.map((variant) => variant.price));
  }
  return product.discountPrice !== null && product.discountPrice < product.price
    ? product.discountPrice
    : product.price;
}

export function effectiveProductStock(product: CartRecommendationProductRow) {
  if (product.hasVariants && product.variants.length > 0) {
    return product.variants.reduce((sum, variant) => sum + variant.stock, 0);
  }
  return product.stock;
}

export function serializeCartRecommendationProduct(product: CartRecommendationProductRow) {
  const price = effectiveProductPrice(product);
  const normalPrice =
    product.discountPrice !== null && product.discountPrice < product.price
      ? product.price
      : product.hasVariants && product.variants.length > 0
        ? Math.max(...product.variants.map((variant) => variant.price))
        : null;
  const discountPercent =
    normalPrice && normalPrice > price ? Math.round(((normalPrice - price) / normalPrice) * 100) : null;

  return {
    id: product.id,
    slug: product.slug,
    name: product.name,
    price,
    normal_price: normalPrice,
    discount_price: product.discountPrice,
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
