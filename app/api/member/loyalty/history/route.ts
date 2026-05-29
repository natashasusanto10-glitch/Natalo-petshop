import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

function describeSource(source: string, points: number) {
  if (source.startsWith("ORDER:")) {
    const orderNumber = source.replace(/^ORDER:/, "");
    return `Bonus belanja - Order #${orderNumber}`;
  }
  if (source.startsWith("CLAIM:")) {
    const code = source.replace(/^CLAIM:/, "");
    return `Tukar poin -> Voucher ${code}`;
  }
  if (source.startsWith("REVIEW:")) {
    return "Bonus ulasan produk";
  }
  if (points > 0) return source || "Bonus poin";
  if (points < 0) return source || "Pemakaian poin";
  return source || "Aktivitas poin";
}

export async function GET() {
  try {
    const session = await getSession("CUSTOMER");
    // Admin (privilege elevation) bisa pakai loyalty juga.
    if (!session) {
      return NextResponse.json({ error: "Login dulu." }, { status: 401 });
    }

    // Fetch entries (latest 100 untuk display) + total balance (aggregate
    // semua rows) PARALLEL. Sebelumnya `balance` di-hitung dari rows
    // limit-100 → kalau user punya >100 transaction, balance miss row
    // lama. Aggregate query langsung di DB level lebih akurat + ringan
    // (index userId, COUNT/SUM O(log n)). Clamp Math.max(0, ...) defensive
    // negative balance kalau ada bug claim duplicate.
    const [rows, balanceAgg] = await Promise.all([
      prisma.customerPoint.findMany({
        where: { userId: session.sub },
        orderBy: { createdAt: "desc" },
        take: 100,
        select: {
          id: true,
          points: true,
          source: true,
          createdAt: true,
        },
      }),
      prisma.customerPoint.aggregate({
        where: { userId: session.sub },
        _sum: { points: true },
      }),
    ]);

    const balance = Math.max(0, balanceAgg._sum.points ?? 0);
    const entries = rows.map((row) => ({
      id: row.id,
      delta: row.points,
      points: row.points,
      source: row.source,
      description: describeSource(row.source, row.points),
      createdAt: row.createdAt.toISOString(),
    }));

    return NextResponse.json({
      ok: true,
      balance,
      entries,
      history: entries,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    console.error("[member/loyalty/history] crashed:", err);
    return NextResponse.json(
      { ok: false, error: `Gagal load riwayat poin: ${message}` },
      { status: 500 },
    );
  }
}
