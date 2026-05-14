/**
 * GET /api/feed/posts/[id]/comments?cursor=<commentId>  — list (lazy)
 * POST /api/feed/posts/[id]/comments  — add comment (auth required)
 *
 * Spec 10.7: comments lazy-loaded. User tap icon comment → load 20+pagination.
 * Posting: transaction supaya commentCount counter di-sync atomic.
 * Admin reply (parentCommentId set, isAdminOfficial=true) belum di-implement
 * dalam endpoint ini — admin akan reply via /api/admin/feed/* di F5.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { listFeedComments } from "@/lib/feed/queries";

const MAX_COMMENT_LENGTH = 1000;

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
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

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Login dulu untuk komentar." }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: { id: true, status: true },
  });
  if (!post || post.status !== "ACTIVE") {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  const body = await request.json().catch(() => ({}));
  const content = String((body as { content?: unknown }).content ?? "").trim();
  if (!content) {
    return NextResponse.json({ error: "Komentar tidak boleh kosong." }, { status: 400 });
  }
  if (content.length > MAX_COMMENT_LENGTH) {
    return NextResponse.json(
      { error: `Komentar maksimal ${MAX_COMMENT_LENGTH} karakter.` },
      { status: 400 },
    );
  }
  const rawParent = (body as { parentCommentId?: unknown }).parentCommentId;
  const parentCommentId = typeof rawParent === "string" && rawParent ? rawParent : null;

  // Verify parent comment exists + masih di post yang sama (kalau ada).
  if (parentCommentId) {
    const parent = await prisma.feedComment.findUnique({
      where: { id: parentCommentId },
      select: { id: true, postId: true, isHidden: true },
    });
    if (!parent || parent.postId !== postId || parent.isHidden) {
      return NextResponse.json(
        { error: "Komentar parent tidak valid." },
        { status: 400 },
      );
    }
  }

  const isAdmin = session.role === "ADMIN";

  const result = await prisma.$transaction(async (tx) => {
    const comment = await tx.feedComment.create({
      data: {
        postId,
        authorId: session.sub,
        parentCommentId,
        content,
        isAdminOfficial: isAdmin,
      },
      include: {
        author: { select: { id: true, name: true, role: true } },
      },
    });
    // Increment commentCount on post (only count top-level for badge).
    if (parentCommentId === null) {
      await tx.feedPost.update({
        where: { id: postId },
        data: { commentCount: { increment: 1 } },
      });
    }
    return comment;
  });

  return NextResponse.json({
    ok: true,
    comment: {
      id: result.id,
      postId: result.postId,
      parentCommentId: result.parentCommentId,
      content: result.content,
      isAdminOfficial: result.isAdminOfficial,
      isHidden: false,
      likeCount: 0,
      createdAt: result.createdAt.toISOString(),
      author: {
        id: result.author.id,
        name: result.author.name,
        role: (result.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as "ADMIN" | "CUSTOMER",
      },
      viewerLiked: false,
    },
  });
}
