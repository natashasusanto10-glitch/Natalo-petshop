import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { MY_FEED_VISIBLE_STATUSES } from "@/lib/feed/my-posts";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const post = await prisma.feedPost.findFirst({
    where: {
      id: postId,
      authorId: session.sub,
      authorRole: "CUSTOMER",
      kind: "COMMUNITY",
      deletedAt: null,
      status: { in: [...MY_FEED_VISIBLE_STATUSES] },
    },
    select: { id: true, status: true },
  });

  if (!post) {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  const now = new Date();
  await prisma.$transaction([
    prisma.feedPost.update({
      where: { id: post.id },
      data: {
        deletedAt: now,
        moderatedById: session.sub,
        moderatedAt: now,
      },
    }),
    prisma.feedModerationLog.create({
      data: {
        postId: post.id,
        actorId: session.sub,
        action: "user_delete",
        fromStatus: post.status,
        toStatus: post.status,
        note: "Deleted by post owner",
      },
    }),
  ]);

  return NextResponse.json({ ok: true });
}
