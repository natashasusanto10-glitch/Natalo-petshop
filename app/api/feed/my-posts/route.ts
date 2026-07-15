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
import type { FeedPostKind, Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  MY_FEED_STATUS_BY_FILTER,
  MY_FEED_VISIBLE_STATUSES,
  normalizeMyFeedFilter,
} from "@/lib/feed/my-posts";
import { bunnyThumbnailUrl, signBunnyUrl } from "@/lib/feed/bunny";
import { buildFeedVideoPlaybackUrls } from "@/lib/feed/video-playback-urls";
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";
import { getViewerSavedPostIds } from "@/lib/feed/queries";
import { feedAccessibilityPayload } from "@/lib/feed/accessibility";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "LOGIN_REQUIRED", message: "Login dulu untuk lihat postingan." },
      { status: 401 }
    );
  }

  const statusParam = request.nextUrl.searchParams.get("status") ?? undefined;
  const filter = normalizeMyFeedFilter(statusParam ?? undefined);
  const selectedStatus =
    filter === "all" ? undefined : MY_FEED_STATUS_BY_FILTER[filter];

  // Pagination — cursor + limit. Default page = 20, max 50. Cursor
  // adalah feedPost.id terakhir dari page sebelumnya. Tanpa cursor,
  // ambil page pertama. Backward-compatible: kalau cursor/limit tidak
  // di-set, return semua sampai 20 post pertama.
  const cursor = request.nextUrl.searchParams.get("cursor") || null;
  const rawLimit = Number(request.nextUrl.searchParams.get("limit") ?? "20");
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(50, Math.max(1, Math.floor(rawLimit)))
      : 20;

  const isAdmin = session.role === "ADMIN";
  const visibleKinds: FeedPostKind[] = isAdmin
    ? ["VIDEO_ONLY", "VIDEO_PRODUCT", "PROMO", "PHOTO_CAROUSEL", "COMMUNITY"]
    : ["COMMUNITY", "PHOTO_CAROUSEL"];

  const baseWhere: Prisma.FeedPostWhereInput = {
    authorId: session.sub,
    authorRole: session.role,
    kind: { in: visibleKinds },
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
      // take + 1 untuk detect hasMore. Cursor skip current item supaya
      // tidak duplicate antar page (Prisma cursor pattern standard).
      take: limit + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
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
        videoAltText: true,
        hasAudio: true,
        subtitleUrl: true,
        subtitleLanguage: true,
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
            altText: true,
          },
        },
        likes: {
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
        },
        // Produk yang di-tag di post — TANPA ini tab "Produk Ditag" di
        // profil user selalu kosong (Flutter productIds derive dari
        // products yg tidak terkirim). Ordered by position untuk konsisten
        // dgn carousel di feed.
        taggedProducts: {
          orderBy: { position: "asc" },
          select: {
            product: {
              select: {
                id: true,
                slug: true,
                name: true,
                price: true,
                discountPrice: true,
                stock: true,
                weightGram: true,
                isActive: true,
                imageUrl: true,
                hasVariants: true,
                avgRating: true,
                reviewCount: true,
              },
            },
          },
        },
      },
    }),
    prisma.feedPost.count({ where: baseWhere }),
  ]);

  // Detect hasMore via `take + 1` pattern. Slice ke `limit` items asli,
  // kalau extra item exists berarti ada next page.
  const hasMore = rawPosts.length > limit;
  const slicedPosts = hasMore ? rawPosts.slice(0, limit) : rawPosts;
  const nextCursor = hasMore ? slicedPosts[slicedPosts.length - 1].id : null;

  // Lookup viewerLiked per post — Flutter pakai field ini buat hydrate
  // _likedCache awal di My Posts screen. Tanpa ini, post yang user
  // sudah pernah like tampil grey di icon, dan tap pertama bakal
  // accidentally UN-LIKE (backend toggle berdasar DB, bukan trust
  // `currentlyLiked` dari client). Lihat bug "klik 1x hilang".
  //
  // 1 query batch via { postId: { in: ids } } — index pada
  // FeedLike.userId_postId membuat lookup O(log n).
  const viewerLikedIds =
    slicedPosts.length === 0
      ? new Set<string>()
      : new Set(
          (
            await prisma.feedLike.findMany({
              where: {
                userId: session.sub,
                postId: { in: slicedPosts.map((p) => p.id) },
              },
              select: { postId: true },
            })
          ).map((l) => l.postId)
        );

  const viewerSavedIds = await getViewerSavedPostIds(
    session.sub,
    slicedPosts.map((post) => post.id)
  );

  return NextResponse.json({
    posts: slicedPosts.map((post) => {
      const signedMedia = post.media.map((item) => {
        const mediaPlaybackUrls = buildFeedVideoPlaybackUrls({
          videoUrl: item.url,
        });
        return {
          id: item.id,
          mediaType: item.mediaType,
          mediaUrl: mediaPlaybackUrls.videoUrl ?? item.url,
          ...(item.mediaType === "video"
            ? { videoDataSaverUrl: mediaPlaybackUrls.videoDataSaverUrl }
            : {}),
          thumbnailUrl:
            signBunnyUrl(item.thumbnailUrl ?? item.url) ??
            item.thumbnailUrl ??
            item.url,
          width: item.width,
          height: item.height,
          sortOrder: item.sortOrder,
          altText: item.altText,
        };
      });
      const isPhotoPost = post.kind === "PHOTO_CAROUSEL";
      const firstMedia = signedMedia[0] ?? null;
      const playbackUrls = buildFeedVideoPlaybackUrls({
        videoUrl: post.videoUrl,
        videoGuid: post.videoGuid,
      });
      const videoUrl = playbackUrls.videoUrl;
      const videoThumbnailUrl =
        signBunnyUrl(
          post.thumbnailUrl ??
            (post.videoGuid ? bunnyThumbnailUrl(post.videoGuid) || null : null)
        ) ?? null;
      const mediaItems = isPhotoPost
        ? signedMedia
        : videoUrl
        ? [
            {
              id: `${post.id}-video`,
              mediaType: "video",
              mediaUrl: videoUrl,
              videoDataSaverUrl: playbackUrls.videoDataSaverUrl,
              thumbnailUrl: videoThumbnailUrl,
              durationSeconds: post.videoDurationSec,
              width: post.videoWidth,
              height: post.videoHeight,
              sortOrder: 0,
              altText: post.videoAltText,
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
        videoDataSaverUrl: playbackUrls.videoDataSaverUrl,
        mediaItems,
        videoDurationSec: post.videoDurationSec,
        durationSec: post.videoDurationSec,
        ...feedAccessibilityPayload(post, signBunnyUrl),
        aspectWidth: isPhotoPost
          ? firstMedia?.width ?? 4
          : post.videoWidth ?? 9,
        aspectHeight: isPhotoPost
          ? firstMedia?.height ?? 5
          : post.videoHeight ?? 16,
        createdAt: post.createdAt.toISOString(),
        status: post.status,
        moderationNote: post.moderationNote,
        likeCount: post.likeCount,
        commentCount: post.commentCount,
        shareCount: post.shareCount,
        viewCount: post.viewCount,
        viewerLiked: viewerLikedIds.has(post.id),
        viewerSaved: viewerSavedIds.has(post.id),
        recentLikers: post.likes.map((like) => ({
          id: like.user.id,
          name: brandDisplayName(like.user.role, like.user.name),
          username: like.user.username,
          role: like.user.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
          profilePhotoUrl: brandPhotoUrl(
            like.user.role,
            like.user.profilePhotoUrl
          ),
          avatarUrl: brandPhotoUrl(like.user.role, like.user.profilePhotoUrl),
        })),
        // Produk yang di-tag → Flutter FeedPost.fromJson baca `products`
        // → productIds non-empty → muncul di tab "Produk Ditag". Shape
        // FeedProductLink (sama dgn reels feed).
        products: post.taggedProducts
          .filter((t) => t.product)
          .map((t) => ({
            id: t.product!.id,
            slug: t.product!.slug,
            name: t.product!.name,
            price: t.product!.price,
            discountPrice: t.product!.discountPrice,
            stock: t.product!.stock,
            weightGram: t.product!.weightGram,
            isActive: t.product!.isActive,
            imageUrl: t.product!.imageUrl,
            hasVariants: t.product!.hasVariants,
            avgRating: t.product!.avgRating ?? 0,
            reviewCount: t.product!.reviewCount ?? 0,
          })),
      };
    }),
    filter,
    totalCount,
    nextCursor,
    hasMore,
  });
}
