/**
 * Activity notifications for the customer feed.
 *
 * Fires push (web + APNs + FCM) AND inserts a personal Announcement so the
 * notification center (/notifications) surfaces the same message even
 * when the user hasn't opted in to push.
 *
 * Triggers wired:
 *   - Top-level comment on a user's post  → notify post author
 *   - Reply to a user's comment           → notify parent comment author
 *   - Like on a user's post               → notify post author (batched)
 *   - Share on a user's post              → notify post author
 *
 * Self-notify is always skipped — never notify yourself for your own
 * activity. Errors are swallowed (notification helpers never throw)
 * because telemetry/notification failures must not block the user-facing
 * action that triggered them.
 */

import type { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  isAdminRole,
  likeRowActorFields,
  notificationActorFields,
  NOTIF_ACTOR_NAME_TOKEN,
  NOTIF_ACTOR_USERNAME_TOKEN,
  OFFICIAL_BRAND_NAME,
  topLikerAvatars,
} from "@/lib/social/brand-user";
import {
  buildCommentNotificationText,
  buildTaggedNotificationTitle,
  createFeedNotification,
  feedPostOwnerUrl,
  quoteFeedTitle,
  SOCIAL_NOTIFICATION_SOURCE,
  truncateFeedText,
} from "@/lib/feed/notification-center";
import { feedNotificationThumbnail } from "@/lib/feed/notification-thumbnail";
import { taggedUserIdsFromRows } from "@/lib/feed/tagged-users";
import { shouldRePush } from "@/lib/social/follow-aggregation";
import { sendFcmToUser } from "@/lib/fcm";
import { sendPushToUser, type PushPayload } from "@/lib/push";

// Milestone helper remains available for bulk/broadcast-style summaries.
// Per-like Notification Center entries are batched below.
const LIKE_MILESTONES = [10, 50, 100, 500, 1000, 5000, 10000];
const LIKE_BATCH_WINDOW_MS = 30 * 60 * 1000;

/**
 * Top-level comment on someone else's post. Fires once per comment.
 * Skipped when the commenter is the post author themselves.
 */
export async function sendCommentNotification(params: {
  postId: string;
  commentId: string;
  actorUserId: string;
  content: string;
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
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
      },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return; // admin posts have no human recipient
    if (post.authorId === params.actorUserId) return; // self-comment, no notif

    const actor = await prisma.user.findUnique({
      where: { id: params.actorUserId },
      select: { name: true, role: true, profilePhotoUrl: true },
    });
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl
    );

    // Judul simpan token nama → read path isi nama LIVE (lihat notifications/me);
    // push di-fill snapshot oleh createFeedNotification.
    const commentText = buildCommentNotificationText(
      NOTIF_ACTOR_NAME_TOKEN,
      params.content,
    );

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_comment",
      title: commentText.title,
      message: commentText.body,
      feedPostId: post.id,
      thumbnailUrl: feedNotificationThumbnail(post),
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Komentar",
      tag: `feed-comment-${post.id}`,
      commentId: params.commentId,
      data: { comment_id: params.commentId },
      surface: SOCIAL_NOTIFICATION_SOURCE,
      actorId: params.actorUserId,
      actor: {
        avatarUrl: actorFields.actorAvatarUrl,
        name: actorFields.actorName,
      },
    });
  } catch (err) {
    console.warn("[feed-activity] sendCommentNotification:", err);
  }
}

/**
 * Reply to a specific comment. Fires once per reply.
 * Skipped when the replier is the parent comment author.
 */
export async function sendReplyNotification(params: {
  parentCommentId: string;
  replyCommentId: string;
  postId: string;
  actorUserId: string;
  content: string;
}) {
  try {
    const parent = await prisma.feedComment.findUnique({
      where: { id: params.parentCommentId },
      select: { authorId: true },
    });
    if (!parent || !parent.authorId) return;
    if (parent.authorId === params.actorUserId) return;

    const actor = await prisma.user.findUnique({
      where: { id: params.actorUserId },
      select: { name: true, role: true, profilePhotoUrl: true },
    });
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl
    );

    const post = await prisma.feedPost.findUnique({
      where: { id: params.postId },
      select: {
        id: true,
        title: true,
        thumbnailUrl: true,
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
      },
    });

    await createFeedNotification({
      userId: parent.authorId,
      eventType: "feed_new_comment",
      title: `${NOTIF_ACTOR_NAME_TOKEN} membalas komentarmu`,
      message: truncateFeedText(params.content),
      feedPostId: params.postId,
      thumbnailUrl: post ? feedNotificationThumbnail(post) : null,
      url: feedPostOwnerUrl(params.postId),
      ctaLabel: "Lihat Balasan",
      tag: `feed-reply-${params.parentCommentId}`,
      commentId: params.replyCommentId,
      data: {
        parent_comment_id: params.parentCommentId,
        reply_comment_id: params.replyCommentId,
      },
      surface: SOCIAL_NOTIFICATION_SOURCE,
      actorId: params.actorUserId,
      actor: {
        avatarUrl: actorFields.actorAvatarUrl,
        name: actorFields.actorName,
      },
    });
  } catch (err) {
    console.warn("[feed-activity] sendReplyNotification:", err);
  }
}

