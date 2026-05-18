/**
 * GET /api/cart/vouchers?subtotal=N
 *
 * Return daftar voucher member Natalo (sourceType=CUSTOMER) untuk user
 * login + cart subtotal saat ini.
 *
 * Aturan visibility (lihat CLAUDE.md - Voucher business rules):
 * - HIDDEN sama sekali kalau: voucher expired / inactive / global max
 *   usage tercapai / user sudah pernah pakai voucher ini
 * - Tampil DISABLED hanya kalau masih mungkin dipakai nanti: subtotal
 *   kurang dari min belanja, voucher belum mulai berlaku, dll
 *
 * Guest dapat 401 — tidak boleh lihat voucher member.
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
  shouldHideVoucher,
  voucherScopeOf,
  voucherTypeOf,
  voucherVisibilityOf,
} from "@/lib/voucher-helpers";
import { isFreeShippingVoucher } from "@/lib/voucher-kind";

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

  // Fetch voucher CUSTOMER yg user-nya berhak (publik atau owned).
  const [vouchers, userUsedOrders, user, successfulOrderCount] = await Promise.all([
    prisma.voucher.findMany({
      where: {
        sourceType: "CUSTOMER",
        OR: [{ userId: null }, { userId: session.sub }],
      },
      orderBy: { createdAt: "desc" },
    }),
    // Voucher code yg user sudah pernah pakai (di slot customer atau manual).
    // Per aturan Natalo: 1 voucher = 1× per user. Voucher yg sudah dipakai
    // di-skip dari daftar.
    prisma.order.findMany({
      where: {
        userId: session.sub,
        OR: [
          { voucherCode: { not: null } },
          { productVoucherCode: { not: null } },
          { shippingVoucherCode: { not: null } },
          { loyaltyVoucherCode: { not: null } },
          { manualVoucherCode: { not: null } },
        ],
        // Order CANCELLED/REFUNDED idealnya tidak count sebagai "sudah
        // pakai" — tapi untuk simplicity & strict-safety, semua order
        // count. Kalau user butuh re-claim setelah cancel, admin bisa
        // unset code di order.
      },
      select: {
        createdAt: true,
        voucherCode: true,
        productVoucherCode: true,
        shippingVoucherCode: true,
        loyaltyVoucherCode: true,
        manualVoucherCode: true,
      },
    }),
    prisma.user.findUnique({
      where: { id: session.sub },
      select: { id: true, createdAt: true },
    }),
    prisma.order.count({
      where: {
        userId: session.sub,
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    }),
  ]);

  const userCtx = {
    isLoggedIn: true,
    userId: session.sub,
    createdAt: user?.createdAt ?? null,
    successfulOrderCount,
  };
  const items: Array<{
    id: string;
    name: string | null;
    code: string;
    description: string | null;
    discountPercent: number | null;
    discountAmount: number | null;
    maxDiscountAmount: number | null;
    minimumOrder: number;
    expiresAt: Date | null;
    sourceType: "CUSTOMER" | "SELLER_MANUAL";
    type: ReturnType<typeof voucherTypeOf>;
    visibility: ReturnType<typeof voucherVisibilityOf>;
    discountScope: ReturnType<typeof voucherScopeOf>;
    discount: number;
    applicable: boolean;
    disabledReason: string | null;
  }> = [];

  for (const v of vouchers) {
    // Aturan visibility: filter out voucher yg permanently invalid
    if (shouldHideVoucher(v, userUsedOrders, now)) continue;

    // Voucher yg lolos masih mungkin dipakai — compute disabled reason
    // untuk transient state (min belanja, dll).
    const disabledReason = getVoucherDisabledReason(v, subtotal, userCtx, now);
    const discount = disabledReason ? 0 : calcVoucherDiscount(subtotal, v);
    const isFreeShipping = isFreeShippingVoucher(v);
    const applicable = disabledReason === null && (discount > 0 || isFreeShipping);

    items.push({
      id: v.id,
      name: v.name,
      code: v.code,
      description: v.description,
      discountPercent: v.discountPercent,
      discountAmount: v.discountAmount,
      maxDiscountAmount: v.maxDiscountAmount,
      minimumOrder: v.minimumOrder,
      expiresAt: v.expiresAt,
      sourceType: v.sourceType,
      type: voucherTypeOf(v),
      visibility: voucherVisibilityOf(v),
      discountScope: voucherScopeOf(v),
      discount,
      applicable,
      disabledReason:
        disabledReason ??
        (!isFreeShipping && discount === 0
          ? "Voucher tidak memberikan potongan untuk pesanan ini"
          : null),
    });
  }

  // Sort: applicable dulu (best discount duluan), lalu disabled
  items.sort((a, b) => {
    if (a.applicable !== b.applicable) return a.applicable ? -1 : 1;
    return b.discount - a.discount;
  });

  return NextResponse.json({
    available: items.filter((it) => it.applicable),
    unavailable: items.filter((it) => !it.applicable),
  });
}
