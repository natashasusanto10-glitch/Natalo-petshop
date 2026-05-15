/**
 * Feed read queries — shared antara API route handlers + (kalau perlu) SSR.
 *
 * Pagination pakai cursor (id + publishedAt|createdAt composite) supaya
 * stabil saat insert/delete di tengah list. Lebih reliable dari offset
 * pagination yg geser saat ada post baru.
 *
 * Public feed is a single TikTok-style stream. `tab` remains optional for
 * legacy/admin callers, but the storefront no longer exposes tab columns.
 */
import { prisma } from "@/lib/prisma";
import type { FeedPostTab } from "@prisma/client";
import type {
  FeedCommentItem,
  FeedCommentsResponse,
  FeedListResponse,
  FeedPostListItem,
} from "./types";

const FEED_PAGE_SIZE = 10;
const COMMENT_PAGE_SIZE = 20;

type FeedListOptions = {
  tab?: FeedPostTab | null;
  cursor?: string | null;
  viewerUserId?: string | null;
};

/**
 * List feed posts. Pakai cursor pagination (id terakhir
 * yg di-render). Sort by createdAt desc; publishedAt belum reliable
 * (akan di-set saat F4 saat admin publish post).
 */
export async function listFeedPosts({
  tab,
  cursor,
  viewerUserId,
}: FeedListOptions): Promise<FeedListResponse> {
  const posts = await prisma.feedPost.findMany({
    where: {
      status: "ACTIVE",
      // Soft-deleted posts stay in DB for audit/restore but must never
      // surface in the public feed.
      deletedAt: null,
      // Bunny videos in `uploading` / `processing` / `failed` are not
      // playable — exclude them. Legacy UploadThing posts default to
      // `ready` so they continue to surface.
      encodingStatus: "ready",
      // Defensive: skip posts whose video assets are missing. This can
      // happen when an admin hide/reject runs cleanup against an already-
      // active post and then unhides — the row comes back ACTIVE but its
      // videoUrl was wiped by deleteFeedAssets(). Without this guard the
      // feed shows a black card with no playable content.
      OR: [
        // Video posts must have both url + thumbnail.
        { videoUrl: { not: null }, thumbnailUrl: { not: null } },
        // Product-only / promo cards have no video but still have a
        // productId to render against.
        { kind: "PRODUCT_ONLY" },
        { kind: "PROMO", productId: { not: null } },
      ],
      ...(tab ? { tab } : {}),
    },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: FEED_PAGE_SIZE + 1,
    ...(cursor
      ? {
          cursor: { id: cursor },
          skip: 1,
        }
      : {}),
    include: {
      author: { select: { id: true, name: true, role: true } },
      product: {
        select: {
          id: true,
          slug: true,
          name: true,
          price: true,
          discountPrice: true,
          stock: true,
          imageUrl: true,
        },
      },
    },
  });

  // Fetch viewer's like state batch-style (1 query) supaya tidak N+1.
  let viewerLikedIds = new Set<string>();
  if (viewerUserId && posts.length > 0) {
    const likes = await prisma.feedLike.findMany({
      where: {
        userId: viewerUserId,
        postId: { in: posts.map((p) => p.id) },
      },
      select: { postId: true },
    });
    viewerLikedIds = new Set(likes.map((l) => l.postId));
  }

  const hasMore = posts.length > FEED_PAGE_SIZE;
  const sliced = hasMore ? posts.slice(0, FEED_PAGE_SIZE) : posts;

  const items: FeedPostListItem[] = sliced.map((p) => ({
    id: p.id,
    kind: p.kind,
    tab: p.tab,
    status: p.status,
    title: p.title,
    description: p.description,
    videoUrl: p.videoUrl,
    thumbnailUrl: p.thumbnailUrl,
    videoDurationSec: p.videoDurationSec,
    videoWidth: p.videoWidth,
    videoHeight: p.videoHeight,
    product: p.product
      ? {
          id: p.product.id,
          slug: p.product.slug,
          name: p.product.name,
          price: p.product.price,
          discountPrice: p.product.discountPrice,
          stock: p.product.stock,
          imageUrl: p.product.imageUrl,
        }
      : null,
    promo:
      p.kind === "PROMO" && p.promoOriginalPrice != null && p.promoDiscountPrice != null
        ? {
            originalPrice: p.promoOriginalPrice,
            discountPrice: p.promoDiscountPrice,
            startsAt: p.promoStartsAt?.toISOString() ?? null,
            endsAt: p.promoEndsAt?.toISOString() ?? null,
          }
        : null,
    likeCount: p.likeCount,
    commentCount: p.commentCount,
    viewCount: p.viewCount,
    shareCount: p.shareCount,
    author: {
      id: p.author.id,
      name: p.author.name,
      role: (p.authorRole === "ADMIN" ? "ADMIN" : "CUSTOMER") as "ADMIN" | "CUSTOMER",
    },
    publishedAt: p.publishedAt?.toISOString() ?? null,
    createdAt: p.createdAt.toISOString(),
    viewerLiked: viewerLikedIds.has(p.id),
  }));

  return {
    items,
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  };
}

type CommentListOptions = {
  postId: string;
  cursor?: string | null;
  viewerUserId?: string | null;
};

/**
 * Top-level komentar untuk satu post. Untuk MVP tidak include nested
 * replies — UI bisa fetch per-comment kalau user expand. Hidden
 * comments di-skip untuk public reader; admin punya endpoint berbeda.
 */
export async function listFeedComments({
  postId,
  cursor,
  viewerUserId,
}: CommentListOptions): Promise<FeedCommentsResponse> {
  const comments = await prisma.feedComment.findMany({
    where: {
      postId,
      parentCommentId: null,
      isHidden: false,
    },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: COMMENT_PAGE_SIZE + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: {
      author: { select: { id: true, name: true, role: true } },
    },
  });

  let viewerLikedIds = new Set<string>();
  if (viewerUserId && comments.length > 0) {
    const likes = await prisma.feedCommentLike.findMany({
      where: {
        userId: viewerUserId,
        commentId: { in: comments.map((c) => c.id) },
      },
      select: { commentId: true },
    });
    viewerLikedIds = new Set(likes.map((l) => l.commentId));
  }

  const hasMore = comments.length > COMMENT_PAGE_SIZE;
  const sliced = hasMore ? comments.slice(0, COMMENT_PAGE_SIZE) : comments;

  const items: FeedCommentItem[] = sliced.map((c) => ({
    id: c.id,
    postId: c.postId,
    parentCommentId: c.parentCommentId,
    content: c.content,
    isAdminOfficial: c.isAdminOfficial,
    isHidden: c.isHidden,
    likeCount: c.likeCount,
    createdAt: c.createdAt.toISOString(),
    author: {
      id: c.author.id,
      name: c.author.name,
      role: (c.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as "ADMIN" | "CUSTOMER",
    },
    viewerLiked: viewerLikedIds.has(c.id),
  }));

  return {
    items,
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  };
}
