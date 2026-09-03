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
import { announcementAudienceWhere } from "@/lib/notification-audience";
import { signBunnyUrl } from "@/lib/feed/bunny";
import {
  resolveNotificationActor,
  notificationActorLabels,
  fillNotificationActorTokens,
} from "@/lib/social/brand-user";

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
  actorAvatarUrl: string | null;
  actorName: string | null;
  actorAvatarUrls: string[];
  actorId: string | null;
  aggregatedCount: number | null;
  feedStatus: string | null;
  commentId: string | null;
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
    thumbnailUrl: signBunnyUrl(a.thumbnailUrl) ?? null,
    actorAvatarUrl: a.actorAvatarUrl,
    actorName: a.actorName,
    actorAvatarUrls: a.actorAvatarUrls,
    actorId: a.actorId,
    aggregatedCount: a.aggregatedCount,
    status: a.feedStatus,
    commentId: a.commentId,
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
      // Broadcast "all" tak punya token aktor, tapi fill defensif memastikan
      // token tak pernah bocor mentah ke klien (fallback "Seseorang").
      const anonLabels = notificationActorLabels(null);
      return NextResponse.json({
        ok: true,
        loggedIn: false,
        unreadCount: 0,
        items: items.map((a) => {
          const m = mapAnnouncement(a);
          return {
            ...m,
            title: fillNotificationActorTokens(m.title, anonLabels),
            body: fillNotificationActorTokens(m.body, anonLabels),
          };
        }),
      });
    }

    // Untuk logged-in: cek profile user — apakah qualified jadi "member"
    // (punya order PAID) dan "active30d" (order dalam 30 hari terakhir).
    // 1 query gabungan supaya cepat — pakai Promise.all.
    const since30d = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const [hasPaidOrder, hasRecentOrder, viewer] = await Promise.all([
      prisma.order.findFirst({
        where: { userId, paymentStatus: "PAID" },
        select: { id: true },
      }),
      prisma.order.findFirst({
        where: { userId, createdAt: { gte: since30d } },
        select: { id: true },
      }),
      prisma.user.findUnique({
        where: { id: userId },
        select: { createdAt: true },
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
          // Broadcast dibatasi sejak akun lahir; personal tanpa batas.
          // Aturannya + alasannya hidup di lib/notification-audience.ts
          // (bertes) — jangan tulis ulang klausanya di sini.
          announcementAudienceWhere({
            userId,
            allowedSegments,
            viewerCreatedAt: viewer?.createdAt ?? null,
          }),
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

    // Status like komentar milik user ini untuk notif komentar (feed_new_comment
    // / mention / reply). Tanpa ini, tombol love di baris notifikasi selalu
    // mulai kosong walau komentarnya sudah di-like di sheet komentar.
    const commentIds = Array.from(
      new Set(
        mapped
          .map((item) => item.commentId)
          .filter((id): id is string => Boolean(id && id.trim())),
      ),
    );
    const likedCommentIds = new Set<string>();
    if (commentIds.length > 0) {
      const likes = await prisma.feedCommentLike.findMany({
        where: { userId, commentId: { in: commentIds } },
        select: { commentId: true },
      });
      for (const like of likes) likedCommentIds.add(like.commentId);
    }

    // Status follow-balik untuk notif "user_followed" (pill "Ikuti"/
    // "Mengikuti" di app). Tanpa ini, pill selalu mulai "Ikuti" walau
    // viewer sudah follow-balik actor-nya — baru benar setelah di-tap
    // (lihat notifications_screen.dart _NotificationFollowBackPill).
    const followActorIds = Array.from(
      new Set(
        mapped
          .filter((item) => item.eventType === "user_followed")
          .map((item) => item.actorId)
          .filter((id): id is string => Boolean(id && id.trim())),
      ),
    );
    const followingActorIds = new Set<string>();
    if (followActorIds.length > 0) {
      const follows = await prisma.userFollow.findMany({
        where: { followerId: userId, followingId: { in: followActorIds } },
        select: { followingId: true },
      });
      for (const follow of follows) followingActorIds.add(follow.followingId);
    }

    // Keberadaan postingan untuk notif ber-feedPostId (Postingan baru,
    // komentar, like, mention, dll). Baris FeedPost HILANG = postingan
    // dihapus → app redupkan baris + label "Sudah dihapus" + matikan tap
    // (Lapisan 2, notifications_screen.dart). Cek keberadaan saja (bukan
    // status ACTIVE): post hidden/pending masih ADA (tak "dihapus"),
    // visibilitasnya diurus jalur buka-postingan (Lapisan 1 toast).
    const feedPostIds = Array.from(
      new Set(
        mapped
          .map((item) => item.feedPostId)
          .filter((id): id is string => Boolean(id && id.trim())),
      ),
    );
    const existingPostIds = new Set<string>();
    if (feedPostIds.length > 0) {
      // Filter `deletedAt: null` — post yang di-soft-delete owner (row masih
      // ada, deletedAt terisi) DIANGGAP tak ada di sini supaya notif lama yang
      // belum ke-cascade tetap tampil "Sudah dihapus". Post baru yang dihapus
      // kini di-cascade (baris notif hilang total, lihat DELETE handler), jadi
      // ini jala pengaman untuk data lama + kasus lomba.
      const posts = await prisma.feedPost.findMany({
        where: { id: { in: feedPostIds }, deletedAt: null },
        select: { id: true },
      });
      for (const post of posts) existingPostIds.add(post.id);
    }

    // Identitas aktor LIVE — avatar/nama diambil dari record User terkini
    // (via actorId) supaya ganti/hapus foto profil langsung sinkron di notif
    // lama. Snapshot di baris hanya fallback (notif lama tanpa actorId /
    // user terhapus / baris agregat). Brand-safe lewat resolveNotificationActor.
    const actorIds = Array.from(
      new Set(
        mapped
          .map((item) => item.actorId)
          .filter((id): id is string => Boolean(id && id.trim())),
      ),
    );
    const liveActorById = new Map<
      string,
      {
        role: string | null;
        name: string | null;
        username: string | null;
        profilePhotoUrl: string | null;
      }
    >();
    if (actorIds.length > 0) {
      const actors = await prisma.user.findMany({
        where: { id: { in: actorIds } },
        select: {
          id: true,
          role: true,
          name: true,
          username: true,
          profilePhotoUrl: true,
        },
      });
      for (const a of actors) {
        liveActorById.set(a.id, {
          role: a.role,
          name: a.name,
          username: a.username,
          profilePhotoUrl: a.profilePhotoUrl,
        });
      }
    }

    const itemsWithReviewSummary = mapped.map((item) => {
      const orderNumber = extractOrderNumberFromNotification(item);
      const liveUser = item.actorId
        ? liveActorById.get(item.actorId) ?? null
        : null;
      const liveActor = resolveNotificationActor({
        actorId: item.actorId,
        // Baris agregat like membawa avatar bertumpuk di actorAvatarUrls;
        // identitas aktor tunggal memang null → jangan diisi 1 avatar live.
        // Kontrak agregat = aggregatedCount (spec Keputusan 9). Fallback
        // panjang actorAvatarUrls utk baris like LAMA pra-migration yang
        // aggregatedCount-nya null tapi sudah agregat.
        isAggregate:
          (item.aggregatedCount ?? 0) > 1 ||
          (item.actorAvatarUrls?.length ?? 0) > 0,
        snapshot: { actorName: item.actorName, actorAvatarUrl: item.actorAvatarUrl },
        liveUser,
      });
      // Ganti token nama/username di judul/body dengan nilai LIVE (username &
      // nama terkini). Notif lama tanpa token → no-op. Aktor terhapus / tanpa
      // actorId → label "Seseorang" (notificationActorLabels(null)).
      const labels = notificationActorLabels(liveUser);
      return {
        ...item,
        actorName: liveActor.actorName,
        actorAvatarUrl: liveActor.actorAvatarUrl,
        title: fillNotificationActorTokens(item.title, labels),
        body: fillNotificationActorTokens(item.body, labels),
        reviewSummary: orderNumber ? reviewSummaryByOrder.get(orderNumber) ?? null : null,
        commentLiked: item.commentId ? likedCommentIds.has(item.commentId) : false,
        isFollowing:
          item.eventType === "user_followed" && item.actorId
            ? followingActorIds.has(item.actorId)
            : null,
        postDeleted:
          item.feedPostId && item.feedPostId.trim()
            ? !existingPostIds.has(item.feedPostId)
            : false,
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
