/**
 * GET /api/feed/my-posts?status=all|pending|active|rejected
 *
 * Return list postingan video user yang sedang login (kind=COMMUNITY).
 * Match perilaku PWA `app/akun/postingan-saya/page.tsx` — dipakai oleh
 * Flutter mobile app untuk render screen "Postingan Saya".
 *
 * Aturan visibility:
 * - Hanya post milik session user
 * - Hanya status PENDING_REVIEW / ACTIVE / REJECTED (skip DRAFT / arsip)
 * - deletedAt: null (skip soft-deleted)
 *
 * Read-only. No mutation.
 */
import { NextRequest, NextResponse } from "next/server";
import type { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  MY_FEED_STATUS_BY_FILTER,
  MY_FEED_VISIBLE_STATUSES,
  normalizeMyFeedFilter,
} from "@/lib/feed/my-posts";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "LOGIN_REQUIRED", message: "Login dulu untuk lihat postingan." },
      { status: 401 },
    );
  }

  const statusParam = request.nextUrl.searchParams.get("status") ?? undefined;
  const filter = normalizeMyFeedFilter(statusParam ?? undefined);
  const selectedStatus =
    filter === "all" ? undefined : MY_FEED_STATUS_BY_FILTER[filter];

  const baseWhere: Prisma.FeedPostWhereInput = {
    authorId: session.sub,
    authorRole: "CUSTOMER",
    kind: "COMMUNITY",
    deletedAt: null,
    status: { in: [...MY_FEED_VISIBLE_STATUSES] },
  };
  const where: Prisma.FeedPostWhereInput = {
    ...baseWhere,
    status: selectedStatus ?? { in: [...MY_FEED_VISIBLE_STATUSES] },
  };

  const [rawPosts, totalCount] = await Promise.all([
    prisma.feedPost.findMany({
      where,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      select: {
        id: true,
        title: true,
        description: true,
        thumbnailUrl: true,
        videoUrl: true,
        videoDurationSec: true,
        createdAt: true,
        status: true,
        moderationNote: true,
        likeCount: true,
        commentCount: true,
        shareCount: true,
      },
    }),
    prisma.feedPost.count({ where: baseWhere }),
  ]);

  return NextResponse.json({
    posts: rawPosts.map((post) => ({
      id: post.id,
      title: post.title,
      description: post.description,
      thumbnailUrl: post.thumbnailUrl,
      videoUrl: post.videoUrl,
      videoDurationSec: post.videoDurationSec,
      createdAt: post.createdAt.toISOString(),
      status: post.status,
      moderationNote: post.moderationNote,
      likeCount: post.likeCount,
      commentCount: post.commentCount,
      shareCount: post.shareCount,
    })),
    filter,
    totalCount,
  });
}
