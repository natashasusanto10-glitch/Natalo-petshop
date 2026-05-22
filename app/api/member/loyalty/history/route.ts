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

    const rows = await prisma.customerPoint.findMany({
      where: { userId: session.sub },
      orderBy: { createdAt: "desc" },
      take: 100,
      select: {
        id: true,
        points: true,
        source: true,
        createdAt: true,
      },
    });

    const balance = rows.reduce((sum, row) => sum + row.points, 0);
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