/**
 * @mention di komentar atau caption postingan. Fires ONCE per recipient
 * unik per source (komentar atau post), regardless multiple mentions
 * sama text. Skip self-mention (actor == recipient).
 *
 * Source bisa COMMENT atau POST CAPTION:
 *   - source = 'comment' → router pakai postId dari parent post
 *   - source = 'post'    → notif route ke post detail
 */
export async function sendMentionNotifications(params: {
  actorUserId: string;
  recipientUserIds: string[]; // already-resolved user IDs (dedupe + non-self)
  source: "comment" | "post";
  postId: string;
  commentId?: string | null;
  excerpt: string; // text excerpt (comment content atau caption)
}) {
  if (params.recipientUserIds.length === 0) return;
  try {
    const [actor, post] = await Promise.all([
      prisma.user.findUnique({
        where: { id: params.actorUserId },
        select: {
          name: true,
          username: true,
          role: true,
          profilePhotoUrl: true,
        },
      }),
      prisma.feedPost.findUnique({
        where: { id: params.postId },
        select: {
          id: true,
          title: true,
          thumbnailUrl: true,
          media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
        },
      }),
    ]);
    if (!post) return;
    // IG/TikTok pattern: notif title pakai bare username sebagai identity
    // label, bukan `@username`. Judul simpan token username → read path isi
    // username LIVE. Snapshot username (brand-safe) untuk fill push. Akun
    // official → brand name (username asli pemilik tak boleh bocor).
    const actorUsernameSnapshot = isAdminRole(actor?.role)
      ? OFFICIAL_BRAND_NAME
      : actor?.username?.trim() || actor?.name?.trim() || "Seseorang";
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl
    );

    const isComment = params.source === "comment";
    const title = isComment
      ? `${NOTIF_ACTOR_USERNAME_TOKEN} menyebut kamu di komentar`
      : `${NOTIF_ACTOR_USERNAME_TOKEN} menyebut kamu di postingan`;
    const message = truncateFeedText(params.excerpt);

    // Filter actor sendiri (defensive — caller seharusnya sudah skip).
    const recipients = params.recipientUserIds.filter(
      (id) => id !== params.actorUserId,
    );

    // Fire in parallel — tiap recipient dapat notif row sendiri.
    await Promise.allSettled(
      recipients.map((recipientUserId) =>
        createFeedNotification({
          userId: recipientUserId,
          eventType: "feed_mention",
          title,
          message,
          feedPostId: post.id,
          thumbnailUrl: feedNotificationThumbnail(post),
          url: feedPostOwnerUrl(post.id),
          ctaLabel: isComment ? "Lihat Komentar" : "Lihat Postingan",
          // Tag dedupe — kalau 1 user di-mention 2x di komentar yang
          // sama (e.g. "@asiong cek ini @asiong"), cuma 1 notif keluar.
          tag: isComment
            ? `feed-mention-comment-${params.commentId}-${recipientUserId}`
            : `feed-mention-post-${params.postId}-${recipientUserId}`,
          data: {
            mention_source: params.source,
            post_id: params.postId,
            ...(params.commentId
              ? { comment_id: params.commentId }
              : {}),
          },
          surface: SOCIAL_NOTIFICATION_SOURCE,
          actorId: params.actorUserId,
          actor: {
            avatarUrl: actorFields.actorAvatarUrl,
            name: actorFields.actorName,
            username: actorUsernameSnapshot,
          },
        }),
      ),
    );
  } catch (err) {
    console.warn("[feed-activity] sendMentionNotifications:", err);
  }
}

/**
 * Tag People (Spec B) — notif ke user yang ditandai di post baru.
 * Dipanggil dari POST create SETELAH transaksi sukses. Self-tag di-skip.
 * Deep-link: /feed/<postId> (case `feed` sudah ada di deep_link_service).
 */
