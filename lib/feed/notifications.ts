/**
 * Feed moderation notifications — hook fired when an admin moderates a
 * customer's feed post. Mirrors the lib/push.ts order-status pattern:
 * fan-out push to web/APNs/FCM + insert a personal Announcement so the
 * notification center (bell icon list) shows the same message even when
 * the user hasn't opted in to push.
 */

import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";

export type FeedModerationAction = "approve" | "reject" | "hide" | "unhide";

const FEED_NOTIF_TYPE = "feed";

function buildCopy(
  action: FeedModerationAction,
  note: string | null,
): { title: string; body: string; ctaLabel: string; url: string } | null {
  switch (action) {
    case "approve":
      return {
        title: "Postingan disetujui 🎉",
        body: "Video kamu sekarang tayang di Feed Natalo. Yuk lihat respon komunitas.",
        ctaLabel: "Lihat di Feed",
        url: "/feed",
      };
    case "reject":
      return {
        title: "Postingan ditolak",
        body: note
          ? `Alasan: ${note}`
          : "Postinganmu tidak sesuai pedoman komunitas Natalo.",
        ctaLabel: "Lihat Status",
        url: "/notifications",
      };
    case "hide":
      // Admin took an existing ACTIVE post off the feed — let the user know.
      return {
        title: "Postingan disembunyikan",
        body: note
          ? `Postinganmu disembunyikan oleh admin. Alasan: ${note}`
          : "Postinganmu disembunyikan dari Feed oleh admin.",
        ctaLabel: "Lihat Status",
        url: "/notifications",
      };
    case "unhide":
      return {
        title: "Postingan tayang kembali",
        body: "Admin sudah menampilkan postinganmu lagi di Feed Natalo.",
        ctaLabel: "Lihat di Feed",
        url: "/feed",
      };
    default:
      return null;
  }
}

/**
 * Fire-and-forget — never throw. Caller awaits to enforce ordering but
 * the function itself swallows any errors so a notification failure can't
 * roll back the moderation update itself.
 */
export async function sendFeedModerationNotification(params: {
  postId: string;
  action: FeedModerationAction;
  note?: string | null;
}) {
  const { postId, action, note } = params;
  const copy = buildCopy(action, note ?? null);
  if (!copy) return;

  try {
    const post = await prisma.feedPost.findUnique({
      where: { id: postId },
      select: { id: true, userId: true },
    });
    if (!post || !post.userId) return; // admin-authored posts have no user to notify

    const payload: PushPayload = {
      title: copy.title,
      body: copy.body,
      url: copy.url,
      tag: `feed-${postId}`,
      data: {
        type: FEED_NOTIF_TYPE,
        post_id: postId,
        action,
        url: copy.url,
      },
    };

    await Promise.all([
      sendPushToUser(post.userId, payload),
      sendApnsToUser(post.userId, payload),
      sendFcmToUser(post.userId, payload),
      prisma.announcement
        .create({
          data: {
            title: copy.title,
            body: copy.body,
            url: copy.url,
            segment: "all", // ignored when targetUserId is set
            type: FEED_NOTIF_TYPE,
            ctaLabel: copy.ctaLabel,
            publishedAt: new Date(),
            targetUserId: post.userId,
          },
        })
        .catch((err) => {
          console.warn("[feed-notif] failed to create Announcement:", err);
        }),
    ]);
  } catch (err) {
    console.warn("[feed-notif] failed:", err);
  }
}
