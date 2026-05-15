/**
 * POST /api/feed/posts/[id]/like
 *
 * Toggle like — kalau user belum like, create FeedLike + increment counter.
 * Kalau sudah like, hapus FeedLike + decrement counter. Idempotent dari
 * sisi UI (FE tinggal toggle visual + call ini; server normalize).
 *
 * Pattern: pakai transaction untuk atomic counter update + like row.
 * Tanpa transaction, race condition saat 2 request concurrent bisa
 * menghasilkan counter drift dari ground truth (FeedLike count).
 *
 * Auth wajib — anon tidak boleh like. Rate limit skip dulu (per-user
 * action, monitorable; kalau ada spam pattern bisa add limit nanti).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  crossedLikeMilestone,
  sendLikeMilestoneNotification,
} from "@/lib/feed/activity-notifications";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const post = await prisma.feedPost
    .findUnique({
      where: { id: postId },
      select: { id: true, status: true },
    })
    .catch(() => null);
  if (!post || post.status !== "ACTIVE") {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  // Toggle dalam transaction supaya counter tidak drift saat concurrent.
  // Try-create: kalau sudah ada (P2002 unique violation), berarti unlike.
  // Also snapshot the previous likeCount so we can detect a milestone
  // crossing on the way back out.
  const result = await prisma.$transaction(async (tx) => {
    const existing = await tx.feedLike.findUnique({
      where: { userId_postId: { userId: session.sub, postId } },
    });

    const before = await tx.feedPost.findUnique({
      where: { id: postId },
      select: { likeCount: true },
    });
    const prevCount = before?.likeCount ?? 0;

    if (existing) {
      await tx.feedLike.delete({
        where: { userId_postId: { userId: session.sub, postId } },
      });
      const updated = await tx.feedPost.update({
        where: { id: postId },
        // decrement floor di 0 supaya tidak negative kalau ada drift.
        data: { likeCount: { decrement: 1 } },
        select: { likeCount: true },
      });
      return {
        liked: false,
        likeCount: Math.max(0, updated.likeCount),
        prevCount,
        nextCount: updated.likeCount,
      };
    }

    await tx.feedLike.create({
      data: { userId: session.sub, postId },
    });
    const updated = await tx.feedPost.update({
      where: { id: postId },
      data: { likeCount: { increment: 1 } },
      select: { likeCount: true },
    });
    return {
      liked: true,
      likeCount: updated.likeCount,
      prevCount,
      nextCount: updated.likeCount,
    };
  });

  // Milestone push fires only on like (not unlike) and only when the new
  // count actually crosses a threshold. Fire-and-forget — helper handles
  // self-notify + admin-author skip internally.
  if (result.liked) {
    const milestone = crossedLikeMilestone(result.prevCount, result.nextCount);
    if (milestone !== null) {
      void sendLikeMilestoneNotification({ postId, milestone });
    }
  }

  return NextResponse.json({
    ok: true,
    liked: result.liked,
    likeCount: result.likeCount,
  });
}
