import { randomBytes } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

/// Thrown di dalam txn kalau poin tidak cukup saat re-check authoritative.
/// Di-catch di luar untuk return 400 friendly (bukan 500).
class InsufficientPointsError extends Error {
  constructor(readonly available: number) {
    super("insufficient_points");
  }
}

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

  // Fast-path check (UX) — hindari buat transaction kalau jelas-jelas
  // poin kurang. BUKAN authoritative; re-check di dalam txn Serializable
  // di bawah yang jadi source of truth.
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

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 30);

  // CRITICAL FIX (write-skew race): CustomerPoint adalah ledger
  // append-only (tidak ada balance row tunggal untuk di-guard via
  // updateMany). Tanpa Serializable, 2 request concurrent dengan poin
  // pas-pasan dua-duanya lolos aggregate-check lalu dua-duanya insert
  // -points → saldo negatif + 2 voucher gratis. Serializable bikin
  // Postgres detect write-skew → 1 txn fail dengan 40001, kita retry
  // sampai 3x (claim jarang, kontensi rendah). Re-check di DALAM txn
  // = authoritative balance gate.
  const code = `POIN-${randomBytes(4).toString("hex").toUpperCase()}`;
  const maxAttempts = 3;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      const voucher = await prisma.$transaction(
        async (tx) => {
          const inner = await tx.customerPoint.aggregate({
            where: { userId: session.sub },
            _sum: { points: true },
          });
          const balance = inner._sum.points ?? 0;
          if (balance < tier.points) {
            throw new InsufficientPointsError(balance);
          }
          await tx.customerPoint.create({
            data: {
              userId: session.sub,
              points: -tier.points,
              source: `CLAIM:${code}`,
            },
          });
          return tx.voucher.create({
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
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );

      return NextResponse.json({
        code: voucher.code,
        discountAmount: tier.discountAmount,
        minimumOrder: tier.minimumOrder,
        expiresAt: voucher.expiresAt,
      });
    } catch (err) {
      if (err instanceof InsufficientPointsError) {
        return NextResponse.json(
          { error: `Poin tidak cukup. Kamu punya ${err.available} poin.` },
          { status: 400 },
        );
      }
      // Serialization failure (40001) — retry. Kalau attempt terakhir,
      // jatuh ke return error di bawah loop.
      const isSerialization =
        err instanceof Prisma.PrismaClientKnownRequestError &&
        err.code === "P2034";
      if (!isSerialization || attempt === maxAttempts - 1) {
        if (isSerialization) {
          return NextResponse.json(
            { error: "Sistem sibuk, coba lagi sebentar." },
            { status: 409 },
          );
        }
        throw err;
      }
      // else: loop retry
    }
  }

  // Unreachable secara normal (loop selalu return), tapi TS perlu ini.
  return NextResponse.json(
    { error: "Gagal klaim voucher. Coba lagi." },
    { status: 500 },
  );
}
