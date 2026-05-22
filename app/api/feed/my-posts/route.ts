/**
 * GET /api/feed/my-posts?status=all|pending|active|rejected
 *
 * Return list postingan user yang sedang login (video COMMUNITY + foto
 * PHOTO_CAROUSEL).
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
import { bunnyThumbnailUrl, signBunnyUrl } from "@/lib/feed/bunny";

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
    kind: { in: ["COMMUNITY", "PHOTO_CAROUSEL"] },
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
        kind: true,
        title: true,
        description: true,
        thumbnailUrl: true,
        videoGuid: true,
        videoUrl: true,
        videoDurationSec: true,
        videoWidth: true,
        videoHeight: true,
        createdAt: true,
        status: true,
        moderationNote: true,
        likeCount: true,
        commentCount: true,
        shareCount: true,
        viewCount: true,
        media: {
          orderBy: { sortOrder: "asc" },
          select: {
            id: true,
            mediaType: true,
            url: true,
            thumbnailUrl: true,
            width: true,
            height: true,
            sortOrder: true,
          },
        },
      },
    }),
    prisma.feedPost.count({ where: baseWhere }),
  ]);

  // Lookup viewerLiked per post — Flutter pakai field ini buat hydrate
  // _likedCache awal di My Posts screen. Tanpa ini, post yang user
  // sudah pernah like tampil grey di icon, dan tap pertama bakal
  // accidentally UN-LIKE (backend toggle berdasar DB, bukan trust
  // `currentlyLiked` dari client). Lihat bug "klik 1x hilang".
  //
  // 1 query batch via { postId: { in: ids } } — index pada
  // FeedLike.userId_postId membuat lookup O(log n).
  const viewerLikedIds = rawPosts.length === 0
    ? new Set<string>()
    : new Set(
        (
          await prisma.feedLike.findMany({
            where: {
              userId: session.sub,
              postId: { in: rawPosts.map((p) => p.id) },
            },
            select: { postId: true },
          })
        ).map((l) => l.postId),
      );

  return NextResponse.json({
    posts: rawPosts.map((post) => {
      const signedMedia = post.media.map((item) => ({
        id: item.id,
        mediaType: item.mediaType,
        mediaUrl: signBunnyUrl(item.url) ?? item.url,
        thumbnailUrl:
          signBunnyUrl(item.thumbnailUrl ?? item.url) ??
          item.thumbnailUrl ??
          item.url,
        width: item.width,
        height: item.height,
        sortOrder: item.sortOrder,
      }));
      const isPhotoPost = post.kind === "PHOTO_CAROUSEL";
      const firstMedia = signedMedia[0] ?? null;
      const videoUrl = signBunnyUrl(post.videoUrl) ?? null;
      const videoThumbnailUrl =
        signBunnyUrl(
          post.thumbnailUrl ??
            (post.videoGuid ? bunnyThumbnailUrl(post.videoGuid) || null : null),
        ) ?? null;
      const mediaItems = isPhotoPost
        ? signedMedia
        : videoUrl
          ? [
              {
                id: `${post.id}-video`,
                mediaType: "video",
                mediaUrl: videoUrl,
                thumbnailUrl: videoThumbnailUrl,
                durationSeconds: post.videoDurationSec,
                width: post.videoWidth,
                height: post.videoHeight,
                sortOrder: 0,
              },
            ]
          : [];
      const type = isPhotoPost
        ? signedMedia.length > 1
          ? "carousel"
          : "photo"
        : "video";

      return {
        id: post.id,
        kind: post.kind,
        type,
        title: post.title,
        description: post.description,
        // Thumbnail adalah cover grid, bukan sumber deteksi tipe media.
        thumbnailUrl: isPhotoPost
          ? firstMedia?.thumbnailUrl ?? firstMedia?.mediaUrl ?? null
          : videoThumbnailUrl,
        mediaUrl: isPhotoPost ? firstMedia?.mediaUrl ?? "" : videoUrl ?? "",
        videoUrl,
        mediaItems,
        videoDurationSec: post.videoDurationSec,
        durationSec: post.videoDurationSec,
        aspectWidth: isPhotoPost
          ? firstMedia?.width ?? 1
          : post.videoWidth ?? 9,
        aspectHeight: isPhotoPost
          ? firstMedia?.height ?? 1
          : post.videoHeight ?? 16,
        createdAt: post.createdAt.toISOString(),
        status: post.status,
        moderationNote: post.moderationNote,
        likeCount: post.likeCount,
        commentCount: post.commentCount,
        shareCount: post.shareCount,
        viewCount: post.viewCount,
        viewerLiked: viewerLikedIds.has(post.id),
      };
    }),
    filter,
    totalCount,
  });
}
