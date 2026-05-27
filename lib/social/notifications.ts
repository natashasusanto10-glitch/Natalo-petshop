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
