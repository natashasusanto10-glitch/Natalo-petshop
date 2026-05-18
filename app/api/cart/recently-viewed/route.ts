import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { sampleProducts } from "@/lib/sample-data";
import {
  cartRecommendationProductInclude,
  cartRecommendationWhere,
  serializeCartRecommendationProduct,
} from "@/lib/cart-recommendation-products";
import { attachPublicProductVoucherPreviews } from "@/lib/product-vouchers";

function parseIds(value: string | null) {
  return (value ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean)
    .slice(0, 50);
}

function unique(values: string[]) {
  return values.filter((value, index, list) => list.indexOf(value) === index);
}

function serializeSampleProduct(product: (typeof sampleProducts)[number]) {
  const price =
    product.discountPrice !== null && product.discountPrice < product.price
      ? product.discountPrice
      : product.price;
  const normalPrice =
    product.discountPrice !== null && product.discountPrice < product.price ? product.price : null;

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
    categoryId: null,
    categorySlug: null,
    category: null,
    brand: null,
    variantAttrs: [],
    variants: [],
  };
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const limit = Math.min(Math.max(Number(searchParams.get("limit") ?? 10) || 10, 1), 10);
  const clientIds = parseIds(searchParams.get("ids"));
  const excludeIds = parseIds(searchParams.get("exclude"));
  const session = await getSession("CUSTOMER").catch(() => null);
  let storedIds: string[] = [];

  if (session?.sub) {
    try {
      const rows = await prisma.$queryRaw<{ product_id: string }[]>`
        SELECT "product_id"
        FROM "user_product_views"
        WHERE "user_id" = ${session.sub}
        ORDER BY "viewed_at" DESC
        LIMIT 30
      `;
      storedIds = rows.map((row) => row.product_id);
    } catch {
      storedIds = [];
    }
  }

  const productIds = unique([...storedIds, ...clientIds]).filter((id) => !excludeIds.includes(id));
  if (productIds.length === 0) {
    return NextResponse.json({ data: [] });
  }

  const products = await prisma.product.findMany({
    where: {
      ...cartRecommendationWhere(excludeIds),
      id: { in: productIds },
    },
    include: cartRecommendationProductInclude,
  });
  const order = new Map(productIds.map((id, index) => [id, index]));
  const data = products
    .sort((a, b) => (order.get(a.id) ?? 999) - (order.get(b.id) ?? 999))
    .slice(0, limit)
    .map(serializeCartRecommendationProduct);
  const foundIds = new Set(data.map((product) => product.id));
  const sampleData =
    data.length < limit
      ? productIds
          .filter((id) => !foundIds.has(id))
          .map((id) => sampleProducts.find((product) => product.id === id))
          .filter((product): product is (typeof sampleProducts)[number] => Boolean(product))
          .filter((product) => product.stock > 0 && product.imageUrl)
          .map(serializeSampleProduct)
      : [];

  const withVoucherPreview = await attachPublicProductVoucherPreviews(
    [...data, ...sampleData].slice(0, limit),
  );

  return NextResponse.json({ data: withVoucherPreview });
}
