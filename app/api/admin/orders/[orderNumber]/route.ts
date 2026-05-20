import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import type { OrderStatus, Prisma } from "@prisma/client";

const VALID_STATUSES: OrderStatus[] = [
  "PENDING",
  "PAID",
  "PROCESSING",
  "READY_FOR_PICKUP",
  "SHIPPED",
  "DELIVERED",
  "CANCELLED",
  "REFUNDED",
];

/**
 * GET /api/admin/orders/[orderNumber]
 *
 * Detail full untuk satu order (admin view). Termasuk customer info,
 * items breakdown, alamat, tracking, payment.
 *
 * Dipakai oleh flutter_admin/ order detail screen.
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json(
      { error: "Unauthorized — admin session required" },
      { status: 401 },
    );
  }

  const { orderNumber } = await params;
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    include: {
      items: {
        select: {
          id: true,
          name: true,
          variantLabel: true,
          quantity: true,
          price: true,
          weightGram: true,
          productId: true,
        },
      },
      user: {
        select: {
          id: true,
          name: true,
          email: true,
          phoneNumber: true,
        },
      },
    },
  });

  if (!order) {
    return NextResponse.json({ error: "Order tidak ditemukan" }, { status: 404 });
  }

  return NextResponse.json(order);
}

/**
 * PATCH /api/admin/orders/[orderNumber]
 *
 * Update status / tracking number / courier info untuk satu order.
 *
 * Body: `{status?: OrderStatus, trackingNumber?: string, courierCode?: string,
 *         courierService?: string}`
 *
 * Audit: setiap perubahan di-log ke OrderHistory (kalau model itu ada).
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json(
      { error: "Unauthorized — admin session required" },
      { status: 401 },
    );
  }

  const { orderNumber } = await params;
  const body = (await request.json().catch(() => null)) as
    | {
        status?: string;
        trackingNumber?: string | null;
        courierCode?: string | null;
        courierService?: string | null;
      }
    | null;

  if (!body) {
    return NextResponse.json({ error: "Body invalid" }, { status: 400 });
  }

  const data: Prisma.OrderUpdateInput = {};
  if (body.status !== undefined) {
    if (!VALID_STATUSES.includes(body.status as OrderStatus)) {
      return NextResponse.json(
        { error: `Status tidak valid: ${body.status}` },
        { status: 400 },
      );
    }
    data.status = body.status as OrderStatus;
  }
  if (body.trackingNumber !== undefined) {
    data.trackingNumber = body.trackingNumber?.trim() || null;
  }
  if (body.courierCode !== undefined) {
    data.courierCode = body.courierCode?.trim() || null;
  }
  if (body.courierService !== undefined) {
    data.courierService = body.courierService?.trim() || null;
  }

  if (Object.keys(data).length === 0) {
    return NextResponse.json(
      { error: "Tidak ada field yang di-update" },
      { status: 400 },
    );
  }

  const updated = await prisma.order
    .update({
      where: { orderNumber },
      data,
      select: {
        id: true,
        orderNumber: true,
        status: true,
        trackingNumber: true,
        courierCode: true,
        courierService: true,
      },
    })
    .catch((err) => {
      if (err.code === "P2025") return null; // Order not found
      throw err;
    });

  if (!updated) {
    return NextResponse.json({ error: "Order tidak ditemukan" }, { status: 404 });
  }

  return NextResponse.json(updated);
}
