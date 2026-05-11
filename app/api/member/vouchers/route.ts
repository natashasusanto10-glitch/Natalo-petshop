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

function calcDiscount(
  subtotal: number,
  voucher: { discountPercent: number | null; discountAmount: number | null }
): number {
  let d = 0;
  if (voucher.discountPercent) d += Math.floor((subtotal * voucher.discountPercent) / 100);
  if (voucher.discountAmount) d += voucher.discountAmount;
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
        OR: [{ voucherCode: { not: null } }, { manualVoucherCode: { not: null } }],
      },
      select: { voucherCode: true, manualVoucherCode: true },
    }),
  ]);

  const usedCodes = new Set<string>();
  for (const order of usedOrders) {
    if (order.voucherCode) usedCodes.add(order.voucherCode);
    if (order.manualVoucherCode) usedCodes.add(order.manualVoucherCode);
  }

  // Filter usedCount < maxUsage (column-to-column gak bisa di Prisma where)
  const usable = vouchers.filter(
    (v) =>
      !usedCodes.has(v.code) &&
      (v.maxUsage === null || v.usedCount < v.maxUsage),
  );

  const eligible: Array<{
    code: string;
    description: string | null;
    discount: number;
    discountPercent: number | null;
    discountAmount: number | null;
    minimumOrder: number;
    expiresAt: Date | null;
  }> = [];

  const ineligible: Array<{
    code: string;
    description: string | null;
    discountPercent: number | null;
    discountAmount: number | null;
    minimumOrder: number;
    expiresAt: Date | null;
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
          minimumOrder: v.minimumOrder,
          expiresAt: v.expiresAt,
        });
      }
    } else {
      ineligible.push({
        code: v.code,
        description: v.description,
        discountPercent: v.discountPercent,
        discountAmount: v.discountAmount,
        minimumOrder: v.minimumOrder,
        expiresAt: v.expiresAt,
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
