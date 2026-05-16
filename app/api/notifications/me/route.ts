/**
 * GET /api/notifications/me
 *
 * Return list pengumuman (Announcement) yang relevan untuk user yang
 * sedang login, plus unread count. Anonymous user (belum login) tetap
 * dilayani — dapat list segment "all" saja, tanpa unread tracking.
 *
 * Segment filter:
 *   - "all"       → semua user (login & anonymous)
 *   - "members"   → user yang pernah ada Order paymentStatus=PAID
 *   - "active30d" → user yang punya Order dalam 30 hari terakhir
 *
 * Response:
 *   {
 *     ok: true,
 *     loggedIn: boolean,
 *     unreadCount: number,                // 0 kalau anonymous
 *     items: Array<{
 *       id, title, body, url, segment, createdAt, read (boolean)
 *     }>
 *   }
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const MAX_ITEMS = 50;

function extractOrderNumberFromNotification(item: {
  title: string;
  body: string;
  url: string | null;
}) {
  const match = `${item.title} ${item.body} ${item.url ?? ""}`.match(/ORD-[A-Z0-9-]+/i);
  return match?.[0] ?? null;
}

function mapAnnouncement(a: {
  id: string;
  title: string;
  body: string;
  url: string | null;
  segment: string;
  type: string;
  source: string | null;
  eventType: string | null;
  feedPostId: string | null;
  thumbnailUrl: string | null;
  feedStatus: string | null;
  ctaLabel: string | null;
  createdAt: Date;
  reads?: Array<{ readAt: Date }>;
}) {
  const isFeed = a.source === "feed" || a.type === "feed";
  return {
    id: a.id,
    title: a.title,
    body: a.body,
    url: a.url,
    segment: a.segment,
    type: isFeed ? (a.eventType ?? a.type) : a.type,
    category: a.type,
    source: a.source,
    eventType: a.eventType,
    feedPostId: a.feedPostId,
    videoId: a.feedPostId,
    thumbnailUrl: a.thumbnailUrl,
    status: a.feedStatus,
    ctaLabel: a.ctaLabel,
    createdAt: a.createdAt.toISOString(),
    read: (a.reads?.length ?? 0) > 0,
  };
}

export async function GET() {
  try {
    const session = await getSession("CUSTOMER");
    const userId = session?.sub ?? null;
    const now = new Date();
    const activeDateFilters = [
      { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
      { OR: [{ endsAt: null }, { endsAt: { gte: now } }] },
    ];

    // Untuk anonymous: cuma announcement segment "all", tanpa read tracking.
    if (!userId) {
      // Anonymous: cuma announcement broadcast segment "all", tidak punya
      // personal (targetUserId required login).
      const items = await prisma.announcement.findMany({
        where: {
          status: "PUBLISHED",
          AND: activeDateFilters,
          segment: "all",
          targetUserId: null,
        },
        orderBy: { createdAt: "desc" },
        take: MAX_ITEMS,
      });
      return NextResponse.json({
        ok: true,
        loggedIn: false,
        unreadCount: 0,
        items: items.map((a) => mapAnnouncement(a)),
      });
    }

    // Untuk logged-in: cek profile user — apakah qualified jadi "member"
    // (punya order PAID) dan "active30d" (order dalam 30 hari terakhir).
    // 1 query gabungan supaya cepat — pakai Promise.all.
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

    // Pull announcements + per-row read state via LEFT JOIN equivalent.
    // Prisma gak punya LEFT JOIN literal, jadi pakai include reads filtered
    // by userId — kalau ada row reads-nya berarti sudah dibaca.
    //
    // Filter: ambil DUA bucket lalu union:
    // 1. BROADCAST — targetUserId NULL, segment match `allowedSegments`
    // 2. PERSONAL — targetUserId = user ini (mis. order status update)
    const items = await prisma.announcement.findMany({
      where: {
        status: "PUBLISHED",
        AND: [
          ...activeDateFilters,
          {
            OR: [
              { targetUserId: null, segment: { in: allowedSegments } },
              { targetUserId: userId },
            ],
          },
        ],
      },
      orderBy: { createdAt: "desc" },
      take: MAX_ITEMS,
      include: {
        reads: {
          where: { userId },
          select: { readAt: true },
        },
      },
    });

    const mapped = items.map((a) => mapAnnouncement(a));
    const orderNumbers = Array.from(
      new Set(
        mapped
          .map(extractOrderNumberFromNotification)
          .filter((orderNumber): orderNumber is string => Boolean(orderNumber)),
      ),
    );

    const reviewSummaryByOrder = new Map<
      string,
      { totalItems: number; reviewedItems: number; allReviewed: boolean }
    >();

    if (orderNumbers.length > 0) {
      const orders = await prisma.order.findMany({
        where: {
          userId,
          orderNumber: { in: orderNumbers },
        },
        select: {
          orderNumber: true,
          items: {
            select: {
              id: true,
              reviews: {
                where: { status: { not: "DELETED" } },
                select: { id: true },
                take: 1,
              },
            },
          },
        },
      });

      for (const order of orders) {
        const totalItems = order.items.length;
        const reviewedItems = order.items.filter((item) => item.reviews.length > 0).length;
        reviewSummaryByOrder.set(order.orderNumber, {
          totalItems,
          reviewedItems,
          allReviewed: totalItems > 0 && reviewedItems === totalItems,
        });
      }
    }

    const itemsWithReviewSummary = mapped.map((item) => {
      const orderNumber = extractOrderNumberFromNotification(item);
      return {
        ...item,
        reviewSummary: orderNumber ? reviewSummaryByOrder.get(orderNumber) ?? null : null,
      };
    });
    const unreadCount = itemsWithReviewSummary.filter((i) => !i.read).length;

    return NextResponse.json({
      ok: true,
      loggedIn: true,
      unreadCount,
      items: itemsWithReviewSummary,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    console.error("[notifications/me] crashed:", err);
    return NextResponse.json(
      { ok: false, error: `Gagal load notifikasi: ${message}` },
      { status: 500 },
    );
  }
}
