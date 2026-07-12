/**
 * Publish-push: kirim push notification saat admin publish feed post
 * dengan opsi "Beri tahu pelanggan" (notifyOnPublish) dicentang.
 *
 * Semua guard (role, status, encoding, idempotensi, daily cap) ada di
 * dalam sendFeedPublishPush — aman dipanggil dari mana pun (webhook Bunny
 * saat encode selesai, atau API publish langsung untuk post tanpa video)
 * tanpa perlu caller mikirin validasi ulang. Errors di-swallow supaya
 * publish flow tidak pernah gagal gara-gara push.
 */

import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";
import { buildFeedPushPayload } from "@/lib/feed/publish-push-payload";

export type PushSegment = "all" | "members" | "active30d";

/** Batas kirim publish-push per hari — cegah spam kalau admin publish beruntun. */
export const FEED_PUSH_DAILY_CAP = 2;

const BATCH_SIZE = 50;

/**
 * Resolve daftar userId target berdasarkan segment — copy pola dari
 * app/api/admin/push/broadcast/route.ts (baris 100-141).
 */
export async function resolveSegmentUserIds(segment: PushSegment): Promise<string[]> {
  if (segment === "all") {
    const rows = await prisma.pushSubscription.findMany({
      where: { userId: { not: null } },
      select: { userId: true },
      distinct: ["userId"],
    });
    return rows.map((r) => r.userId).filter((id): id is string => !!id);
  }

  const since =
    segment === "active30d" ? new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) : null;

  const orderUsers = await prisma.order.findMany({
    where: {
      userId: { not: null },
      paymentStatus: "PAID",
      ...(since ? { createdAt: { gte: since } } : {}),
    },
    select: { userId: true },
    distinct: ["userId"],
  });
  const orderUserIds = orderUsers.map((o) => o.userId).filter((id): id is string => !!id);

  if (orderUserIds.length === 0) return [];

  const subRows = await prisma.pushSubscription.findMany({
    where: { userId: { in: orderUserIds } },
    select: { userId: true },
    distinct: ["userId"],
  });
  return subRows.map((r) => r.userId).filter((id): id is string => !!id);
}

/** Hitung berapa feed post yang sudah kirim publish-push dalam 24 jam terakhir. */
export async function countRecentPublishPush(): Promise<number> {
  return prisma.feedPost.count({
    where: { publishPushSentAt: { gte: new Date(Date.now() - 24 * 60 * 60 * 1000) } },
  });
}

/**
 * Kirim publish-push untuk satu feed post. Dipanggil setelah post publish
 * (ADMIN, status ACTIVE, video ready) dan notifyOnPublish=true.
 *
 * Guard di dalam (return diam kalau tidak lolos):
 *   - Post tidak ada / authorRole != "ADMIN" / status != "ACTIVE" /
 *     encodingStatus != "ready" / notifyOnPublish=false / sudah pernah kirim.
 *   - Daily cap tercapai (FEED_PUSH_DAILY_CAP) → skip + warn.
 *   - Klaim atomik via updateMany(publishPushSentAt: null) — race-safe,
 *     kalau count===0 berarti sudah diklaim proses lain, return diam.
 */
export async function sendFeedPublishPush(postId: string): Promise<void> {
  try {
    const post = await prisma.feedPost.findUnique({
      where: { id: postId },
      select: {
        id: true,
        authorRole: true,
        status: true,
        encodingStatus: true,
        title: true,
        description: true,
        notifyOnPublish: true,
        pushSegment: true,
        publishPushSentAt: true,
      },
    });
    if (!post) return;
    if (post.authorRole !== "ADMIN") return;
    if (post.status !== "ACTIVE") return;
    if (post.encodingStatus !== "ready") return;
    if (!post.notifyOnPublish) return;
    if (post.publishPushSentAt != null) return;

    const recentCount = await countRecentPublishPush();
    if (recentCount >= FEED_PUSH_DAILY_CAP) {
      console.warn("[feed-push] daily cap tercapai, skip", postId);
      return;
    }

    // Klaim atomik — hindari double-send kalau dipanggil bersamaan
    // (mis. webhook Bunny + retry manual admin).
    const claim = await prisma.feedPost.updateMany({
      where: { id: postId, publishPushSentAt: null },
      data: { publishPushSentAt: new Date() },
    });
    if (claim.count === 0) return;

    const { title, body, url, tag } = buildFeedPushPayload(
      postId,
      post.title,
      post.description,
    );
    const segment: PushSegment = (post.pushSegment as PushSegment | null) ?? "members";

    await prisma.announcement.create({
      data: {
        title,
        body,
        url,
        segment,
        type: "announcement",
        ctaLabel: "Lihat Post",
        publishedAt: new Date(),
        status: "PUBLISHED",
      },
    });

    const targetUserIds = await resolveSegmentUserIds(segment);
    if (targetUserIds.length === 0) return;

    const payload: PushPayload = { title, body, url, tag };

    for (let i = 0; i < targetUserIds.length; i += BATCH_SIZE) {
      const batch = targetUserIds.slice(i, i + BATCH_SIZE);
      await Promise.allSettled(
        batch.flatMap((userId) => [
          sendPushToUser(userId, payload),
          sendApnsToUser(userId, payload),
          sendFcmToUser(userId, payload),
        ]),
      );
    }
  } catch (err) {
    console.warn("[feed-push] failed:", err);
  }
}

/**
 * Kirim test push publish-feed ke satu user — dipakai admin untuk preview
 * tanpa menyentuh post asli / Announcement / guard apa pun.
 */
export async function sendFeedPublishTestPush(params: {
  userId: string;
  title: string;
  description: string | null;
}): Promise<void> {
  try {
    // Reuse buildFeedPushPayload untuk truncation title/body + fallback body
    // yang sama persis dengan publish-push asli, lalu override url/tag
    // supaya test push tidak menyentuh post id nyata.
    const { title, body } = buildFeedPushPayload(
      "test",
      params.title,
      params.description,
    );
    const payload: PushPayload = {
      title,
      body,
      url: "/feed",
      tag: `feed-publish-test-${params.userId}`,
    };

    await Promise.allSettled([
      sendPushToUser(params.userId, payload),
      sendApnsToUser(params.userId, payload),
      sendFcmToUser(params.userId, payload),
    ]);
  } catch (err) {
    console.warn("[feed-push] test push failed:", err);
  }
}
