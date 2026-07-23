import { sendFcmToUser } from "@/lib/fcm";
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import {
  brandPhotoUrl,
  isAdminRole,
  notificationActorFields,
  OFFICIAL_BRAND_NAME,
} from "@/lib/social/brand-user";
import { feedNotificationThumbnail } from "@/lib/feed/notification-thumbnail";
import { signBunnyUrl } from "@/lib/feed/bunny";

export const SOCIAL_NOTIFICATION_SOURCE = "social";

export type SocialNotificationEventType =
  | "user_followed"
  | "followed_user_posted";

/** Batas follower per postingan untuk fan-out notif. Di atas ini, kita
 *  cap + log supaya tahu kapan perlu pindah ke queue/batch worker.
 *  Untuk Natalo (follower sedikit) tidak akan kena. */
const FOLLOWER_NOTIFY_CAP = 500;

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
        role: true,
        profilePhotoUrl: true,
      },
    });
    if (!follower) return;

    // Akun official (admin) → brand name + foto null di notif (jangan
    // bocorkan nama asli/foto pemilik ke user yang di-follow admin).
    const actorName = isAdminRole(follower.role)
      ? OFFICIAL_BRAND_NAME
      : displayName(follower);
    // signBunnyUrl no-op untuk URL non-Bunny (profil biasanya di storage
    // lain) — aman dipanggil selalu, cuma efektif kalau memang hotlink
    // protection aktif & URL-nya memang di CDN Bunny.
    const actorPhoto =
      signBunnyUrl(brandPhotoUrl(follower.role, follower.profilePhotoUrl)) ??
      null;
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
      imageUrl: actorPhoto,
      data: {
        source: SOCIAL_NOTIFICATION_SOURCE,
        type: eventType,
        follower_id: params.followerId,
        follower_username: follower.username ?? "",
        url,
      },
    };

    // 2 channel (web + FCM) — sendApnsToUser dihapus, lihat komentar di
    // lib/fcm.ts (dobel notif iOS).
    await Promise.allSettled([
      sendPushToUser(params.followingId, payload),
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
          thumbnailUrl: actorPhoto,
          actorName,
          actorAvatarUrl: actorPhoto,
          actorId: params.followerId,
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

/**
 * Notif ke SEMUA follower saat author posting baru di-APPROVE admin
 * (PENDING_REVIEW → ACTIVE). Bukan saat submit, supaya follower tidak
 * dapat notif untuk postingan yang masih pending / akhirnya ditolak.
 *
 * Idempotent: dedup via Announcement dengan eventType + url (postId).
 * Kalau postingan ini sudah pernah trigger notif "followed_user_posted"
 * (mis. admin hide lalu approve ulang, atau double-call), skip total.
 * Skip kalau author ADMIN (postingan official tidak butuh notif follower).
 *
 * Fire-and-forget di call site (jangan await — jangan block response
 * admin approve). Semua error di-swallow + log.
 */
export async function sendNewPostToFollowersNotification(postId: string) {
  try {
    const post = await prisma.feedPost.findUnique({
      where: { id: postId },
      select: {
        id: true,
        kind: true,
        status: true,
        thumbnailUrl: true,
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
        author: {
          select: {
            id: true,
            name: true,
            username: true,
            role: true,
            profilePhotoUrl: true,
          },
        },
      },
    });
    if (!post) return;
    // Hanya untuk postingan yang sudah tayang + author customer (bukan
    // admin official).
    if (post.status !== "ACTIVE") return;
    if (post.author.role === "ADMIN") return;

    const eventType: SocialNotificationEventType = "followed_user_posted";
    const url = `/feed/${post.id}`;

    // Dedup — kalau postingan ini sudah pernah trigger notif (1 Announcement
    // saja cukup jadi penanda, semua follower share url+eventType yg sama),
    // skip. Cegah double-notif saat re-approve / double admin click.
    const already = await prisma.announcement.findFirst({
      where: { eventType, url },
      select: { id: true },
    });
    if (already) return;

    // Ambil semua follower author.
    const follows = await prisma.userFollow.findMany({
      where: { followingId: post.author.id },
      select: { followerId: true },
    });
    if (follows.length === 0) return;

    let followerIds = follows.map((f) => f.followerId);
    if (followerIds.length > FOLLOWER_NOTIFY_CAP) {
      console.warn(
        `[social-notification] author ${post.author.id} punya ` +
          `${followerIds.length} follower > cap ${FOLLOWER_NOTIFY_CAP}. ` +
          `Notif di-cap; pertimbangkan queue/batch worker.`,
      );
      followerIds = followerIds.slice(0, FOLLOWER_NOTIFY_CAP);
    }

    const actorName = post.author.username || post.author.name || "Seseorang";
    const kindLabel = post.kind === "PHOTO_CAROUSEL" ? "foto" : "video";
    const title = "Postingan baru";
    const body = `${actorName} posting ${kindLabel} baru`;
    // WAJIB sign — video thumbnail di-hosting Bunny CDN dgn hotlink
    // protection; tanpa token, APNs/FCM gagal fetch gambar saat push
    // (403), rich image tak pernah nongol walau NSE iOS sudah beres.
    // In-app read path (mapAnnouncement) sudah sign versi Announcement-nya
    // sendiri; ini KHUSUS untuk imageUrl yang dikirim ke push itself.
    const thumb = signBunnyUrl(feedNotificationThumbnail(post)) ?? null;
    const actorFields = notificationActorFields(
      post.author.role,
      post.author.name,
      post.author.profilePhotoUrl,
    );

    const payload: PushPayload = {
      title,
      body,
      url,
      tag: `${eventType}-${post.id}`,
      imageUrl: thumb,
      data: {
        source: SOCIAL_NOTIFICATION_SOURCE,
        type: eventType,
        post_id: post.id,
        author_username: post.author.username ?? "",
        category: "feed",
        url,
      },
    };

    // Announcement batch — 1 row per follower (targetUserId) supaya muncul
    // di bell masing-masing.
    await prisma.announcement.createMany({
      data: followerIds.map((fid) => ({
        title,
        body,
        url,
        segment: "all",
        type: "feed",
        source: SOCIAL_NOTIFICATION_SOURCE,
        eventType,
        feedPostId: post.id,
        thumbnailUrl: thumb,
        ctaLabel: "Lihat Postingan",
        publishedAt: new Date(),
        targetUserId: fid,
        actorId: post.author.id,
        actorAvatarUrl: actorFields.actorAvatarUrl,
        actorName: actorFields.actorName,
      })),
    });

    // Push fan-out — paralel, error per-follower di-swallow oleh allSettled.
    // 2 channel (web + FCM) — sendApnsToUser dihapus, lihat komentar di
    // lib/fcm.ts (dobel notif iOS).
    await Promise.allSettled(
      followerIds.flatMap((fid) => [
        sendPushToUser(fid, payload),
        sendFcmToUser(fid, payload),
      ]),
    );
  } catch (err) {
    console.warn("[social-notification] new-post-to-followers failed:", err);
  }
}
