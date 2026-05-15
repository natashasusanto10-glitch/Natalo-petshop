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
 *   - Like milestone crossed on a post    → notify post author (10/100/1000)
 *
 * Self-notify is always skipped — never notify yourself for your own
 * activity. Errors are swallowed (notification helpers never throw)
 * because telemetry/notification failures must not block the user-facing
 * action that triggered them.
 */

import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";

const FEED_NOTIF_TYPE = "feed";
// Push notifications fire only when the cumulative like count crosses one
// of these thresholds. Avoids "Andi liked your post" spam every time
// somebody taps the heart. Order matters — first match wins.
const LIKE_MILESTONES = [10, 50, 100, 500, 1000, 5000, 10000];

function truncate(input: string, limit = 80): string {
  const trimmed = input.trim();
  if (trimmed.length <= limit) return trimmed;
  return `${trimmed.slice(0, limit - 1)}…`;
}

async function fanout(userId: string, payload: PushPayload) {
  try {
    await Promise.all([
      sendPushToUser(userId, payload),
      sendApnsToUser(userId, payload),
      sendFcmToUser(userId, payload),
      prisma.announcement
        .create({
          data: {
            title: payload.title,
            body: payload.body,
            url: payload.url ?? "/notifications",
            segment: "all",
            type: FEED_NOTIF_TYPE,
            ctaLabel: "Lihat",
            publishedAt: new Date(),
            targetUserId: userId,
          },
        })
        .catch((err) => {
          console.warn("[feed-activity] failed to insert Announcement:", err);
        }),
    ]);
  } catch (err) {
    console.warn("[feed-activity] fanout failed:", err);
  }
}

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
      select: { id: true, authorId: true, authorRole: true },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return; // admin posts have no human recipient
    if (post.authorId === params.actorUserId) return; // self-comment, no notif

    const actor = await prisma.user.findUnique({
      where: { id: params.actorUserId },
      select: { name: true },
    });
    const actorName = actor?.name?.trim() || "Seseorang";

    const payload: PushPayload = {
      title: "Komentar baru di videomu",
      body: `${actorName}: ${truncate(params.content)}`,
      url: `/feed?post=${params.postId}`,
      tag: `feed-comment-${params.postId}`,
      data: {
        type: FEED_NOTIF_TYPE,
        subtype: "comment",
        post_id: params.postId,
        comment_id: params.commentId,
      },
    };
    await fanout(post.authorId, payload);
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

    const payload: PushPayload = {
      title: `${actorName} balas komentarmu`,
      body: truncate(params.content),
      url: `/feed?post=${params.postId}`,
      tag: `feed-reply-${params.parentCommentId}`,
      data: {
        type: FEED_NOTIF_TYPE,
        subtype: "reply",
        post_id: params.postId,
        parent_comment_id: params.parentCommentId,
        reply_comment_id: params.replyCommentId,
      },
    };
    await fanout(parent.authorId, payload);
  } catch (err) {
    console.warn("[feed-activity] sendReplyNotification:", err);
  }
}

/**
 * Was a milestone crossed between two likeCount snapshots? Returns the
 * milestone value, or null if no boundary in (prev, next].
 */
export function crossedLikeMilestone(prev: number, next: number): number | null {
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
      select: { id: true, authorId: true, authorRole: true, title: true },
    });
    if (!post || !post.authorId) return;
    if (post.authorRole === "ADMIN") return;

    const emoji = params.milestone >= 1000 ? "🚀" : params.milestone >= 100 ? "🔥" : "🎉";
    const payload: PushPayload = {
      title: `${emoji} Postingan kamu ${params.milestone} like!`,
      body: post.title
        ? truncate(post.title)
        : "Video kamu makin disukai komunitas Natalo.",
      url: `/feed?post=${params.postId}`,
      tag: `feed-milestone-${params.postId}-${params.milestone}`,
      data: {
        type: FEED_NOTIF_TYPE,
        subtype: "like-milestone",
        post_id: params.postId,
        milestone: String(params.milestone),
      },
    };
    await fanout(post.authorId, payload);
  } catch (err) {
    console.warn("[feed-activity] sendLikeMilestoneNotification:", err);
  }
}
