/**
 * GET /api/feed/posts/[id]/comments?cursor=<commentId>
 *
 * Lazy-loaded — frontend tidak fetch komentar saat feed pertama tampil
 * (sesuai spec section 10.7). User tap icon comment → call endpoint ini.
 *
 * Return top-level comments only (parentCommentId = null). Reply admin
 * di-fetch terpisah per-comment kalau user expand (atau bisa di-eager
 * fetch untuk admin reply badge "Natalo Official" — di F4 nanti).
 *
 * MVP: hanya GET. POST untuk comment user di F4 saat upload flow ready.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { listFeedComments } from "@/lib/feed/queries";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  // Verify post exists + ACTIVE — kalau di-hide/reject, jangan expose comments.
  const post = await prisma.feedPost
    .findUnique({
      where: { id: postId },
      select: { id: true, status: true },
    })
    .catch(() => null);
  if (!post || post.status !== "ACTIVE") {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  const { searchParams } = new URL(request.url);
  const cursor = searchParams.get("cursor") || null;

  const session = await getSession().catch(() => null);
  const result = await listFeedComments({
    postId,
    cursor,
    viewerUserId: session?.sub ?? null,
  });

  return NextResponse.json(result);
}
