/**
 * GET /api/cart/vouchers?subtotal=N
 *
 * Return daftar voucher member Natalo (sourceType=CUSTOMER) untuk user
 * login + cart subtotal saat ini, lengkap dgn applicable status.
 *
 * Sesuai aturan: voucher Natalo HANYA untuk member login. Guest dapat
 * 401 — tidak boleh lihat / klaim voucher member.
 *
 * SELLER_MANUAL voucher TIDAK pernah muncul di endpoint ini (rahasia,
 * harus di-validate via /api/cart/vouchers/validate-private).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  calcVoucherDiscount,
  getVoucherDisabledReason,
} from "@/lib/voucher-helpers";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      {
        error: "LOGIN_REQUIRED",
        message: "Login dulu untuk melihat voucher member.",
      },
      { status: 401 },
    );
  }

  const subtotalRaw = request.nextUrl.searchParams.get("subtotal");
  const subtotal = Math.max(0, parseInt(subtotalRaw ?? "0", 10) || 0);

  const now = new Date();
  // Voucher member = sourceType CUSTOMER, baik publik admin promo
  // (userId=null) maupun voucher claim user (userId=session.sub).
  // Per aturan Natalo: keduanya butuh login.
  const vouchers = await prisma.voucher.findMany({
    where: {
      sourceType: "CUSTOMER",
      OR: [{ userId: null }, { userId: session.sub }],
    },
    orderBy: { createdAt: "desc" },
  });

  const userCtx = { isLoggedIn: true, userId: session.sub };
  const items = vouchers.map((v) => {
    const disabledReason = getVoucherDisabledReason(v, subtotal, userCtx, now);
    const discount = disabledReason ? 0 : calcVoucherDiscount(subtotal, v);
    return {
      id: v.id,
      code: v.code,
      description: v.description,
      discountPercent: v.discountPercent,
      discountAmount: v.discountAmount,
      minimumOrder: v.minimumOrder,
      expiresAt: v.expiresAt,
      sourceType: v.sourceType,
      discount,
      applicable: disabledReason === null && discount > 0,
      disabledReason:
        disabledReason ??
        (discount === 0 && !v.maxUsage
          ? "Voucher tidak memberikan potongan untuk pesanan ini"
          : null),
    };
  });

  // Sort: applicable dulu, lalu non-applicable
  items.sort((a, b) => {
    if (a.applicable !== b.applicable) return a.applicable ? -1 : 1;
    return b.discount - a.discount;
  });

  return NextResponse.json({
    available: items.filter((it) => it.applicable),
    unavailable: items.filter((it) => !it.applicable),
  });
}
