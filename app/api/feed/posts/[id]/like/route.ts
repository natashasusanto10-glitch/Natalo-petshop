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
import { after, NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { sendLikeNotification } from "@/lib/feed/activity-notifications";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
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
      select: { id: true, status: true, deletedAt: true },
    })
    .catch(() => null);
  if (!post || post.status !== "ACTIVE" || post.deletedAt) {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 }
    );
  }

  // Toggle dalam transaction supaya counter tidak drift saat concurrent.
  // Try-create: kalau sudah ada (P2002 unique violation), berarti unlike.
  const result = await prisma.$transaction(async (tx) => {
    const existing = await tx.feedLike.findUnique({
      where: { userId_postId: { userId: session.sub, postId } },
    });

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
    };
  });

  // Non-blocking via `after()` (bukan `void`) — void promise bisa dibekukan
  // Vercel sebelum jalan → notif like hilang; after() dijamin eksekusi
  // setelah response, jadi like tetap terasa instan. Helper batches recent
  // likes and skips self/admin cases; error ditelan internal.
  if (result.liked) {
    after(() =>
      sendLikeNotification({
        postId,
        actorUserId: session.sub,
        likeCount: result.likeCount,
      }),
    );
  }

  const recentLikes = await prisma.feedLike.findMany({
    where: { postId },
    orderBy: { createdAt: "desc" },
    take: 3,
    select: {
      user: {
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

  return NextResponse.json({
    ok: true,
    liked: result.liked,
    likeCount: result.likeCount,
    recentLikers: recentLikes.map((like) => ({
      id: like.user.id,
      name: like.user.name,
      username: like.user.username,
      role: like.user.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
      profilePhotoUrl: like.user.profilePhotoUrl,
      avatarUrl: like.user.profilePhotoUrl,
    })),
  });
}
