import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";

export const SOCIAL_NOTIFICATION_SOURCE = "social";

export type SocialNotificationEventType = "user_followed";

function displayName(user: { name: string | null; username: string | null }) {
  return user.username || user.name || "Seseorang";
}

export async function sendFollowNotification(params: {
  followerId: string;
  followingId: string;
}) {
  try {
    if (params.followerId === params.followingId) return;

    const follower = await prisma.user.findUnique({
      where: { id: params.followerId },
      select: {
        id: true,
        name: true,
        username: true,
        profilePhotoUrl: true,
      },
    });
    if (!follower) return;

    const actorName = displayName(follower);
    const url = follower.username
      ? `/u/${encodeURIComponent(follower.username)}`
      : "/notifications";
    const title = "Pengikut baru";
    const body = `${actorName} mulai mengikuti kamu.`;
    const eventType: SocialNotificationEventType = "user_followed";

    // Dedup — cegah spam follow→unfollow→follow. Kalau follower ini sudah
    // trigger notif "user_followed" ke target dalam 7 hari terakhir, skip
    // (tidak push + tidak buat Announcement baru). Keyed by `url` yang
    // unik per follower-username. Hanya dedup kalau follower punya
    // username (url unik); follower tanpa username pakai url generic
    // "/notifications" yang collide antar user, jadi skip dedup supaya
    // tidak over-suppress notif dari follower berbeda.
    if (follower.username) {
      const recent = await prisma.announcement.findFirst({
        where: {
          targetUserId: params.followingId,
          eventType,
          url,
          createdAt: {
            gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
          },
        },
        select: { id: true },
      });
      if (recent) return;
    }

    const payload: PushPayload = {
      title,
      body,
      url,
      tag: `${eventType}-${params.followerId}-${params.followingId}`,
      imageUrl: follower.profilePhotoUrl ?? null,
      data: {
        source: SOCIAL_NOTIFICATION_SOURCE,
        type: eventType,
        follower_id: params.followerId,
        follower_username: follower.username ?? "",
        url,
      },
    };

    await Promise.allSettled([
      sendPushToUser(params.followingId, payload),
      sendApnsToUser(params.followingId, payload),
      sendFcmToUser(params.followingId, payload),
      prisma.announcement.create({
        data: {
          title,
          body,
          url,
          segment: "all",
          type: SOCIAL_NOTIFICATION_SOURCE,
          source: SOCIAL_NOTIFICATION_SOURCE,
          eventType,
          thumbnailUrl: follower.profilePhotoUrl ?? null,
          ctaLabel: "Lihat Profil",
          publishedAt: new Date(),
          targetUserId: params.followingId,
        },
      }),
    ]);
  } catch (err) {
    console.warn("[social-notification] follow failed:", err);
  }
}
