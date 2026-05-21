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

import { prisma } from "@/lib/prisma";
import {
  createFeedNotification,
  feedPostOwnerUrl,
  quoteFeedTitle,
  truncateFeedText,
} from "@/lib/feed/notification-center";

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
      },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return; // admin posts have no human recipient
    if (post.authorId === params.actorUserId) return; // self-comment, no notif

    const actor = await prisma.user.findUnique({
      where: { id: params.actorUserId },
      select: { name: true },
    });
    const actorName = actor?.name?.trim() || "Seseorang";

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_comment",
      title: "Komentar baru di Feed kamu",
      message: `${actorName} mengomentari postingan ${quoteFeedTitle(
        post.title
      )}: ${truncateFeedText(params.content)}`,
      feedPostId: post.id,
      thumbnailUrl: post.thumbnailUrl,
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Komentar",
      tag: `feed-comment-${post.id}`,
      data: { comment_id: params.commentId },
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
      select: { name: true },
    });
    const actorName = actor?.name?.trim() || "Seseorang";

    const post = await prisma.feedPost.findUnique({
      where: { id: params.postId },
      select: { id: true, title: true, thumbnailUrl: true },
    });

    await createFeedNotification({
      userId: parent.authorId,
      eventType: "feed_new_comment",
      title: `${actorName} membalas komentarmu`,
      message: truncateFeedText(params.content),
      feedPostId: params.postId,
      thumbnailUrl: post?.thumbnailUrl ?? null,
      url: feedPostOwnerUrl(params.postId),
      ctaLabel: "Lihat Balasan",
      tag: `feed-reply-${params.parentCommentId}`,
      data: {
        parent_comment_id: params.parentCommentId,
        reply_comment_id: params.replyCommentId,
      },
    });
  } catch (err) {
    console.warn("[feed-activity] sendReplyNotification:", err);
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
      thumbnailUrl: post.thumbnailUrl,
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan",
      tag: `feed-milestone-${post.id}-${params.milestone}`,
      data: { milestone: String(params.milestone) },
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
      },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return;
    if (post.authorId === params.actorUserId) return;

    const since = new Date(Date.now() - LIKE_BATCH_WINDOW_MS);
    const recentUnread = await prisma.announcement.findFirst({
      where: {
        targetUserId: post.authorId,
        source: "feed",
        eventType: "feed_new_like",
        feedPostId: post.id,
        createdAt: { gte: since },
        reads: { none: { userId: post.authorId } },
      },
      select: { id: true },
      orderBy: { createdAt: "desc" },
    });

    if (recentUnread) {
      await prisma.announcement.update({
        where: { id: recentUnread.id },
        data: {
          title: `${params.likeCount} orang menyukai Feed kamu`,
          body: `Postingan ${quoteFeedTitle(
            post.title
          )} mendapat beberapa like baru.`,
          thumbnailUrl: post.thumbnailUrl,
          publishedAt: new Date(),
        },
      });
      return;
    }

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_like",
      title: "Feed kamu mendapat like baru",
      message: `Postingan ${quoteFeedTitle(
        post.title
      )} disukai oleh pengguna lain.`,
      feedPostId: post.id,
      thumbnailUrl: post.thumbnailUrl,
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan",
      tag: `feed-like-${post.id}`,
      data: { like_count: String(params.likeCount) },
    });
  } catch (err) {
    console.warn("[feed-activity] sendLikeNotification:", err);
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
      thumbnailUrl: post.thumbnailUrl,
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan",
      tag: `feed-share-${post.id}`,
      data: { share_count: String(params.shareCount) },
    });
  } catch (err) {
    console.warn("[feed-activity] sendShareNotification:", err);
  }
}