export async function sendTaggedUserNotifications(params: {
  actorUserId: string;
  recipientUserIds: string[];
  postId: string;
}) {
  if (params.recipientUserIds.length === 0) return;
  try {
    const [actor, post] = await Promise.all([
      prisma.user.findUnique({
        where: { id: params.actorUserId },
        select: { name: true, username: true, role: true, profilePhotoUrl: true },
      }),
      prisma.feedPost.findUnique({
        where: { id: params.postId },
        select: {
          id: true,
          title: true,
          thumbnailUrl: true,
          media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
        },
      }),
    ]);
    if (!post) return;
    const actorName = isAdminRole(actor?.role)
      ? OFFICIAL_BRAND_NAME
      : actor?.username && actor.username.length > 0
        ? actor.username
        : actor?.name?.trim() || "Seseorang";
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl,
    );

    // Tidak ada notifikasi ke diri sendiri (self-tag boleh, tanpa notif).
    const recipients = params.recipientUserIds.filter(
      (id) => id !== params.actorUserId,
    );

    await Promise.allSettled(
      recipients.map((recipientUserId) =>
        createFeedNotification({
          userId: recipientUserId,
          eventType: "feed_tagged",
          title: buildTaggedNotificationTitle(actorName),
          message: truncateFeedText(post.title) || "Lihat postingannya sekarang.",
          feedPostId: post.id,
          thumbnailUrl: feedNotificationThumbnail(post),
          url: `/feed/${encodeURIComponent(post.id)}`,
          ctaLabel: "Lihat Postingan",
          tag: `feed-tagged-${params.postId}-${recipientUserId}`,
          data: { post_id: params.postId },
          surface: SOCIAL_NOTIFICATION_SOURCE,
          actor: {
            avatarUrl: actorFields.actorAvatarUrl,
            name: actorFields.actorName,
          },
        }),
      ),
    );
  } catch (err) {
    console.warn("[feed-activity] sendTaggedUserNotifications:", err);
  }
}

/**
 * Tag People VIDEO fix (final review Spec B) — dispatch notif tagged-user
 * persis saat video post bertransisi ke `encodingStatus: "ready"` (video
 * benar-benar playable), BUKAN saat provision time
 * (app/api/feed/bunny/upload-url/route.ts TIDAK LAGI memanggil
 * sendTaggedUserNotifications langsung). Sebelumnya notif dikirim begitu
 * row FeedPost dibuat dengan encodingStatus "uploading" — kalau upload
 * dibatalkan atau encoding gagal, tagged user tetap dapat notif phantom
 * yang mengarah ke post yang tak pernah tayang (videoUrl masih null).
 *
 * Dipanggil dari 2 hook point yang sama-sama menandai ready:
 *   - lib/feed/reconcile.ts (cron/manual reconcile)
 *   - app/api/feed/bunny/webhook/route.ts (webhook Bunny)
 *
 * Re-derive recipient dari baris FeedTaggedUser TERSIMPAN di DB (query
 * fresh di sini), bukan dari data provisioning-time yang sudah basi — kalau
 * tag berubah selagi video masih encoding, notif tetap akurat.
 *
 * `db`/`notify` injectable untuk test (default: prisma asli +
 * sendTaggedUserNotifications asli) — pola sama dengan
 * lib/feed/queries.ts getFeedCommentDetail. Errors ditelan (konsisten
 * dengan semua helper notif lain di file ini) — kegagalan notif tidak
 * boleh menggagalkan transisi ready itu sendiri.
 */
export async function notifyTaggedUsersOnVideoReady(
  params: { postId: string; actorUserId: string },
  deps: {
    db?: Pick<Prisma.TransactionClient, "feedTaggedUser">;
    notify?: typeof sendTaggedUserNotifications;
  } = {},
) {
  const db = deps.db ?? prisma;
  const notify = deps.notify ?? sendTaggedUserNotifications;
  try {
    const rows = await db.feedTaggedUser.findMany({
      where: { feedPostId: params.postId },
      select: { taggedUserId: true },
    });
    const recipientUserIds = taggedUserIdsFromRows(rows);
    if (recipientUserIds.length === 0) return;
    await notify({
      actorUserId: params.actorUserId,
      recipientUserIds,
      postId: params.postId,
    });
  } catch (err) {
    console.warn("[feed-activity] notifyTaggedUsersOnVideoReady:", err);
  }
}

/**
 * Was a milestone crossed between two likeCount snapshots? Returns the
 * milestone value, or null if no boundary in (prev, next].
 */
