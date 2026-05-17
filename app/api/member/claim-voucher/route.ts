import { randomBytes } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const TIERS = [
  { points: 50, discountAmount: 5000, label: "50 poin -> voucher Rp5.000" },
  { points: 100, discountAmount: 10000, label: "100 poin -> voucher Rp10.000" },
  { points: 200, discountAmount: 20000, label: "200 poin -> voucher Rp20.000" },
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
        description: `Voucher tukar poin - ${tier.label}`,
        discountAmount: tier.discountAmount,
        minimumOrder: 0,
        maxUsage: 1,
        usedCount: 0,
        expiresAt,
        isActive: true,
        userId: session.sub,
        sourceType: "CUSTOMER",
        kind: "LOYALTY_CLAIM",
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
    expiresAt: voucher.expiresAt,
  });
}
