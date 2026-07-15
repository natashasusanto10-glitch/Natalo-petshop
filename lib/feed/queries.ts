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
import { resolveActiveDiscount } from "@/lib/product-pricing";
import { extractMentionHandles } from "./mentions";
import { signBunnyUrl } from "./bunny";
import { feedAccessibilityPayload } from "./accessibility";
import type {
  FeedCommentItem,
  FeedCommentsResponse,
  FeedListResponse,
  FeedPostListItem,
} from "./types";

const FEED_PAGE_SIZE = 10;
const COMMENT_PAGE_SIZE = 20;

/**
 * Resolve diskon AKTIF untuk produk di feed — pakai logika canonical yang
 * sama dengan checkout + halaman produk (resolveActiveDiscount). Mengecek
 * window aktif (flash sale endsAt + Promo Toko endsAt) DAN mengembalikan
 * SUMBER diskon supaya UI bisa label benar:
 *   - FLASH_SALE → badge "Flash Sale X%"
 *   - PROMO_TOKO → badge "Diskon X%"
 *
 * SEBELUMNYA feed kirim raw Product.discountPrice (field flash sale) apa
 * adanya tanpa cek aktif/tidak, dan tidak fetch Promo Toko sama sekali →
 * produk dengan Promo Toko -12% salah tampil "Flash Sale 25%". Helper ini
 * mengirim effectivePrice (harga aktif sebenarnya) + discountSource.
 *
 * `tagPromoPrice` opsional — promoPrice per-tag di video PROMO/Shop the
 * Look (FeedPostProduct.promoPrice). Diperlakukan sebagai Promo Toko;
 * lowest wins.
 */
