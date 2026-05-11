/**
 * GET /api/admin/push/stats
 *
 * Admin-only diagnostic: breakdown jumlah PushSubscription di DB per
 * channel (web / apns / fcm / unknown) × dengan/tanpa userId.
 *
 * Berguna saat broadcast "Semua user" return 0 recipient — bisa kelihatan
 * apakah memang belum ada subscriber sama sekali, atau ada subscriber tapi
 * userId-nya null (subscribed sebelum login → orphan row).
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  try {
    const session = await getSession("ADMIN");
    if (!session || session.role !== "ADMIN") {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // Pull minimum data needed — endpoint prefix + userId presence.
    const rows = await prisma.pushSubscription.findMany({
      select: { endpoint: true, userId: true },
    });

    type Bucket = { total: number; withUser: number; anonymous: number };
    const empty = (): Bucket => ({ total: 0, withUser: 0, anonymous: 0 });
    const byChannel = {
      web: empty(),
      apns: empty(),
      fcm: empty(),
      unknown: empty(),
    };

    for (const r of rows) {
      const channel: keyof typeof byChannel = r.endpoint.startsWith("https://")
        ? "web"
        : r.endpoint.startsWith("apns:")
          ? "apns"
          : r.endpoint.startsWith("fcm:")
            ? "fcm"
            : "unknown";
      byChannel[channel].total++;
      if (r.userId) byChannel[channel].withUser++;
      else byChannel[channel].anonymous++;
    }

    // Distinct userIds (untuk konfirmasi recipientCount segment "all").
    const distinctUserIds = await prisma.pushSubscription.findMany({
      where: { userId: { not: null } },
      select: { userId: true },
      distinct: ["userId"],
    });

    return NextResponse.json({
      ok: true,
      totalRows: rows.length,
      distinctUsersWithSub: distinctUserIds.length,
      anonymousRows: rows.filter((r) => !r.userId).length,
      byChannel,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    console.error("[push-stats] crashed:", err);
    return NextResponse.json(
      { error: `Stats gagal: ${message}` },
      { status: 500 },
    );
  }
}
