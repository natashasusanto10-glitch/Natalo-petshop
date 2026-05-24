/**
 * GET /api/member/refund-cases/[id]
 *
 * Return detail refund case lengkap untuk display di halaman detail
 * refund Flutter.
 *
 * Auth: harus login + case.userId === session.sub (user cuma boleh
 * lihat refund miliknya sendiri).
 *
 * Response:
 * {
 *   case: {
 *     id, reason, amount, status, adminNote,
 *     voucherAllocations: { code: amount } | null,
 *     saldoAllocation: ... | null,
 *     createdAt, approvedAt, creditedAt,
 *   },
 *   order: {
 *     id, orderNumber, status, subtotal, total, productDiscount, shippingDiscount,
 *     refundBalanceUsed, createdAt,
 *   },
 *   item: {       // null kalau whole-order refund (orderItemId null)
 *     id, name, variantLabel, price, quantity, lineTotal,
 *   } | null,
 *   admin: {      // info admin yang issue refund (untuk display)
 *     name,
 *   } | null,
 * }
 *
 * 404 kalau case tidak ada / bukan milik user.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "LOGIN_REQUIRED", message: "Login dulu untuk lihat detail refund." },
      { status: 401 },
    );
  }

  const { id } = await params;

  const refundCase = await prisma.refundCase.findUnique({
    where: { id },
    include: {
      order: {
        select: {
          id: true,
          orderNumber: true,
          status: true,
          subtotal: true,
          total: true,
          productDiscount: true,
          shippingDiscount: true,
          refundBalanceUsed: true,
          createdAt: true,
        },
      },
      orderItem: {
        select: {
          id: true,
          name: true,
          variantLabel: true,
          price: true,
          quantity: true,
        },
      },
    },
  });

  if (!refundCase || refundCase.userId !== session.sub) {
    // 404 untuk both "not found" dan "wrong user" — security best practice
    // (don't leak existence of refund case kalau bukan milik user).
    return NextResponse.json(
      { error: "NOT_FOUND", message: "Refund tidak ditemukan." },
      { status: 404 },
    );
  }

  // Admin attribution — TAMPILKAN SEBAGAI BRAND, bukan nama individual.
  // Customer-facing surface harus konsisten "— Natalo Petshop", bukan
  // nama admin tertentu (e.g. "Natasha") karena:
  //   1. Brand consistency — customer komunikasi dengan toko, bukan
  //      staff perseorangan.
  //   2. Privacy — nama admin internal tidak perlu di-expose ke customer.
  //   3. Continuity — staff bisa rotasi, brand fixed.
  // Tetap nullable kalau gak ada createdByAdminId (system-generated /
  // legacy refund) supaya UI bisa skip signature line.
  const admin: { name: string } | null = refundCase.createdByAdminId
    ? { name: "Natalo Petshop" }
    : null;

  return NextResponse.json({
    case: {
      id: refundCase.id,
      reason: refundCase.reason,
      amount: refundCase.amount,
      status: refundCase.status,
      adminNote: refundCase.adminNote,
      voucherAllocations: refundCase.voucherAllocations ?? null,
      saldoAllocation: refundCase.saldoAllocation ?? null,
      destination: refundCase.destination,
      createdAt: refundCase.createdAt.toISOString(),
      approvedAt: refundCase.approvedAt?.toISOString() ?? null,
      creditedAt: refundCase.creditedAt?.toISOString() ?? null,
    },
    order: {
      id: refundCase.order.id,
      orderNumber: refundCase.order.orderNumber,
      status: refundCase.order.status,
      subtotal: refundCase.order.subtotal,
      total: refundCase.order.total,
      productDiscount: refundCase.order.productDiscount,
      shippingDiscount: refundCase.order.shippingDiscount,
      refundBalanceUsed: refundCase.order.refundBalanceUsed,
      createdAt: refundCase.order.createdAt.toISOString(),
    },
    item: refundCase.orderItem
      ? {
          id: refundCase.orderItem.id,
          name: refundCase.orderItem.name,
          variantLabel: refundCase.orderItem.variantLabel,
          price: refundCase.orderItem.price,
          quantity: refundCase.orderItem.quantity,
          lineTotal: refundCase.orderItem.price * refundCase.orderItem.quantity,
        }
      : null,
    admin,
  });
}
