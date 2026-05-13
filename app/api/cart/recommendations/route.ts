import { NextRequest, NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { sampleProducts } from "@/lib/sample-data";
import {
  cartRecommendationProductInclude,
  cartRecommendationWhere,
  serializeCartRecommendationProduct,
  type CartRecommendationProductRow,
} from "@/lib/cart-recommendation-products";

function parseIds(value: string | null) {
  return (value ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean)
    .slice(0, 100);
}

function pushUnique(
  target: CartRecommendationProductRow[],
  products: CartRecommendationProductRow[],
  seen: Set<string>,
) {
  for (const product of products) {
    if (seen.has(product.id)) continue;
    seen.add(product.id);
    target.push(product);
  }
}

function sampleRecommendations(excludeIds: string[], limit: number) {
  return sampleProducts
    .filter((product) => (product as { isActive?: boolean }).isActive !== false)
    .filter((product) => product.stock > 0 && product.imageUrl)
    .filter((product) => !excludeIds.includes(product.id))
    .slice(0, limit)
    .map((product) => {
      const price =
        product.discountPrice !== null && product.discountPrice < product.price
          ? product.discountPrice
          : product.price;
      const normalPrice =
        product.discountPrice !== null && product.discountPrice < product.price
          ? product.price
          : null;
      return {
        id: product.id,
        slug: product.slug,
        name: product.name,
        price,
        normal_price: normalPrice,
        discount_price: product.discountPrice,
        discount_percent:
          normalPrice && normalPrice > price
            ? Math.round(((normalPrice - price) / normalPrice) * 100)
            : null,
        image: product.imageUrl,
        stock: product.stock,
        weightGram: product.weightGram,
        rating: product.avgRating,
        sold_count: product.reviewCount,
        hasVariants: product.hasVariants,
        category: null,
        brand: null,
        variantAttrs: [],
        variants: [],
      };
    });
}

async function getManualRuleIds(sourceIds: string[], limit: number) {
  if (sourceIds.length === 0) return [];
  try {
    const rows = await prisma.$queryRaw<{ recommended_product_id: string }[]>(Prisma.sql`
      SELECT "recommended_product_id"
      FROM "product_recommendation_rules"
      WHERE "is_active" = true
        AND "source_product_id" IN (${Prisma.join(sourceIds)})
      ORDER BY "priority" DESC, "created_at" DESC
      LIMIT ${limit}
    `);
    return rows.map((row) => row.recommended_product_id);
  } catch {
    return [];
  }
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const limit = Math.min(Math.max(Number(searchParams.get("limit") ?? 10) || 10, 1), 10);
  const excludeIds = parseIds(searchParams.get("exclude"));
  const cartIds = parseIds(searchParams.get("cart"));
  const take = limit + 1;
  const session = await getSession("CUSTOMER").catch(() => null);
  const seen = new Set(excludeIds);
  const products: CartRecommendationProductRow[] = [];

  const sourceProducts =
    cartIds.length > 0
      ? await prisma.product.findMany({
          where: { id: { in: cartIds } },
          select: { id: true, categoryId: true, brandId: true },
        })
      : [];
  const categoryIds = sourceProducts
    .map((product) => product.categoryId)
    .filter((id): id is string => Boolean(id));
  const brandIds = sourceProducts
    .map((product) => product.brandId)
    .filter((id): id is string => Boolean(id));

  const ruleIds = await getManualRuleIds(cartIds, take * 2);
  if (ruleIds.length > 0) {
    const manualProducts = await prisma.product.findMany({
      where: { AND: [cartRecommendationWhere(excludeIds), { id: { in: ruleIds } }] },
      include: cartRecommendationProductInclude,
    });
    const order = new Map(ruleIds.map((id, index) => [id, index]));
    pushUnique(
      products,
      manualProducts.sort((a, b) => (order.get(a.id) ?? 999) - (order.get(b.id) ?? 999)),
      seen,
    );
  }

  if (products.length < take && (categoryIds.length > 0 || brandIds.length > 0)) {
    const complementary = await prisma.product.findMany({
      where: {
        AND: [
          cartRecommendationWhere([...seen]),
          {
            OR: [
              ...(categoryIds.length > 0 ? [{ categoryId: { in: categoryIds } }] : []),
              ...(brandIds.length > 0 ? [{ brandId: { in: brandIds } }] : []),
            ],
          },
        ],
      },
      orderBy: [{ reviewCount: "desc" }, { avgRating: "desc" }, { createdAt: "desc" }],
      take: take - products.length,
      include: cartRecommendationProductInclude,
    });
    pushUnique(products, complementary, seen);
  }

  if (products.length < take && session?.sub) {
    const purchasedItems = await prisma.orderItem.findMany({
      where: { order: { userId: session.sub } },
      orderBy: { id: "desc" },
      take: 60,
      include: { product: { select: { categoryId: true, brandId: true } } },
    });
    const purchasedCategoryIds = purchasedItems
      .map((item) => item.product.categoryId)
      .filter((id): id is string => Boolean(id));
    const purchasedBrandIds = purchasedItems
      .map((item) => item.product.brandId)
      .filter((id): id is string => Boolean(id));

    if (purchasedCategoryIds.length > 0 || purchasedBrandIds.length > 0) {
      const personalProducts = await prisma.product.findMany({
        where: {
          AND: [
            cartRecommendationWhere([...seen]),
            {
              OR: [
                ...(purchasedCategoryIds.length > 0
                  ? [{ categoryId: { in: purchasedCategoryIds } }]
                  : []),
                ...(purchasedBrandIds.length > 0 ? [{ brandId: { in: purchasedBrandIds } }] : []),
              ],
            },
          ],
        },
        orderBy: [{ reviewCount: "desc" }, { avgRating: "desc" }, { createdAt: "desc" }],
        take: take - products.length,
        include: cartRecommendationProductInclude,
      });
      pushUnique(products, personalProducts, seen);
    }
  }

  if (products.length < take) {
    const fallback = await prisma.product.findMany({
      where: cartRecommendationWhere([...seen]),
      orderBy: [{ reviewCount: "desc" }, { avgRating: "desc" }, { createdAt: "desc" }],
      take: take - products.length,
      include: cartRecommendationProductInclude,
    });
    pushUnique(products, fallback, seen);
  }

  const page = products.slice(0, limit);
  if (page.length === 0) {
    return NextResponse.json({
      data: sampleRecommendations(excludeIds, limit),
      next_cursor: null,
      has_more: false,
    });
  }

  return NextResponse.json({
    data: page.map(serializeCartRecommendationProduct),
    next_cursor: products.length > limit ? page.at(-1)?.id ?? null : null,
    has_more: products.length > limit,
  });
}
