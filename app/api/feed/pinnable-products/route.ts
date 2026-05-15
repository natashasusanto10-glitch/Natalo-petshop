import { NextResponse } from "next/server";
import type { OrderStatus } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const VALID_ORDER_STATUSES: OrderStatus[] = ["DELIVERED"];

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Login dulu." }, { status: 401 });
  }

  const orderItems = await prisma.orderItem.findMany({
    where: {
      order: {
        userId: session.sub,
        paymentStatus: "PAID",
        status: { in: VALID_ORDER_STATUSES },
      },
    },
    select: {
      productId: true,
      orderId: true,
    },
    take: 300,
  });

  const orderIds = [...new Set(orderItems.map((item) => item.orderId))];
  const productIds = [...new Set(orderItems.map((item) => item.productId))];

  const [orders, productRows] = await Promise.all([
    prisma.order.findMany({
      where: { id: { in: orderIds } },
      select: {
        id: true,
        createdAt: true,
        orderNumber: true,
      },
    }),
    prisma.product.findMany({
      where: { id: { in: productIds } },
      select: {
        id: true,
        slug: true,
        name: true,
        price: true,
        discountPrice: true,
        stock: true,
        imageUrl: true,
        avgRating: true,
        reviewCount: true,
      },
    }),
  ]);

  const orderById = new Map(orders.map((order) => [order.id, order]));
  const productById = new Map(productRows.map((product) => [product.id, product]));

  const seen = new Set<string>();
  const products = orderItems
    .map((item) => ({
      item,
      order: orderById.get(item.orderId) ?? null,
      product: productById.get(item.productId) ?? null,
    }))
    .filter((row) => row.order && row.product)
    .sort((a, b) => {
      const left = a.order?.createdAt.getTime() ?? 0;
      const right = b.order?.createdAt.getTime() ?? 0;
      return right - left;
    })
    .filter((row) => {
      if (seen.has(row.item.productId)) return false;
      seen.add(row.item.productId);
      return true;
    })
    .map((row) => ({
      productId: row.product!.id,
      slug: row.product!.slug,
      name: row.product!.name,
      imageUrl: row.product!.imageUrl,
      price: row.product!.discountPrice ?? row.product!.price,
      originalPrice: row.product!.price,
      stock: row.product!.stock,
      avgRating: row.product!.avgRating,
      reviewCount: row.product!.reviewCount,
      purchasedAt: row.order!.createdAt.toISOString(),
      orderNumber: row.order!.orderNumber,
    }));

  return NextResponse.json({ products });
}
