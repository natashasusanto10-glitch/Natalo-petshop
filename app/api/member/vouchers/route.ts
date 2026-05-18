/**
 * GET /api/member/vouchers?subtotal=XXX
 *
 * Return SEMUA voucher milik user, dipisah jadi:
 *   - eligible[]   — sudah memenuhi syarat (subtotal >= minimumOrder), discount > 0
 *   - ineligible[] — milik user tapi belum memenuhi syarat (mis. subtotal kurang)
 *
 * Eligible disort dari discount terbesar ke terkecil — index 0 = paling untung,
 * cocok untuk auto-apply.
 *
 * Filter dasar (untuk kedua list):
 *   - voucher.userId = current user
 *   - isActive = true
 *   - sudah aktif (startsAt <= now)
 *   - belum expired (expiresAt null OR > now)
 *   - usedCount < maxUsage (atau maxUsage null)
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { isFreeShippingVoucher } from "@/lib/voucher-kind";
import { isVoucherUsageLimitReached } from "@/lib/voucher-helpers";

function calcDiscount(
  subtotal: number,
  voucher: {
    discountPercent: number | null;
    discountAmount: number | null;
    maxDiscountAmount?: number | null;
    kind?: string | null;
  }
): number {
  if (isFreeShippingVoucher(voucher)) return 0;
  let d = 0;
  if (voucher.discountPercent) d += Math.floor((subtotal * voucher.discountPercent) / 100);
  if (voucher.discountAmount) d += voucher.discountAmount;
  if (voucher.maxDiscountAmount && voucher.maxDiscountAmount > 0) {
    d = Math.min(d, voucher.maxDiscountAmount);
  }
  return Math.min(d, subtotal);
}

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session)
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });

  const sp = request.nextUrl.searchParams;
  const subtotal = Math.max(0, Number(sp.get("subtotal") ?? 0));
  const now = new Date();

  // Ambil SEMUA voucher milik user yang masih aktif & belum expired (tanpa
  // filter minimumOrder) — biar bisa kasih tau user voucher yang "kurang
  // belanja sekian lagi".
  const [vouchers, usedOrders] = await Promise.all([
    prisma.voucher.findMany({
      where: {
        userId: session.sub,
        sourceType: "CUSTOMER",
        isActive: true,
        startsAt: { lte: now },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: { createdAt: "desc" },
    }),
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
  ]);

  // Filter usedCount < maxUsage (column-to-column gak bisa di Prisma where)
  const usable = vouchers.filter(
    (v) =>
      !isVoucherUsageLimitReached(v, usedOrders, now) &&
      (v.maxUsage === null || v.usedCount < v.maxUsage),
  );

  const eligible: Array<{
    code: string;
    description: string | null;
    discount: number;
    discountPercent: number | null;
    discountAmount: number | null;
    maxDiscountAmount: number | null;
    minimumOrder: number;
    expiresAt: Date | null;
    kind: string;
  }> = [];

  const ineligible: Array<{
    code: string;
    description: string | null;
    discountPercent: number | null;
    discountAmount: number | null;
    maxDiscountAmount: number | null;
    minimumOrder: number;
    expiresAt: Date | null;
    kind: string;
    shortfall: number; // berapa rupiah lagi belanja agar memenuhi minimumOrder
  }> = [];

  for (const v of usable) {
    const meetsMinimum = subtotal >= v.minimumOrder;
    if (meetsMinimum) {
      const discount = calcDiscount(subtotal, v);
      if (discount > 0) {
        eligible.push({
          code: v.code,
          description: v.description,
          discount,
          discountPercent: v.discountPercent,
          discountAmount: v.discountAmount,
          maxDiscountAmount: v.maxDiscountAmount,
          minimumOrder: v.minimumOrder,
          expiresAt: v.expiresAt,
          kind: v.kind,
        });
      } else if (isFreeShippingVoucher(v)) {
        eligible.push({
          code: v.code,
          description: v.description,
          discount,
          discountPercent: v.discountPercent,
          discountAmount: v.discountAmount,
          maxDiscountAmount: v.maxDiscountAmount,
          minimumOrder: v.minimumOrder,
          expiresAt: v.expiresAt,
          kind: v.kind,
        });
      }
    } else {
      ineligible.push({
        code: v.code,
        description: v.description,
        discountPercent: v.discountPercent,
        discountAmount: v.discountAmount,
        maxDiscountAmount: v.maxDiscountAmount,
        minimumOrder: v.minimumOrder,
        expiresAt: v.expiresAt,
        kind: v.kind,
        shortfall: v.minimumOrder - subtotal,
      });
    }
  }

  eligible.sort((a, b) => b.discount - a.discount);
  // Untuk ineligible, urutkan dari yang shortfall paling kecil — paling dekat untuk dipakai
  ineligible.sort((a, b) => a.shortfall - b.shortfall);

  return NextResponse.json({
    // Backwards-compat: field "vouchers" tetap return eligible saja agar
    // konsumen lama tidak break.
    vouchers: eligible,
    eligible,
    ineligible,
  });
}