export function crossedLikeMilestone(
  prev: number,
  next: number
): number | null {
  if (next <= prev) return null;
  for (const m of LIKE_MILESTONES) {
    if (prev < m && next >= m) return m;
  }
  return null;
}

/**
 * Fired when a like takes a post past a milestone threshold (10/100/1000…).
 * Caller passes the milestone — they already computed it via
 * crossedLikeMilestone() against the before/after counts.
 */
export async function sendLikeMilestoneNotification(params: {
  postId: string;
  milestone: number;
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
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
      },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return;

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_like",
      title: `${params.milestone} orang menyukai Feed kamu`,
      message: `Postingan ${quoteFeedTitle(
        post.title
      )} mendapat beberapa like baru.`,
      feedPostId: post.id,
      thumbnailUrl: feedNotificationThumbnail(post),
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan",
      tag: `feed-milestone-${post.id}-${params.milestone}`,
      data: { milestone: String(params.milestone) },
      surface: SOCIAL_NOTIFICATION_SOURCE,
    });
  } catch (err) {
    console.warn("[feed-activity] sendLikeMilestoneNotification:", err);
  }
}

export async function sendLikeNotification(params: {
  postId: string;
  actorUserId: string;
  likeCount: number;
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
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
      },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return;
    if (post.authorId === params.actorUserId) return;

    const thumb = feedNotificationThumbnail(post);

    const actor = await prisma.user.findUnique({
      where: { id: params.actorUserId },
      select: { name: true, role: true, profilePhotoUrl: true },
    });
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl,
    );

    const since = new Date(Date.now() - LIKE_BATCH_WINDOW_MS);
    const recentUnread = await prisma.announcement.findFirst({
      where: {
        targetUserId: post.authorId,
        source: SOCIAL_NOTIFICATION_SOURCE,
        eventType: "feed_new_like",
        feedPostId: post.id,
        createdAt: { gte: since },
        reads: { none: { userId: post.authorId } },
      },
      select: { id: true, lastPushedAt: true },
      orderBy: { createdAt: "desc" },
    });

    if (recentUnread) {
      const topLikers = await prisma.feedLike.findMany({
        where: { postId: post.id },
        orderBy: { createdAt: "desc" },
        take: 3,
        select: { user: { select: { role: true, profilePhotoUrl: true } } },
      });
      const avatarUrls = topLikerAvatars(topLikers.map((l) => l.user));

      const aggTitle = `${params.likeCount} orang menyukai Feed kamu`;
      const aggBody = `Postingan ${quoteFeedTitle(
        post.title
      )} mendapat beberapa like baru.`;
      const nowDate = new Date();
      const doPush = shouldRePush(recentUnread.lastPushedAt, nowDate);

      await prisma.announcement.update({
        where: { id: recentUnread.id },
        data: {
          title: aggTitle,
          body: aggBody,
          thumbnailUrl: thumb,
          ...likeRowActorFields(true, actorFields),
          actorAvatarUrls: avatarUrls,
          aggregatedCount: params.likeCount,
          publishedAt: nowDate,
          ...(doPush ? { lastPushedAt: nowDate } : {}),
        },
      });

      // Re-push ter-throttle (Keputusan 2 spec agregasi): tray ikut segar
      // ala IG — Android replace via tag, iOS via apns-collapse-id. Maks
      // 1 push per 5 menit per baris; di antaranya in-app saja (real-time
      // list menangkap gratis).
      if (doPush) {
        const likePayload: PushPayload = {
          title: aggTitle,
          body: aggBody,
          url: feedPostOwnerUrl(post.id),
          tag: `feed-like-${post.id}`,
          imageUrl: thumb,
          prefCategory: "feed",
          renderClientSide: true,
          actorAvatarUrl: actorFields.actorAvatarUrl,
          data: {
            source: SOCIAL_NOTIFICATION_SOURCE,
            type: "feed_new_like",
            post_id: post.id,
            like_count: String(params.likeCount),
            url: feedPostOwnerUrl(post.id),
          },
        };
        await Promise.allSettled([
          sendPushToUser(post.authorId, likePayload),
          sendFcmToUser(post.authorId, likePayload),
        ]);
      }
      return;
    }

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_like",
      title: "Feed kamu mendapat like baru",
      message: `${NOTIF_ACTOR_NAME_TOKEN} menyukai postingan ${quoteFeedTitle(post.title)}.`,
      feedPostId: post.id,
      thumbnailUrl: thumb,
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan",
      tag: `feed-like-${post.id}`,
      data: { like_count: String(params.likeCount) },
      actorId: params.actorUserId,
      actor: { avatarUrl: actorFields.actorAvatarUrl, name: actorFields.actorName },
      surface: SOCIAL_NOTIFICATION_SOURCE,
    });
  } catch (err) {
    console.warn("[feed-activity] sendLikeNotification:", err);
  }
}

