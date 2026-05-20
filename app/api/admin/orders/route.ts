import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import type { OrderStatus, Prisma } from "@prisma/client";

/**
 * GET /api/admin/orders
 *
 * Query params:
 * - `status` — filter by OrderStatus (PENDING/PAID/PROCESSING/...). Optional.
 * - `q` — search by orderNumber or customerName. Optional.
 * - `limit` — default 50, max 100.
 * - `cursor` — orderId untuk pagination next page.
 *
 * Response: `{orders: [...], nextCursor: string | null}`.
 *
 * Dipakai oleh:
 * - flutter_admin/ (Natalo Admin APK) — orders tab
 * - app/admin/(protected)/orders/ web — bisa migrate ke endpoint ini juga
 */
export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json(
      { error: "Unauthorized — admin session required" },
      { status: 401 },
    );
  }

  const sp = request.nextUrl.searchParams;
  const status = sp.get("status");
  const q = sp.get("q")?.trim() ?? "";
  const limit = Math.min(Math.max(parseInt(sp.get("limit") ?? "50", 10), 1), 100);
  const cursor = sp.get("cursor") ?? undefined;

  const where: Prisma.OrderWhereInput = {};
  if (status && status !== "all") {
    // Validate enum value sebelum query supaya prisma tidak throw.
    const validStatuses: OrderStatus[] = [
      "PENDING",
      "PAID",
      "PROCESSING",
      "READY_FOR_PICKUP",
      "SHIPPED",
      "DELIVERED",
      "CANCELLED",
      "REFUNDED",
    ];
    if (validStatuses.includes(status as OrderStatus)) {
      where.status = status as OrderStatus;
    }
  }
  if (q) {
    where.OR = [
      { orderNumber: { contains: q, mode: "insensitive" } },
      { customerName: { contains: q, mode: "insensitive" } },
      { customerPhone: { contains: q } },
    ];
  }

  const orders = await prisma.order.findMany({
    where,
    take: limit + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    orderBy: { createdAt: "desc" },
    select: {
      id: true,
      orderNumber: true,
      customerName: true,
      customerPhone: true,
      shippingAddress: true,
      shippingCity: true,
      subtotal: true,
      shippingCost: true,
      discount: true,
      total: true,
      status: true,
      paymentStatus: true,
      paymentProvider: true,
      courierCode: true,
      courierService: true,
      trackingNumber: true,
      orderType: true,
      shippingMethod: true,
      createdAt: true,
      items: {
        select: {
          id: true,
          name: true,
          variantLabel: true,
          quantity: true,
          price: true,
        },
      },
    },
  });

  const hasMore = orders.length > limit;
  const page = hasMore ? orders.slice(0, limit) : orders;
  const nextCursor = hasMore ? page[page.length - 1].id : null;

  return NextResponse.json({
    orders: page,
    nextCursor,
  });
}
