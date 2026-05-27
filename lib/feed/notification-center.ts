import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";

export const FEED_NOTIFICATION_CATEGORY = "feed";
export const FEED_NOTIFICATION_SOURCE = "feed";
export const SOCIAL_NOTIFICATION_SOURCE = "social";

export type NotificationSurface =
  | typeof FEED_NOTIFICATION_SOURCE
  | typeof SOCIAL_NOTIFICATION_SOURCE;

export type FeedNotificationEventType =
  | "feed_review_pending"
  | "feed_post_approved"
  | "feed_post_rejected"
  | "feed_encoding_failed"
  | "feed_new_comment"
  | "feed_new_like"
  | "feed_new_share"
  | "feed_mention";

export type FeedNotificationStatus = "pending" | "approved" | "rejected";

export function feedPostOwnerUrl(postId: string) {
  return `/akun/postingan-saya/${encodeURIComponent(postId)}`;
}

/**
 * Map event type → APNs notification category. Category match dengan
 * UNNotificationCategory yang di-register di iOS AppDelegate
 * (registerNotificationCategories). Trigger action buttons di banner
 * tray.
 *
 * Categories (match dengan ios/App/App/AppDelegate.swift):
 *   - "feed_review"  → 2 buttons: "Lihat", "Tolak" (admin moderation)
 *   - "feed_result"  → 1 button: "Lihat" (user dapat hasil approve/reject)
 *   - null           → default tap-to-open behavior
 */
function deriveNotificationCategory(
  eventType: FeedNotificationEventType,
): string | null {
  switch (eventType) {
    case "feed_review_pending":
      return "feed_review";
    case "feed_post_approved":
    case "feed_post_rejected":
    case "feed_encoding_failed":
      return "feed_result";
    default:
      return null;
  }
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
  surface?: NotificationSurface;
}) {
  const url = params.url ?? feedPostOwnerUrl(params.feedPostId);
  const surface = params.surface ?? FEED_NOTIFICATION_SOURCE;

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
      source: surface,
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

    // Wave 4 #9: thumbnail post di-pass sebagai imageUrl untuk rich
    // notification — APNs NSE attach sebagai preview di banner, FCM
    // tampil sebagai BigPictureStyle di Android, Web Push tampil image
    // di body notification. Fallback graceful — kalau thumbnail null
    // (post tanpa video / belum encoding), notif tetap text-only.
    const payload: PushPayload = {
      title: params.title,
      body: params.message,
      url,
      tag: params.tag ?? `${params.eventType}-${params.feedPostId}`,
      data: pushData,
      imageUrl: params.thumbnailUrl ?? null,
      // category dipakai untuk action buttons di iOS. Default null —
      // hanya event yang butuh action (mis. feed_review_pending untuk
      // admin moderate) yang set.
      category: deriveNotificationCategory(params.eventType),
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
          type: surface,
          source: surface,
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
