/**
 * Feed status notifications.
 *
 * These helpers insert personal Announcement rows for Notification Center
 * and fan out push through the existing web/APNs/FCM channels. Errors are
 * swallowed so notification delivery never blocks the Feed action itself.
 */

import { prisma } from "@/lib/prisma";
import {
  createFeedNotification,
  feedPostOwnerUrl,
  quoteFeedTitle,
  type FeedNotificationEventType,
  type FeedNotificationStatus,
} from "@/lib/feed/notification-center";

export type FeedModerationAction = "approve" | "reject" | "hide" | "unhide";

function eventForAction(action: FeedModerationAction): {
  eventType: FeedNotificationEventType;
  status: FeedNotificationStatus | null;
  title: string;
  ctaLabel: string;
} | null {
  switch (action) {
    case "approve":
      return {
        eventType: "feed_post_approved",
        status: "approved",
        title: "Feed kamu sudah tayang",
        ctaLabel: "Lihat Postingan",
      };
    case "reject":
      return {
        eventType: "feed_post_rejected",
        status: "rejected",
        title: "Feed kamu ditolak",
        ctaLabel: "Lihat Alasan",
      };
    case "hide":
    case "unhide":
      return null;
    default:
      return null;
  }
}

/**
 * Notify user kalau video upload-nya GAGAL di-encode.
 *
 * Dipanggil oleh:
 *   - Bunny webhook saat status ERROR (post di-mark failed)
 *   - Reconcile cron saat post stuck >timeout AND Bunny null/error
 *
 * Idempotent via dedupeByEvent — kalau notif untuk post yang sama udah
 * pernah dikirim, gak akan duplicate.
 */
export async function sendFeedEncodingFailedNotification(params: {
  postId: string;
  reason?: string | null;
}) {
  try {
    const post = await prisma.feedPost.findUnique({
      where: { id: params.postId },
      select: {
        id: true,
        authorId: true,
        authorRole: true,
        title: true,
        thumbnailUrl: true,
      },
    });
    if (!post || post.authorRole !== "CUSTOMER") return;

    const reasonSuffix = params.reason
      ? ` Alasan: ${params.reason}.`
      : "";

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_encoding_failed",
      title: "Video gagal diproses",
      message: `Postingan ${quoteFeedTitle(
        post.title,
      )} gagal di-encode dan tidak bisa tayang.${reasonSuffix} Silakan upload ulang.`,
      feedPostId: post.id,
      thumbnailUrl: post.thumbnailUrl,
      status: "rejected",
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan Saya",
      dedupeByEvent: true,
    });
  } catch (err) {
    console.warn("[feed-notif] encoding-failed failed:", err);
  }
}

export async function sendFeedPendingReviewNotification(params: {
  postId: string;
}) {
  try {
    const post = await prisma.feedPost.findUnique({
      where: { id: params.postId },
      select: {
        id: true,
        authorId: true,
        authorRole: true,
        status: true,
        title: true,
        thumbnailUrl: true,
      },
    });
    if (!post || post.authorRole !== "CUSTOMER") return;
    if (post.status !== "PENDING_REVIEW") return;

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_review_pending",
      title: "Feed kamu sedang menunggu review",
      message: `Postingan ${quoteFeedTitle(
        post.title
      )} sedang menunggu review admin sebelum tampil di Feed.`,
      feedPostId: post.id,
      thumbnailUrl: post.thumbnailUrl,
      status: "pending",
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan Saya",
      dedupeByEvent: true,
    });
  } catch (err) {
    console.warn("[feed-notif] pending failed:", err);
  }
}

export async function sendFeedModerationNotification(params: {
  postId: string;
  action: FeedModerationAction;
  note?: string | null;
}) {
  const event = eventForAction(params.action);
  if (!event) return;

  try {
    const post = await prisma.feedPost.findUnique({
      where: { id: params.postId },
      select: {
        id: true,
        authorId: true,
        authorRole: true,
        title: true,
        thumbnailUrl: true,
      },
    });
    if (!post || post.authorRole !== "CUSTOMER") return;

    let message: string;
    if (params.action === "approve") {
      message = `Postingan ${quoteFeedTitle(
        post.title
      )} sudah disetujui dan sekarang tampil di Feed.`;
    } else if (params.action === "reject") {
      message = `Postingan ${quoteFeedTitle(
        post.title
      )} belum bisa ditayangkan. Silakan cek alasannya.`;
    } else if (params.action === "hide") {
      message = params.note
        ? `Postingan ${quoteFeedTitle(
            post.title
          )} disembunyikan oleh admin. Alasan: ${params.note}`
        : `Postingan ${quoteFeedTitle(post.title)} disembunyikan oleh admin.`;
    } else {
      message = `Postingan ${quoteFeedTitle(
        post.title
      )} sudah ditampilkan kembali di Feed.`;
    }

    await createFeedNotification({
      userId: post.authorId,
      eventType: event.eventType,
      title: event.title,
      message,
      feedPostId: post.id,
      thumbnailUrl: post.thumbnailUrl,
      status: event.status,
      url: feedPostOwnerUrl(post.id),
      ctaLabel: event.ctaLabel,
      dedupeByEvent: params.action === "approve" || params.action === "reject",
    });
  } catch (err) {
    console.warn("[feed-notif] moderation failed:", err);
  }
}
