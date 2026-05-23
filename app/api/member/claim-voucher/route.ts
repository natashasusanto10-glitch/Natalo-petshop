import { randomBytes } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

// Loyalty tier reward — earn rate 1 poin per Rp20.000 belanja
// (lihat app/api/orders/route.ts: Math.floor(total / 20000)).
//
// Setiap tier voucher punya `minimumOrder` — voucher hanya berlaku saat
// subtotal checkout >= angka tsb. Cegah "voucher Rp150.000 dipakai di
// order Rp50.000" yang merugikan loyalty economy.
const TIERS = [
  {
    points: 20,
    discountAmount: 10000,
    minimumOrder: 150000,
    label: "20 poin -> voucher Rp10.000 (min belanja Rp150.000)",
  },
  {
    points: 50,
    discountAmount: 25000,
    minimumOrder: 300000,
    label: "50 poin -> voucher Rp25.000 (min belanja Rp300.000)",
  },
  {
    points: 75,
    discountAmount: 40000,
    minimumOrder: 500000,
    label: "75 poin -> voucher Rp40.000 (min belanja Rp500.000)",
  },
  {
    points: 100,
    discountAmount: 60000,
    minimumOrder: 700000,
    label: "100 poin -> voucher Rp60.000 (min belanja Rp700.000)",
  },
  {
    points: 200,
    discountAmount: 150000,
    minimumOrder: 1500000,
    label: "200 poin -> voucher Rp150.000 (min belanja Rp1.500.000)",
  },
] as const;

export async function GET() {
  return NextResponse.json({ tiers: TIERS });
}

export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { points: requestedPoints } = await request.json();
  const tier = TIERS.find((t) => t.points === requestedPoints);

  if (!tier) {
    return NextResponse.json({ error: "Tier tidak valid." }, { status: 400 });
  }

  const agg = await prisma.customerPoint.aggregate({
    where: { userId: session.sub },
    _sum: { points: true },
  });
  const totalPoints = agg._sum.points ?? 0;

  if (totalPoints < tier.points) {
    return NextResponse.json(
      { error: `Poin tidak cukup. Kamu punya ${totalPoints} poin.` },
      { status: 400 },
    );
  }

  const code = `POIN-${randomBytes(4).toString("hex").toUpperCase()}`;
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 30);

  const [voucher] = await prisma.$transaction([
    prisma.voucher.create({
      data: {
        code,
        name: "Voucher Reward Poin",
        description: `Voucher tukar poin - ${tier.label}`,
        discountAmount: tier.discountAmount,
        minimumOrder: tier.minimumOrder,
        maxUsage: 1,
        usedCount: 0,
        usageLimitPerUser: 1,
        expiresAt,
        isActive: true,
        userId: session.sub,
        sourceType: "CUSTOMER",
        type: "LOYALTY_POINT_CLAIM",
        // CRITICAL: harus set `kind` explicit. Default Prisma =
        // `PRODUCT_DISCOUNT`, yang bikin loyalty voucher mismatched
        // di `resolveCustomerSlot('loyalty')` di checkout/recalculate
        // → "Voucher tidak bisa digunakan untuk slot ini" saat
        // user explicit re-apply setelah release.
        kind: "LOYALTY_CLAIM",
        visibility: "USER_OWNED",
        discountType: "FIXED_AMOUNT",
        discountScope: "PRODUCT",
      },
    }),
    prisma.customerPoint.create({
      data: {
        userId: session.sub,
        points: -tier.points,
        source: `CLAIM:${code}`,
      },
    }),
  ]);

  return NextResponse.json({
    code: voucher.code,
    discountAmount: tier.discountAmount,
    minimumOrder: tier.minimumOrder,
    expiresAt: voucher.expiresAt,
  });
}
