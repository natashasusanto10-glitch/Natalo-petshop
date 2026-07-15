/**
 * PATCH /api/admin/feed/comments/[id]
 *   Body: { action: "hide" | "unhide", reason?: string }
 *
 * DELETE /api/admin/feed/comments/[id]
 *   Soft-delete while retaining a synchronization tombstone.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  countedFeedCommentWhere,
  readDatabaseClock,
} from "@/lib/feed/comment-sync";

type RouteContext = { params: Promise<{ id: string }> };

async function requireAdmin(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return { response: csrfReject };

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return {
      response: NextResponse.json({ error: "Unauthorized" }, { status: 401 }),
    };
  }
  return { session };
}

export async function PATCH(request: NextRequest, { params }: RouteContext) {
  const authorized = await requireAdmin(request);
  if ("response" in authorized) return authorized.response;

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID required" }, { status: 400 });
  }

  const body = await request.json().catch(() => ({}));
  const action = String((body as { action?: unknown }).action ?? "");
  const rawReason = (body as { reason?: unknown }).reason;
  const reason =
    typeof rawReason === "string" ? rawReason.trim().slice(0, 500) : "";
  if (action !== "hide" && action !== "unhide") {
    return NextResponse.json(
      { error: "Action harus 'hide' atau 'unhide'." },
      { status: 400 }
    );
  }

  const locator = await prisma.feedComment.findUnique({
    where: { id: commentId },
    select: { postId: true },
  });
  if (!locator) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 }
    );
  }

  const result = await prisma.$transaction(async (tx) => {
    const lockedPosts = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT "id"
      FROM "FeedPost"
      WHERE "id" = ${locator.postId}
      FOR UPDATE
    `;
    if (lockedPosts.length === 0) return { kind: "not-found" } as const;

    const comment = await tx.feedComment.findUnique({
      where: { id: commentId },
      select: { isHidden: true, deletedAt: true, postId: true },
    });
    if (!comment || comment.postId !== locator.postId || comment.deletedAt) {
      return { kind: "not-found" } as const;
    }
    if (action === "hide" && comment.isHidden) {
      return { kind: "already-hidden" } as const;
    }
    if (action === "unhide" && !comment.isHidden) {
      return { kind: "already-visible" } as const;
    }

    const visibilityChangedAt = await readDatabaseClock(tx);
    const updated = await tx.feedComment.update({
      where: { id: commentId },
      data: {
        isHidden: action === "hide",
        hiddenById: action === "hide" ? authorized.session.sub : null,
        hiddenAt: action === "hide" ? visibilityChangedAt : null,
        hiddenReason: action === "hide" ? reason || null : null,
        updatedAt: visibilityChangedAt,
      },
      select: { id: true, isHidden: true, hiddenReason: true },
    });
    const commentCount = await tx.feedComment.count({
      where: countedFeedCommentWhere(locator.postId),
    });
    await tx.feedPost.update({
      where: { id: locator.postId },
      data: { commentCount },
    });
    return { kind: "updated", comment: updated } as const;
  });

  if (result.kind === "not-found") {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 }
    );
  }
  if (result.kind === "already-hidden") {
    return NextResponse.json(
      { error: "Komentar sudah disembunyikan." },
      { status: 409 }
    );
  }
  if (result.kind === "already-visible") {
    return NextResponse.json(
      { error: "Komentar belum disembunyikan." },
      { status: 409 }
    );
  }
  return NextResponse.json({ ok: true, comment: result.comment });
}

export async function DELETE(request: NextRequest, { params }: RouteContext) {
  const authorized = await requireAdmin(request);
  if ("response" in authorized) return authorized.response;

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID required" }, { status: 400 });
  }

  const locator = await prisma.feedComment.findUnique({
    where: { id: commentId },
    select: { postId: true },
  });
  if (!locator) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 }
    );
  }

  const found = await prisma.$transaction(async (tx) => {
    const lockedPosts = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT "id"
      FROM "FeedPost"
      WHERE "id" = ${locator.postId}
      FOR UPDATE
    `;
    if (lockedPosts.length === 0) return false;

    const comment = await tx.feedComment.findUnique({
      where: { id: commentId },
      select: { deletedAt: true, postId: true, isHidden: true },
    });
    if (!comment || comment.postId !== locator.postId) return false;

    if (!comment.deletedAt || !comment.isHidden) {
      const deletedAt = await readDatabaseClock(tx);
      await tx.feedComment.update({
        where: { id: commentId },
        data: {
          deletedAt: comment.deletedAt ?? deletedAt,
          isHidden: true,
          hiddenById: authorized.session.sub,
          hiddenAt: deletedAt,
          hiddenReason: "Dihapus moderator",
        },
      });
    }
    const commentCount = await tx.feedComment.count({
      where: countedFeedCommentWhere(locator.postId),
    });
    await tx.feedPost.update({
      where: { id: locator.postId },
      data: { commentCount },
    });
    return true;
  });

  if (!found) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 }
    );
  }
  return NextResponse.json({ ok: true });
}