function resolveFeedProductDiscount(
  product: {
    price: number;
    discountPrice: number | null;
    flashSaleEndsAt: Date | null;
    discountItems?: Array<{
      variantId: string | null;
      discountedPrice: number;
      discount: { endsAt: Date };
    }>;
  },
  now: Date,
  tagPromoPrice?: number | null,
): { discountPrice: number | null; discountSource: "FLASH_SALE" | "PROMO_TOKO" | null } {
  const promoItems = (product.discountItems ?? [])
    .filter((it) => it.variantId === null)
    .map((it) => ({ discountedPrice: it.discountedPrice, endsAt: it.discount.endsAt }));
  let best = resolveActiveDiscount(
    product.price,
    { discountPrice: product.discountPrice, endsAt: product.flashSaleEndsAt },
    promoItems,
    now,
  );
  if (
    tagPromoPrice != null &&
    tagPromoPrice > 0 &&
    tagPromoPrice < product.price &&
    (!best || tagPromoPrice < best.effectivePrice)
  ) {
    best = {
      source: "PROMO_TOKO",
      effectivePrice: tagPromoPrice,
      discountAmount: product.price - tagPromoPrice,
      discountPercent: Math.round(
        ((product.price - tagPromoPrice) / product.price) * 100,
      ),
      endsAt: now,
    };
  }
  if (!best) return { discountPrice: null, discountSource: null };
  return { discountPrice: best.effectivePrice, discountSource: best.source };
}

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

  // Single `now` per request — dipakai untuk filter discountItems aktif
  // (di select) + resolveFeedProductDiscount (di serialization). Konsisten
  // supaya tidak ada drift antara filter query dan resolve.
  const now = new Date();

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
        // PHOTO_CAROUSEL: pass WHERE filter — media check di-handle
        // post-query (Prisma _count workaround). Photo post tidak punya
        // videoUrl, jadi tanpa OR ini akan filtered out di atas.
        { kind: "PHOTO_CAROUSEL" },
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
      author: {
        select: {
          id: true,
          name: true,
          username: true,
          role: true,
          profilePhotoUrl: true,
        },
      },
      product: {
        select: {
          id: true,
          slug: true,
          name: true,
          price: true,
          discountPrice: true,
          // Flash sale window + Promo Toko (discountItems) — supaya
          // resolveActiveDiscount bisa tentukan diskon AKTIF + sumbernya.
          // Tanpa ini feed salah label "Flash Sale" untuk Promo Toko.
          flashSaleEndsAt: true,
          discountItems: {
            where: {
              isItemActive: true,
              discount: {
                isActive: true,
                startsAt: { lte: now },
                endsAt: { gt: now },
              },
            },
            select: {
              variantId: true,
              discountedPrice: true,
              discount: { select: { endsAt: true } },
            },
          },
          stock: true,
          weightGram: true,
          isActive: true,
          imageUrl: true,
          // hasVariants — bedakan quick-add path: kalau false, tap +cart
          // langsung addItemToCart. Kalau true, harus buka variant picker
          // dulu (cart tidak boleh skip variant selection).
          hasVariants: true,
          // Social proof — dipakai di popup preview + bottom sheet
          // (Final Lock Spec). avgRating + reviewCount denormalized di
          // Product table (di-update via review CRUD). soldCount tidak
          // denormalized — di-hitung batched setelah query utama.
          avgRating: true,
          reviewCount: true,
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
              flashSaleEndsAt: true,
              discountItems: {
            where: {
              isItemActive: true,
              discount: {
                isActive: true,
                startsAt: { lte: now },
                endsAt: { gt: now },
              },
            },
            select: {
              variantId: true,
              discountedPrice: true,
              discount: { select: { endsAt: true } },
            },
          },
              stock: true,
              weightGram: true,
              imageUrl: true,
              isActive: true,
              hasVariants: true,
              avgRating: true,
              reviewCount: true,
            },
          },
        },
        orderBy: { position: "asc" },
      },
      // PHOTO_CAROUSEL media — 1-8 image rows. Empty untuk video posts.
      media: {
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
        orderBy: { sortOrder: "asc" },
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

  // Follow state viewer→author, batch 1 query (pola sama dgn viewerLikedIds,
  // no N+1) — dipakai chip "Ikuti/Mengikuti" di samping nama kreator di
  // feed app (IG parity). Anon viewer → semua false.
  let viewerFollowedAuthorIds = new Set<string>();
  if (viewerUserId && posts.length > 0) {
    const follows = await prisma.userFollow.findMany({
      where: {
        followerId: viewerUserId,
        followingId: { in: [...new Set(posts.map((p) => p.authorId))] },
      },
      select: { followingId: true },
    });
    viewerFollowedAuthorIds = new Set(follows.map((f) => f.followingId));
  }

  // Batched soldCount aggregate — kumpulkan semua productId dari main
  // product + taggedProducts, lalu 1 query groupBy ambil _sum quantity
  // sekaligus. Pattern sama dengan /api/products/[slug] (status filter:
  // hanya order yang sudah PAID atau lebih lanjut → exclude PENDING/cart).
  // Defensive catch → empty map kalau aggregate error (data tetap render
  // dengan soldCount = 0, bukan crash seluruh feed).
  const soldCountMap = new Map<string, number>();
  if (posts.length > 0) {
    const productIds = new Set<string>();
    for (const p of posts) {
      if (p.product?.id) productIds.add(p.product.id);
      for (const tp of p.taggedProducts) {
        if (tp.product?.id) productIds.add(tp.product.id);
      }
    }
    if (productIds.size > 0) {
      try {
        const soldRows = await prisma.orderItem.groupBy({
          by: ["productId"],
          where: {
            productId: { in: [...productIds] },
            order: {
              status: {
                in: [
                  "PAID",
                  "PROCESSING",
                  "READY_FOR_PICKUP",
                  "SHIPPED",
                  "DELIVERED",
                ],
              },
            },
          },
          _sum: { quantity: true },
        });
        for (const row of soldRows) {
          soldCountMap.set(row.productId, row._sum.quantity ?? 0);
        }
      } catch {
        // Aggregate failure tidak boleh nge-break feed list. Map kosong
        // → soldCount default 0 di serialization.
      }
    }
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
    // Sign URL dengan Bunny CDN token kalau BUNNY_TOKEN_SECURITY_KEY di-set
    // (defense untuk hotlink protection). Tanpa env, return as-is.
    videoUrl: signBunnyUrl(p.videoUrl) ?? null,
    thumbnailUrl: signBunnyUrl(p.thumbnailUrl) ?? null,
    thumbnailBlurhash: p.thumbnailBlurhash,
    videoDurationSec: p.videoDurationSec,
    videoWidth: p.videoWidth,
    videoHeight: p.videoHeight,
    ...feedAccessibilityPayload(p, signBunnyUrl),
    product: p.product
      ? (() => {
          // discountPrice = harga AKTIF (effectivePrice) hasil
          // resolveActiveDiscount, BUKAN raw Product.discountPrice. Plus
          // discountSource supaya app label "Flash Sale" vs "Diskon" benar.
          const d = resolveFeedProductDiscount(p.product!, now);
          return {
            id: p.product!.id,
            slug: p.product!.slug,
            name: p.product!.name,
            price: p.product!.price,
            discountPrice: d.discountPrice,
            discountSource: d.discountSource,
            stock: p.product!.stock,
            weightGram: p.product!.weightGram,
            isAvailable: p.product!.isActive,
            imageUrl: p.product!.imageUrl,
            hasVariants: p.product!.hasVariants,
            avgRating: p.product!.avgRating ?? 0,
            reviewCount: p.product!.reviewCount ?? 0,
            soldCount: soldCountMap.get(p.product!.id) ?? 0,
          };
        })()
      : null,
    // Shop the Look: keep inactive tagged products visible for context, but
    // mark them unavailable so UI can disable commerce safely.
    taggedProducts: p.taggedProducts
      .filter((tp) => tp.product)
      .map((tp) => {
        // Per-tag promoPrice ikut dipertimbangkan (lowest wins).
        const d = resolveFeedProductDiscount(tp.product!, now, tp.promoPrice);
        return {
          id: tp.product!.id,
          slug: tp.product!.slug,
          name: tp.product!.name,
          price: tp.product!.price,
          discountPrice: d.discountPrice,
          discountSource: d.discountSource,
          stock: tp.product!.stock,
          weightGram: tp.product!.weightGram,
          isAvailable: tp.product!.isActive,
          imageUrl: tp.product!.imageUrl,
          position: tp.position,
          promoPrice: tp.promoPrice ?? null,
          hasVariants: tp.product!.hasVariants,
          avgRating: tp.product!.avgRating ?? 0,
          reviewCount: tp.product!.reviewCount ?? 0,
          soldCount: soldCountMap.get(tp.product!.id) ?? 0,
        };
      }),
    promo:
      p.kind === "PROMO" &&
      p.promoOriginalPrice != null &&
      p.promoDiscountPrice != null
        ? {
            originalPrice: p.promoOriginalPrice,
            discountPrice: p.promoDiscountPrice,
            startsAt: p.promoStartsAt?.toISOString() ?? null,
            endsAt: p.promoEndsAt?.toISOString() ?? null,
          }
        : null,
    // PHOTO_CAROUSEL media — 1-8 image entries ordered by sortOrder.
    // Video posts return empty array (kind != PHOTO_CAROUSEL).
    media: p.media.map((m) => ({
      id: m.id,
      mediaType: m.mediaType,
      url: m.url,
      thumbnailUrl: m.thumbnailUrl,
      width: m.width,
      height: m.height,
      sortOrder: m.sortOrder,
      altText: m.altText,
    })),
    likeCount: p.likeCount,
    commentCount: p.commentCount,
    viewCount: p.viewCount,
    shareCount: p.shareCount,
    author: {
      id: p.author.id,
      name: p.author.name,
      username: p.author.username ?? null,
      role: (p.authorRole === "ADMIN" ? "ADMIN" : "CUSTOMER") as
        | "ADMIN"
        | "CUSTOMER",
      profilePhotoUrl: p.author.profilePhotoUrl ?? null,
      // Chip "Ikuti/Mengikuti" di feed app — snapshot saat fetch; toggle
      // selanjutnya di-track client-side (followOverrides).
      isFollowing: viewerFollowedAuthorIds.has(p.author.id),
    },
    recentLikers: p.likes.map((like) => ({
      id: like.user.id,
      name: like.user.name,
      username: like.user.username ?? null,
      role: (like.user.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as
        | "ADMIN"
        | "CUSTOMER",
      profilePhotoUrl: like.user.profilePhotoUrl ?? null,
      avatarUrl: like.user.profilePhotoUrl ?? null,
    })),
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
    author: {
      id: string;
      name: string;
      username: string | null;
      role: string;
      profilePhotoUrl: string | null;
    };
    replies?: Array<{
      id: string;
      postId: string;
      parentCommentId: string | null;
      content: string;
      isAdminOfficial: boolean;
      isHidden: boolean;
      likeCount: number;
      createdAt: Date;
      author: {
        id: string;
        name: string;
        username: string | null;
        role: string;
        profilePhotoUrl: string | null;
      };
    }>;
  },
  viewerLikedIds: Set<string>,
  officialHandles: Set<string> = new Set()
): FeedCommentItem {
  // Mention handle di content yang merupakan akun official → kirim ke
  // client untuk brand-override render. Skip kalau tidak ada official
  // handle yang ke-mention (mayoritas komentar).
  const officialMentions =
    officialHandles.size > 0
      ? [...extractMentionHandles(c.content)].filter((h) =>
          officialHandles.has(h),
        )
      : [];
  return {
    id: c.id,
    postId: c.postId,
    parentCommentId: c.parentCommentId,
    content: c.content,
    isAdminOfficial: c.isAdminOfficial,
    officialMentions,
    isHidden: c.isHidden,
    likeCount: c.likeCount,
    createdAt: c.createdAt.toISOString(),
    author: {
      id: c.author.id,
      name: c.author.name,
      username: c.author.username ?? null,
      role: (c.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as
        | "ADMIN"
        | "CUSTOMER",
      profilePhotoUrl: c.author.profilePhotoUrl ?? null,
    },
    viewerLiked: viewerLikedIds.has(c.id),
    replies:
      c.replies?.map((reply) =>
        mapFeedComment(reply, viewerLikedIds, officialHandles),
      ) ?? [],
    replyCount: c.replies?.length ?? 0,
  };
}

/**
 * Batch-resolve handle @mention di sekumpulan komentar (+ replies) ke set
 * username (lowercase) yang merupakan akun ADMIN/official. Dipakai
 * mapFeedComment untuk kirim officialMentions → client brand-override.
 *
 * 1 query saja (findMany username IN [...]) — efisien untuk 1 page komentar.
 */
async function resolveOfficialMentionHandles(
  contents: string[],
): Promise<Set<string>> {
  const handles = new Set<string>();
  for (const content of contents) {
    for (const h of extractMentionHandles(content)) handles.add(h);
  }
  if (handles.size === 0) return new Set();
  const admins = await prisma.user.findMany({
    where: { username: { in: [...handles] }, role: "ADMIN" },
    select: { username: true },
  });
  return new Set(
    admins
      .map((a) => a.username?.toLowerCase())
      .filter((u): u is string => Boolean(u)),
  );
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
      // Hide komentar yang user hapus sendiri. isHidden=admin moderation;
      // deletedAt=user self-delete. Semantik beda, dua-duanya filter out.
      deletedAt: null,
    },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: COMMENT_PAGE_SIZE + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: {
      author: {
        select: {
          id: true,
          name: true,
          username: true,
          role: true,
          profilePhotoUrl: true,
        },
      },
      replies: {
        where: { isHidden: false, deletedAt: null },
        orderBy: [{ createdAt: "asc" }, { id: "asc" }],
        include: {
          author: {
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

  // Resolve handle official yang ke-mention di seluruh page (parent +
  // reply) → 1 query. Dipakai untuk brand-override render di client.
  const officialHandles = await resolveOfficialMentionHandles(
    sliced.flatMap((c) => [
      c.content,
      ...c.replies.map((reply) => reply.content),
    ]),
  );

  const items: FeedCommentItem[] = sliced.map((c) =>
    mapFeedComment(c, viewerLikedIds, officialHandles)
  );

  return {
    items,
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  };
}
