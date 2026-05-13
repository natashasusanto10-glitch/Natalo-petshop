import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import {
  cartRecommendationProductInclude,
  cartRecommendationWhere,
  serializeCartRecommendationProduct,
} from "@/lib/cart-recommendation-products";

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

  return NextResponse.json({ data });
}
