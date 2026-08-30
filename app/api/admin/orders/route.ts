import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import type { OrderStatus, Prisma } from "@prisma/client";
import { orderSearchWhere } from "@/lib/admin-search";

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
    // Support comma-separated multi-status (mis. "PAID,PROCESSING,READY_FOR_PICKUP")
    // supaya satu tab bisa cover beberapa status yang semantically sama.
    // Tab "Perlu Kirim" di mobile butuh ini karena order yang sudah dibayar
    // bisa di status PAID (baru bayar) atau PROCESSING (admin sedang siapkan)
    // atau READY_FOR_PICKUP — semua butuh perhatian admin untuk dikirim.
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
    const requested = status
      .split(",")
      .map((s) => s.trim().toUpperCase())
      .filter((s) => validStatuses.includes(s as OrderStatus)) as OrderStatus[];
    if (requested.length === 1) {
      where.status = requested[0];
    } else if (requested.length > 1) {
      where.status = { in: requested };
    }
    // Kalau requested kosong (semua invalid) → tidak filter — sama dengan
    // perilaku lama tapi sekarang strict: status mismatch sengaja
    // di-treat sebagai "no filter" daripada throw 500.
  }
  // Token-based: "santoso budi" ketemu "Budi Santoso", dan nomor pesanan
  // ber-tanda-hubung ("INV-20260728-001") tetap cocok walau admin hanya
  // mengetik sebagian potongannya.
  const searchWhere = orderSearchWhere(q);
  if (searchWhere) where.AND = searchWhere.AND;

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
