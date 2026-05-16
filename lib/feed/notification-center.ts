import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";

export const FEED_NOTIFICATION_CATEGORY = "feed";
export const FEED_NOTIFICATION_SOURCE = "feed";

export type FeedNotificationEventType =
  | "feed_review_pending"
  | "feed_post_approved"
  | "feed_post_rejected"
  | "feed_new_comment"
  | "feed_new_like"
  | "feed_new_share";

export type FeedNotificationStatus = "pending" | "approved" | "rejected";

export function feedPostOwnerUrl(postId: string) {
  return `/akun/postingan-saya/${encodeURIComponent(postId)}`;
}

export function truncateFeedText(input: string | null | undefined, limit = 80) {
  const trimmed = (input ?? "").trim();
  if (trimmed.length <= limit) return trimmed;
  return `${trimmed.slice(0, limit - 1)}…`;
}

export function quoteFeedTitle(title: string | null | undefined) {
  const safeTitle = truncateFeedText(title, 60) || "Postingan kamu";
  return `"${safeTitle}"`;
}

export async function createFeedNotification(params: {
  userId: string;
  eventType: FeedNotificationEventType;
  title: string;
  message: string;
  feedPostId: string;
  thumbnailUrl?: string | null;
  status?: FeedNotificationStatus | null;
  url?: string | null;
  ctaLabel?: string | null;
  tag?: string | null;
  data?: Record<string, string | null | undefined>;
  dedupeByEvent?: boolean;
}) {
  const url = params.url ?? feedPostOwnerUrl(params.feedPostId);

  try {
    if (params.dedupeByEvent) {
      const existing = await prisma.announcement.findFirst({
        where: {
          targetUserId: params.userId,
          source: FEED_NOTIFICATION_SOURCE,
          eventType: params.eventType,
          feedPostId: params.feedPostId,
        },
        select: { id: true },
      });
      if (existing) return;
    }

    const pushData: Record<string, string> = {
      source: FEED_NOTIFICATION_SOURCE,
      type: params.eventType,
      feed_post_id: params.feedPostId,
      post_id: params.feedPostId,
      url,
    };
    if (params.thumbnailUrl) pushData.thumbnail_url = params.thumbnailUrl;
    if (params.status) pushData.status = params.status;
    for (const [key, value] of Object.entries(params.data ?? {})) {
      if (value != null && value !== "") pushData[key] = value;
    }

    const payload: PushPayload = {
      title: params.title,
      body: params.message,
      url,
      tag: params.tag ?? `${params.eventType}-${params.feedPostId}`,
      data: pushData,
    };

    await Promise.all([
      sendPushToUser(params.userId, payload),
      sendApnsToUser(params.userId, payload),
      sendFcmToUser(params.userId, payload),
      prisma.announcement.create({
        data: {
          title: params.title,
          body: params.message,
          url,
          segment: "all",
          type: FEED_NOTIFICATION_CATEGORY,
          source: FEED_NOTIFICATION_SOURCE,
          eventType: params.eventType,
          feedPostId: params.feedPostId,
          thumbnailUrl: params.thumbnailUrl ?? null,
          feedStatus: params.status ?? null,
          ctaLabel: params.ctaLabel ?? "Lihat Postingan",
          publishedAt: new Date(),
          targetUserId: params.userId,
        },
      }),
    ]);
  } catch (err) {
    console.warn("[feed-notification] failed:", err);
  }
}
