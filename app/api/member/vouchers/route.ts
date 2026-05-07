/**
 * GET /api/member/vouchers?subtotal=XXX
 *
 * Return voucher milik user yang APPLICABLE untuk subtotal saat ini.
 * Sorted by best discount value (descending) — index 0 = paling untung.
 *
 * Filter:
 *   - voucher.userId = current user
 *   - isActive = true
 *   - belum expired (expiresAt null OR > now)
 *   - sudah aktif (startsAt <= now)
 *   - usedCount < maxUsage (atau maxUsage null)
 *   - subtotal >= minimumOrder
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
  const session = await getSession();
  if (!session)
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });

  const sp = request.nextUrl.searchParams;
  const subtotal = Math.max(0, Number(sp.get("subtotal") ?? 0));
  const now = new Date();

  const vouchers = await prisma.voucher.findMany({
    where: {
      userId: session.sub,
      isActive: true,
      startsAt: { lte: now },
      OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      minimumOrder: { lte: subtotal },
    },
    orderBy: { createdAt: "desc" },
  });

  // Filter usedCount < maxUsage (tidak bisa langsung di Prisma where karena column-to-column)
  const applicable = vouchers
    .filter((v) => v.maxUsage === null || v.usedCount < v.maxUsage)
    .map((v) => ({
      code: v.code,
      description: v.description,
      discount: calcDiscount(subtotal, v),
      discountPercent: v.discountPercent,
      discountAmount: v.discountAmount,
      minimumOrder: v.minimumOrder,
      expiresAt: v.expiresAt,
    }))
    .filter((v) => v.discount > 0)
    .sort((a, b) => b.discount - a.discount);

  return NextResponse.json({ vouchers: applicable });
}
