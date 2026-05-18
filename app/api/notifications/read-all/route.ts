/**
 * POST /api/notifications/read-all
 *
 * Mark semua notifikasi yang terlihat di Notification Center sebagai dibaca
 * untuk customer yang sedang login. Anonymous user tidak punya read tracking,
 * jadi request dianggap no-op sukses agar tombol Flutter tidak memunculkan
 * error untuk pengunjung.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

function activeDateFilters(now: Date) {
  return [
    { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
    { OR: [{ endsAt: null }, { endsAt: { gte: now } }] },
  ];
}

export async function POST() {
  try {
    const session = await getSession("CUSTOMER");
    const userId = session?.sub ?? null;

    if (!userId) {
      return NextResponse.json({
        ok: true,
        loggedIn: false,
        unreadCount: 0,
        markedCount: 0,
      });
    }

    const now = new Date();
    const since30d = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const [hasPaidOrder, hasRecentOrder] = await Promise.all([
      prisma.order.findFirst({
        where: { userId, paymentStatus: "PAID" },
        select: { id: true },
      }),
      prisma.order.findFirst({
        where: { userId, createdAt: { gte: since30d } },
        select: { id: true },
      }),
    ]);

    const allowedSegments: string[] = ["all"];
    if (hasPaidOrder) allowedSegments.push("members");
    if (hasRecentOrder) allowedSegments.push("active30d");

    const items = await prisma.announcement.findMany({
      where: {
        status: "PUBLISHED",
        AND: [
          ...activeDateFilters(now),
          {
            OR: [
              { targetUserId: null, segment: { in: allowedSegments } },
              { targetUserId: userId },
            ],
          },
        ],
        reads: { none: { userId } },
      },
      select: { id: true },
      take: 50,
    });

    if (items.length > 0) {
      await prisma.announcementRead.createMany({
        data: items.map((item) => ({
          userId,
          announcementId: item.id,
        })),
        skipDuplicates: true,
      });
    }

    return NextResponse.json({
      ok: true,
      loggedIn: true,
      unreadCount: 0,
      markedCount: items.length,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    console.error("[notifications/read-all] crashed:", err);
    return NextResponse.json(
      { ok: false, error: `Gagal mark all read: ${message}` },
      { status: 500 }
    );
  }
}