/**
 * Fired saat komentar user di-like orang lain. Notif ke author komentar.
 * Skip self-like + skip kalau author komentar = admin (akun official,
 * tidak ada recipient manusia). Debounce: kalau ada notif comment-like
 * unread untuk komentar yg sama dalam window, update (bukan spam baru) —
 * cegah notif beruntun saat like/unlike cepat atau banyak yg like.
 */
export async function sendCommentLikeNotification(params: {
  commentId: string;
  postId: string;
  commentAuthorId: string;
  actorUserId: string;
  likeCount: number;
}) {
  try {
    if (!params.commentAuthorId) return;
    if (params.commentAuthorId === params.actorUserId) return; // self-like

    const author = await prisma.user.findUnique({
      where: { id: params.commentAuthorId },
      select: { role: true },
    });
    if (!author) return;
    if (author.role === "ADMIN") return; // akun official, no recipient

    const post = await prisma.feedPost.findUnique({
      where: { id: params.postId },
      select: {
        thumbnailUrl: true,
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
      },
    });

    const actor = await prisma.user.findUnique({
      where: { id: params.actorUserId },
      select: { name: true, role: true, profilePhotoUrl: true },
    });
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl,
    );

    const since = new Date(Date.now() - LIKE_BATCH_WINDOW_MS);
    const recentUnread = await prisma.announcement.findFirst({
      where: {
        targetUserId: params.commentAuthorId,
        source: SOCIAL_NOTIFICATION_SOURCE,
        eventType: "feed_new_like",
        createdAt: { gte: since },
        tag: `feed-comment-like-${params.commentId}`,
        reads: { none: { userId: params.commentAuthorId } },
      },
      select: { id: true },
      orderBy: { createdAt: "desc" },
    });

    if (recentUnread) {
      const topLikers = await prisma.feedCommentLike.findMany({
        where: { commentId: params.commentId },
        orderBy: { createdAt: "desc" },
        take: 3,
        select: { user: { select: { role: true, profilePhotoUrl: true } } },
      });
      const avatarUrls = topLikerAvatars(topLikers.map((l) => l.user));

      await prisma.announcement.update({
        where: { id: recentUnread.id },
        data: {
          title: `${params.likeCount} orang menyukai komentarmu`,
          // Overwrite body juga — create tunggal kini bernama ("Andi menyukai
          // komentarmu"); tanpa ini baris agregat kontradiktif (judul "N orang"
          // + body nama satu liker). Selaras dgn jalur post-like.
          body: "Beberapa orang menyukai komentarmu di Feed.",
          ...likeRowActorFields(true, actorFields),
          actorAvatarUrls: avatarUrls,
          publishedAt: new Date(),
        },
      });
      return;
    }

    await createFeedNotification({
      userId: params.commentAuthorId,
      eventType: "feed_new_like",
      title: "Komentarmu mendapat like",
      message: `${NOTIF_ACTOR_NAME_TOKEN} menyukai komentarmu di Feed.`,
      feedPostId: params.postId,
      thumbnailUrl: post ? feedNotificationThumbnail(post) : null,
      url: feedPostOwnerUrl(params.postId),
      ctaLabel: "Lihat Komentar",
      tag: `feed-comment-like-${params.commentId}`,
      commentId: params.commentId,
      data: {
        comment_id: params.commentId,
        like_count: String(params.likeCount),
      },
      actorId: params.actorUserId,
      actor: { avatarUrl: actorFields.actorAvatarUrl, name: actorFields.actorName },
      surface: SOCIAL_NOTIFICATION_SOURCE,
    });
  } catch (err) {
    console.warn("[feed-activity] sendCommentLikeNotification:", err);
  }
}

export async function sendShareNotification(params: {
  postId: string;
  shareCount: number;
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
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
      },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return;

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_share",
      title: "Feed kamu dibagikan",
      message: `Postingan ${quoteFeedTitle(post.title)} baru saja dibagikan.`,
      feedPostId: post.id,
      thumbnailUrl: feedNotificationThumbnail(post),
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan",
      tag: `feed-share-${post.id}`,
      data: { share_count: String(params.shareCount) },
      surface: SOCIAL_NOTIFICATION_SOURCE,
    });
  } catch (err) {
    console.warn("[feed-activity] sendShareNotification:", err);
  }
}
