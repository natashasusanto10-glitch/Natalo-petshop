import { sendFcmToUser } from "@/lib/fcm";
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import { fillNotificationActorTokens } from "@/lib/social/brand-user";

export const FEED_NOTIFICATION_CATEGORY = "feed";
export const FEED_NOTIFICATION_SOURCE = "feed";
export const SOCIAL_NOTIFICATION_SOURCE = "social";

/** Event beraktor yang dirender klien (avatar bulat) — spec §2, review A2.
 *  JANGAN pakai kategori: feed_encoding_failed dkk harus tetap andal. */
const RENDER_CLIENT_EVENTS = new Set([
  "feed_new_comment",
  "feed_new_like",
  "feed_mention",
  "feed_tagged",
]);

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
  | "feed_mention"
  | "feed_tagged";

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

/**
 * Map event type → kategori PREFERENSI push ("feed" = toggle "Feed Activity"
 * di NotificationPreferencesScreen: komentar/like/share/mention di postingan
 * user). Hasil moderasi & status upload (approved/rejected/encoding/review)
 * TIDAK di-gate — itu status postingan milik user sendiri, selalu dikirim.
 * Return null = tidak difilter preferensi (always-on).
 */
function derivePrefCategory(
  eventType: FeedNotificationEventType,
): "feed" | null {
  switch (eventType) {
    case "feed_new_comment":
    case "feed_new_like":
    case "feed_new_share":
    case "feed_mention":
    case "feed_tagged":
      return "feed";
    default:
      return null;
  }
}

export function truncateFeedText(input: string | null | undefined, limit = 80) {
  const trimmed = (input ?? "").trim();
  if (trimmed.length <= limit) return trimmed;
  return `${trimmed.slice(0, limit - 1)}…`;
}

/**
 * Teks notif komentar ringkas ala IG: nama aktor jadi judul + isi komentar
 * langsung (tanpa judul generik / judul post — thumbnail kanan sudah
 * menunjukkan post-nya). "berkomentar" WAJIB memuat "komentar" karena filter
 * tab Feed di client mencocokkan keyword itu.
 */
export function buildCommentNotificationText(
  actorName: string,
  content: string,
): { title: string; body: string } {
  return {
    title: `${actorName} berkomentar`,
    body: truncateFeedText(content),
  };
}

export function quoteFeedTitle(title: string | null | undefined) {
  const safeTitle = truncateFeedText(title, 60) || "Postingan kamu";
  return `"${safeTitle}"`;
}

/**
 * Teks notif Tag People (Spec B): "[Nama] menandai Anda dalam postingan".
 * Penandai official → nama brand (caller yang resolve actorName).
 */
export function buildTaggedNotificationTitle(actorName: string): string {
  return `${actorName} menandai Anda dalam postingan`;
}

export const derivePrefCategoryForTest = derivePrefCategory;

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
  commentId?: string | null;
  data?: Record<string, string | null | undefined>;
  actor?: { avatarUrl?: string | null; name?: string | null; username?: string | null };
  // ID user aktor — disimpan supaya read path bisa resolve avatar/nama LIVE
  // (foto profil terkini), bukan snapshot basi. Null untuk notif tanpa aktor
  // tunggal (share, milestone).
  actorId?: string | null;
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
    // Judul/body dari caller BISA memuat token aktor (nama/username). Push yang
    // terkirim tak bisa di-update kemudian → isi token dgn label SNAPSHOT
    // (identitas aktor saat ini). Baris Announcement tetap disimpan DENGAN
    // token supaya read path bisa isi nilai LIVE (lihat notifications/me).
    const snapshotActorLabels = {
      nameLabel: params.actor?.name?.trim() || "Seseorang",
      usernameLabel:
        params.actor?.username?.trim() || params.actor?.name?.trim() || "Seseorang",
    };
    const payload: PushPayload = {
      title: fillNotificationActorTokens(params.title, snapshotActorLabels),
      body: fillNotificationActorTokens(params.message, snapshotActorLabels),
      url,
      tag: params.tag ?? `${params.eventType}-${params.feedPostId}`,
      data: pushData,
      imageUrl: params.thumbnailUrl ?? null,
      // category dipakai untuk action buttons di iOS. Default null —
      // hanya event yang butuh action (mis. feed_review_pending untuk
      // admin moderate) yang set.
      category: deriveNotificationCategory(params.eventType),
      // prefCategory = filter preferensi user (toggle "Feed Activity").
      // Engagement (komentar/like/share/mention) di-gate; status upload
      // milik user sendiri tidak.
      prefCategory: derivePrefCategory(params.eventType),
      renderClientSide: RENDER_CLIENT_EVENTS.has(params.eventType),
      actorAvatarUrl: params.actor?.avatarUrl ?? null,
    };

    // 2 channel (web + FCM) — sendApnsToUser dihapus, lihat komentar di
    // lib/fcm.ts (dobel notif iOS). category (action buttons) tetap
    // jalan lewat sendFcmToUser -> aps.category.
    await Promise.all([
      sendPushToUser(params.userId, payload),
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
          commentId: params.commentId ?? null,
          ctaLabel: params.ctaLabel ?? "Lihat Postingan",
          actorAvatarUrl: params.actor?.avatarUrl ?? null,
          actorName: params.actor?.name ?? null,
          actorId: params.actorId ?? null,
          publishedAt: new Date(),
          targetUserId: params.userId,
        },
      }),
    ]);
  } catch (err) {
    console.warn("[feed-notification] failed:", err);
  }
}
