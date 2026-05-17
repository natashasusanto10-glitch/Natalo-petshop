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
  /** Filter to only posts that tag this product (Shop the Look + legacy
   *  productId). Used when entering /feed from a product page. */
  productSlug?: string | null;
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
  productSlug,
}: FeedListOptions): Promise<FeedListResponse> {
  // Resolve product slug → id sekali, supaya WHERE clause bisa pakai
  // productId match (lebih efisien dari nested slug lookup di setiap row).
  let productIdFilter: string | null = null;
  if (productSlug) {
    const product = await prisma.product.findUnique({
      where: { slug: productSlug },
      select: { id: true },
    });
    if (!product) {
      // Slug tidak ada — return empty list daripada throw.
      return { items: [], nextCursor: null };
    }
    productIdFilter = product.id;
  }

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
      // Defensive: skip posts whose video assets are missing.
      OR: [
        { videoUrl: { not: null }, thumbnailUrl: { not: null } },
        { kind: "PRODUCT_ONLY" },
        { kind: "PROMO", productId: { not: null } },
      ],
      ...(tab ? { tab } : {}),
      // Shop the Look filter: match BOTH legacy productId AND multi-tag.
      ...(productIdFilter
        ? {
            AND: [
              {
                OR: [
                  { productId: productIdFilter },
                  {
                    taggedProducts: { some: { productId: productIdFilter } },
                  },
                ],
              },
            ],
          }
        : {}),
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
          weightGram: true,
          isActive: true,
          imageUrl: true,
        },
      },
      // Shop the Look — multi-tag carousel dengan per-product promoPrice.
      taggedProducts: {
        select: {
          position: true,
          promoPrice: true,
          product: {
            select: {
              id: true,
              slug: true,
              name: true,
              price: true,
              discountPrice: true,
              stock: true,
              weightGram: true,
              imageUrl: true,
              isActive: true,
            },
          },
        },
        orderBy: { position: "asc" },
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
    thumbnailBlurhash: p.thumbnailBlurhash,
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
          weightGram: p.product.weightGram,
          isAvailable: p.product.isActive,
          imageUrl: p.product.imageUrl,
        }
      : null,
    // Shop the Look: keep inactive tagged products visible for context, but
    // mark them unavailable so UI can disable commerce safely.
    taggedProducts: p.taggedProducts
      .filter((tp) => tp.product)
      .map((tp) => ({
        id: tp.product!.id,
        slug: tp.product!.slug,
        name: tp.product!.name,
        price: tp.product!.price,
        discountPrice: tp.product!.discountPrice,
        stock: tp.product!.stock,
        weightGram: tp.product!.weightGram,
        isAvailable: tp.product!.isActive,
        imageUrl: tp.product!.imageUrl,
        position: tp.position,
        promoPrice: tp.promoPrice ?? null,
      })),
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

function mapFeedComment(
  c: {
    id: string;
    postId: string;
    parentCommentId: string | null;
    content: string;
    isAdminOfficial: boolean;
    isHidden: boolean;
    likeCount: number;
    createdAt: Date;
    author: { id: string; name: string; role: string };
    replies?: Array<{
      id: string;
      postId: string;
      parentCommentId: string | null;
      content: string;
      isAdminOfficial: boolean;
      isHidden: boolean;
      likeCount: number;
      createdAt: Date;
      author: { id: string; name: string; role: string };
    }>;
  },
  viewerLikedIds: Set<string>,
): FeedCommentItem {
  return {
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
    replies: c.replies?.map((reply) => mapFeedComment(reply, viewerLikedIds)) ?? [],
    replyCount: c.replies?.length ?? 0,
  };
}

/**
 * Top-level komentar untuk satu post, plus 1-level replies. Hidden
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
      replies: {
        where: { isHidden: false },
        orderBy: [{ createdAt: "asc" }, { id: "asc" }],
        include: {
          author: { select: { id: true, name: true, role: true } },
        },
      },
    },
  });

  let viewerLikedIds = new Set<string>();
  if (viewerUserId && comments.length > 0) {
    const commentIds = comments.flatMap((c) => [
      c.id,
      ...c.replies.map((reply) => reply.id),
    ]);
    const likes = await prisma.feedCommentLike.findMany({
      where: {
        userId: viewerUserId,
        commentId: { in: commentIds },
      },
      select: { commentId: true },
    });
    viewerLikedIds = new Set(likes.map((l) => l.commentId));
  }

  const hasMore = comments.length > COMMENT_PAGE_SIZE;
  const sliced = hasMore ? comments.slice(0, COMMENT_PAGE_SIZE) : comments;

  const items: FeedCommentItem[] = sliced.map((c) => mapFeedComment(c, viewerLikedIds));

  return {
    items,
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  };
}
