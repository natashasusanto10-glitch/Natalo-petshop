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
import type { FeedPostTab, Prisma } from "@prisma/client";
import { resolveActiveDiscount } from "@/lib/product-pricing";
import {
  attachPublicProductVoucherPreviews,
  type ProductVoucherPreview,
} from "@/lib/product-vouchers";
import { extractMentionHandles } from "./mentions";
import { signBunnyUrl } from "./bunny";
import { buildFeedVideoPlaybackUrls } from "./video-playback-urls";
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";
import {
  resolveViewerTagHidden,
  TAGGED_USERS_SELECT,
  serializeTaggedUsers,
} from "@/lib/feed/tagged-users";
import {
  stripEphemeralUrlQuery,
} from "@/lib/share/share-version";
import { buildFeedShareVersion } from "@/lib/share/feed-share-data";
import { feedAccessibilityPayload } from "./accessibility";
import { visibleFeedCommentRootWhere } from "./comment-sync";
import type {
  FeedCommentItem,
  FeedCommentsResponse,
  FeedListResponse,
  FeedPostListItem,
} from "./types";

const FEED_PAGE_SIZE = 10;
const COMMENT_PAGE_SIZE = 20;

/**
 * Subset of the Prisma client the feed READ path touches, injectable so the
 * pagination/batch contract can be unit-tested without a database (same
 * `db = prisma` seam already used by listFeedComments/getFeedCommentDetail
 * below). Product voucher + soldCount aggregation still use the module client
 * directly — they only run when a post carries products, and the batch
 * (saved-post) path passes product-less ids, so they are never exercised
 * through an injected client.
 */
export type FeedReadDb = Pick<
  typeof prisma,
  "feedPost" | "feedLike" | "feedSave" | "userFollow"
>;

export const PUBLIC_FEED_POST_WHERE = {
  status: "ACTIVE",
  deletedAt: null,
  encodingStatus: "ready",
  OR: [
    { videoUrl: { not: null }, thumbnailUrl: { not: null } },
    { kind: "PRODUCT_ONLY" },
    { kind: "PROMO", productId: { not: null } },
    { kind: "PHOTO_CAROUSEL" },
  ],
} satisfies Prisma.FeedPostWhereInput;

/** Resolve saved state for a whole page in one query. */
export async function getViewerSavedPostIds(
  viewerUserId: string | null | undefined,
  postIds: readonly string[],
  db: Pick<typeof prisma, "feedSave"> = prisma
): Promise<Set<string>> {
  if (!viewerUserId || postIds.length === 0) return new Set<string>();

  const saves = await db.feedSave.findMany({
    where: {
      userId: viewerUserId,
      postId: { in: [...new Set(postIds)] },
    },
    select: { postId: true },
  });
  return new Set(saves.map((save) => save.postId));
}

export function orderFeedItemsByPostIds(
  postIds: readonly string[],
  items: readonly FeedPostListItem[]
): FeedPostListItem[] {
  const byId = new Map(items.map((item) => [item.id, item]));
  return postIds.flatMap((postId) => {
    const item = byId.get(postId);
    return item ? [item] : [];
  });
}

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
export function resolveFeedProductDiscount(
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
  tagPromoPrice?: number | null
): {
  discountPrice: number | null;
  discountSource: "FLASH_SALE" | "PROMO_TOKO" | null;
} {
  const promoItems = (product.discountItems ?? [])
    .filter((it) => it.variantId === null)
    .map((it) => ({
      discountedPrice: it.discountedPrice,
      endsAt: it.discount.endsAt,
    }));
  let best = resolveActiveDiscount(
    product.price,
    { discountPrice: product.discountPrice, endsAt: product.flashSaleEndsAt },
    promoItems,
    now
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
        ((product.price - tagPromoPrice) / product.price) * 100
      ),
      endsAt: now,
    };
  }
  if (!best) return { discountPrice: null, discountSource: null };
  return { discountPrice: best.effectivePrice, discountSource: best.source };
}

/**
 * Prisma `include` shape untuk listFeedPosts — diekstrak supaya handler lain
 * (mis. GET /api/feed/hashtags/[name]) bisa fetch post dengan shape query
 * IDENTIK lalu reuse resolveFeedBatchContext/serializeFeedPostRow di bawah
 * untuk hasilkan JSON yang sama persis dengan feed utama.
 *
 * Fungsi (bukan `const` object literal) — BUKAN pilihan sembarang: dua
 * cabang `discountItems.where` di bawah butuh `now` per-request supaya
 * filter "discount aktif saat ini" konsisten dengan `now` yang sama dipakai
 * resolveFeedProductDiscount saat serialize (lihat komentar di
 * listFeedPosts). Kalau ini jadi top-level const, `now` akan beku di waktu
 * module pertama di-load (bukan di-refresh tiap request) — discount yang
 * baru mulai/berakhir setelah itu akan salah ter-filter selamanya. Jadi
 * dipertahankan sebagai factory function, dipanggil dgn `now` yang sama tiap
 * request (persis seperti sebelum ekstraksi).
 */
export function buildFeedPostInclude(now: Date) {
  return {
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
        // brandId/categoryId — WAJIB untuk hitung voucher scoped (Brand
        // Eksklusif dkk) via voucherMatchesProduct. Bukan dikirim ke
        // client mentah; cuma dipakai server-side match lalu diringkas
        // jadi shippingVoucher/discountVoucher.badgeLabel+isBrandExclusive.
        brandId: true,
        categoryId: true,
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
            brandId: true,
            categoryId: true,
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
    taggedUsers: TAGGED_USERS_SELECT,
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
  } satisfies Prisma.FeedPostInclude;
}

/** Row shape hasil `prisma.feedPost.findMany({ include: buildFeedPostInclude(now) })`. */
export type FeedPostRow = Prisma.FeedPostGetPayload<{
  include: ReturnType<typeof buildFeedPostInclude>;
}>;

type FeedListOptions = {
  tab?: FeedPostTab | null;
  cursor?: string | null;
  viewerUserId?: string | null;
  /** Filter to only posts that tag this product (Shop the Look + legacy
   *  productId). Used when entering /feed from a product page. */
  productSlug?: string | null;
  /** Internal batch filter used by the saved-post listing. */
  postIds?: readonly string[];
  /** Injectable Prisma seam (defaults to the module client) — see FeedReadDb. */
  db?: FeedReadDb;
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
  postIds,
  db = prisma,
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

  // Batch fetch by explicit ids (saved-post listing) — the caller already
  // paginated, so we must return EVERY requested id. Sizing the internal
  // window to postIds.length stops the LIMIT/slice from silently dropping ids
  // past FEED_PAGE_SIZE (the saved-feed vanishing bug). The primary
  // (non-postIds) feed path keeps its FEED_PAGE_SIZE cursor window unchanged.
  const pageSize = postIds ? postIds.length : FEED_PAGE_SIZE;

  const posts = await db.feedPost.findMany({
    where: {
      ...PUBLIC_FEED_POST_WHERE,
      ...(postIds ? { id: { in: [...postIds] } } : {}),
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
    take: pageSize + 1,
    ...(cursor
      ? {
          cursor: { id: cursor },
          skip: 1,
        }
      : {}),
    include: buildFeedPostInclude(now),
  });

  const ctx = await resolveFeedBatchContext(posts, viewerUserId ?? null, now, db);

  const hasMore = posts.length > pageSize;
  const sliced = hasMore ? posts.slice(0, pageSize) : posts;

  const items: FeedPostListItem[] = sliced.map((p) => serializeFeedPostRow(p, ctx));

  return {
    items,
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
  };
}

export type FeedBatchContext = {
  now: Date;
  viewerLikedIds: Set<string>;
  viewerSavedIds: Set<string>;
  viewerFollowedAuthorIds: Set<string>;
  soldCountMap: Map<string, number>;
  voucherPreviewMap: Map<
    string,
    { product: ProductVoucherPreview | null; shipping: ProductVoucherPreview | null }
  >;
  // Diteruskan apa adanya dari pemanggil listFeedPosts (bukan hasil batch
  // query) — dipakai serializeFeedPostRow (resolveViewerTagHidden). Disimpan
  // di ctx (bukan parameter terpisah) supaya serializeFeedPostRow cukup
  // 1 parameter ctx, konsisten dengan field lain yang page-scoped.
  viewerUserId: string | null;
};

/**
 * Hitung semua nilai batch (1 query per jenis, no N+1) yang dibutuhkan untuk
 * serialize satu page hasil listFeedPosts. Diekstrak dari body listFeedPosts
 * (pure mechanical move) — logic SAMA PERSIS, cuma diparameterkan ke
 * `posts`/`viewerUserId`/`now` alih-alih closure ke local listFeedPosts.
 * `now` WAJIB parameter (bukan `new Date()` baru di sini) — harus persis
 * instance yang sama dipakai membangun query include (buildFeedPostInclude),
 * supaya tidak ada drift antara filter query dan resolveFeedProductDiscount
 * saat serialize (lihat komentar di listFeedPosts).
 */
export async function resolveFeedBatchContext(
  posts: readonly FeedPostRow[],
  viewerUserId: string | null,
  now: Date,
  db: FeedReadDb = prisma,
): Promise<FeedBatchContext> {
  // Fetch viewer's like state batch-style (1 query) supaya tidak N+1.
  let viewerLikedIds = new Set<string>();
  if (viewerUserId && posts.length > 0) {
    const likes = await db.feedLike.findMany({
      where: {
        userId: viewerUserId,
        postId: { in: posts.map((p) => p.id) },
      },
      select: { postId: true },
    });
    viewerLikedIds = new Set(likes.map((l) => l.postId));
  }

  const viewerSavedIds = await getViewerSavedPostIds(
    viewerUserId,
    posts.map((post) => post.id),
    db
  );

  // Follow state viewer→author, batch 1 query (pola sama dgn viewerLikedIds,
  // no N+1) — dipakai chip "Ikuti/Mengikuti" di samping nama kreator di
  // feed app (IG parity). Anon viewer → semua false.
  let viewerFollowedAuthorIds = new Set<string>();
  if (viewerUserId && posts.length > 0) {
    const follows = await db.userFollow.findMany({
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
  // Voucher preview (Gratis Ongkir / Hemat) per productId — batched sekali
  // untuk semua produk (main + tagged) di page ini, sama pola dgn
  // soldCountMap. Map value null = tidak ada voucher publik yang cocok.
  const voucherPreviewMap = new Map<
    string,
    { product: ProductVoucherPreview | null; shipping: ProductVoucherPreview | null }
  >();
  if (posts.length > 0) {
    const productIds = new Set<string>();
    const voucherInputById = new Map<
      string,
      { id: string; price: number; categoryId: string | null; brandId: string | null }
    >();
    for (const p of posts) {
      if (p.product?.id) {
        productIds.add(p.product.id);
        voucherInputById.set(p.product.id, {
          id: p.product.id,
          price: p.product.price,
          categoryId: p.product.categoryId,
          brandId: p.product.brandId,
        });
      }
      for (const tp of p.taggedProducts) {
        if (tp.product?.id) {
          productIds.add(tp.product.id);
          voucherInputById.set(tp.product.id, {
            id: tp.product.id,
            price: tp.product.price,
            categoryId: tp.product.categoryId,
            brandId: tp.product.brandId,
          });
        }
      }
    }
    if (voucherInputById.size > 0) {
      try {
        const withPreviews = await attachPublicProductVoucherPreviews(
          [...voucherInputById.values()],
          { userId: viewerUserId }
        );
        for (const item of withPreviews) {
          voucherPreviewMap.set(item.id, {
            product: item.voucherPreview,
            shipping: item.shippingVoucherPreview,
          });
        }
      } catch {
        // Voucher preview kegagalan tidak boleh nge-break feed list —
        // map kosong → shippingVoucher/discountVoucher null di serialization.
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

  return {
    now,
    viewerLikedIds,
    viewerSavedIds,
    viewerFollowedAuthorIds,
    soldCountMap,
    voucherPreviewMap,
    viewerUserId,
  };
}

/**
 * Serialize satu row FeedPost (hasil query dgn buildFeedPostInclude) jadi
 * shape JSON publik FeedPostListItem. Diekstrak dari closure `.map()` di
 * listFeedPosts (pure mechanical move) — logic SAMA PERSIS, referensi ke
 * closure var lama (now/viewerLikedIds/viewerSavedIds/
 * viewerFollowedAuthorIds/soldCountMap/voucherPreviewMap/viewerUserId)
 * diganti jadi ctx.<field>. Reusable oleh handler lain yang butuh JSON post
 * identik dengan feed utama (mis. GET /api/feed/hashtags/[name]).
 *
 * Sengaja TANPA anotasi return type eksplisit `: FeedPostListItem` — body
 * ini mengirim 2 field (`taggedUsers`, `viewerTagHidden`) yang belum
 * dideklarasikan di tipe FeedPostListItem (lib/feed/types.ts), gap
 * pre-existing dari sebelum ekstraksi ini (di luar scope task ini, lihat
 * lib/feed/types.ts). Closure `.map()` yang lama tidak pernah excess-property
 * checked terhadap FeedPostListItem (union inference lewat generic `.map<U>`,
 * lalu assignability biasa ke `FeedPostListItem[]` yang membolehkan field
 * ekstra) — anotasi return type di sini akan membuat literal ini "fresh"
 * dan KETAT di-cek, memunculkan error TS baru utk 2 field itu. Membiarkan
 * TS infer return type mereplikasi persis perilaku type-check yang lama.
 */
export function serializeFeedPostRow(
  p: FeedPostRow,
  ctx: FeedBatchContext,
) {
  const playbackUrls = buildFeedVideoPlaybackUrls({
    videoUrl: p.videoUrl,
    videoGuid: p.videoGuid,
  });
  const authorDisplayName = brandDisplayName(p.author.role, p.author.name);
  const authorPhoto = brandPhotoUrl(
    p.author.role,
    p.author.profilePhotoUrl
  );
  const isOfficial = p.authorRole === "ADMIN";
  return {
    id: p.id,
    shareVersion: buildFeedShareVersion(p),
    kind: p.kind,
    tab: p.tab,
    status: p.status,
    title: p.title,
    description: p.description,
    // Sign URL dengan Bunny CDN token kalau BUNNY_TOKEN_SECURITY_KEY di-set
    // (defense untuk hotlink protection). Tanpa env, return as-is.
    videoUrl: playbackUrls.videoUrl,
    videoDataSaverUrl: playbackUrls.videoDataSaverUrl,
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
          const d = resolveFeedProductDiscount(p.product!, ctx.now);
          const voucher = ctx.voucherPreviewMap.get(p.product!.id);
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
            soldCount: ctx.soldCountMap.get(p.product!.id) ?? 0,
            shippingVoucher: voucher?.shipping
              ? {
                  badgeLabel: voucher.shipping.badgeLabel,
                  isBrandExclusive: voucher.shipping.isBrandExclusive,
                }
              : null,
            discountVoucher: voucher?.product
              ? {
                  badgeLabel: voucher.product.badgeLabel,
                  isBrandExclusive: voucher.product.isBrandExclusive,
                }
              : null,
          };
        })()
      : null,
    // Shop the Look: keep inactive tagged products visible for context, but
    // mark them unavailable so UI can disable commerce safely.
    taggedProducts: p.taggedProducts
      .filter((tp) => tp.product)
      .map((tp) => {
        // Per-tag promoPrice ikut dipertimbangkan (lowest wins).
        const d = resolveFeedProductDiscount(tp.product!, ctx.now, tp.promoPrice);
        const voucher = ctx.voucherPreviewMap.get(tp.product!.id);
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
          soldCount: ctx.soldCountMap.get(tp.product!.id) ?? 0,
          shippingVoucher: voucher?.shipping
            ? {
                badgeLabel: voucher.shipping.badgeLabel,
                isBrandExclusive: voucher.shipping.isBrandExclusive,
              }
            : null,
          discountVoucher: voucher?.product
            ? {
                badgeLabel: voucher.product.badgeLabel,
                isBrandExclusive: voucher.product.isBrandExclusive,
              }
            : null,
        };
      }),
    taggedUsers: serializeTaggedUsers(
      p.taggedUsers,
      new Map(p.media.map((m, index) => [m.id, index])),
    ),
    // Tag People (final review Spec B fix) — "apakah tag milik VIEWER
    // ini disembunyikan", null kalau viewer tidak ditandai di post ini.
    // Dipakai seed sheet Opsi Tag supaya "un-hide" tetap reachable
    // setelah app restart (server jadi sumber kebenaran, bukan
    // session-local state).
    viewerTagHidden: resolveViewerTagHidden(p.taggedUsers, ctx.viewerUserId ?? null),
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
    media: p.media.map((m) => {
      const mediaPlaybackUrls = buildFeedVideoPlaybackUrls({
        videoUrl: m.url,
      });
      return {
        id: m.id,
        mediaType: m.mediaType,
        url: mediaPlaybackUrls.videoUrl ?? m.url,
        ...(m.mediaType === "video"
          ? { videoDataSaverUrl: mediaPlaybackUrls.videoDataSaverUrl }
          : {}),
        thumbnailUrl: m.thumbnailUrl,
        width: m.width,
        height: m.height,
        sortOrder: m.sortOrder,
        altText: m.altText,
      };
    }),
    likeCount: p.likeCount,
    commentCount: p.commentCount,
    viewCount: p.viewCount,
    shareCount: p.shareCount,
    author: {
      id: p.author.id,
      // Akun official (admin) → brand "Natalo Petshop" + foto null (klien
      // render logo). Nama asli/foto pemilik tidak boleh bocor.
      name: authorDisplayName,
      username: p.author.username ?? null,
      role: (p.authorRole === "ADMIN" ? "ADMIN" : "CUSTOMER") as
        | "ADMIN"
        | "CUSTOMER",
      profilePhotoUrl: authorPhoto,
      // Chip "Ikuti/Mengikuti" di feed app — snapshot saat fetch; toggle
      // selanjutnya di-track client-side (followOverrides).
      isFollowing: ctx.viewerFollowedAuthorIds.has(p.author.id),
    },
    recentLikers: p.likes.map((like) => ({
      id: like.user.id,
      name: brandDisplayName(like.user.role, like.user.name),
      username: like.user.username ?? null,
      role: (like.user.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as
        | "ADMIN"
        | "CUSTOMER",
      profilePhotoUrl: brandPhotoUrl(
        like.user.role,
        like.user.profilePhotoUrl
      ),
      avatarUrl: brandPhotoUrl(like.user.role, like.user.profilePhotoUrl),
    })),
    publishedAt: p.publishedAt?.toISOString() ?? null,
    createdAt: p.createdAt.toISOString(),
    viewerLiked: ctx.viewerLikedIds.has(p.id),
    viewerSaved: ctx.viewerSavedIds.has(p.id),
  };
}

export async function listSavedFeedPosts({
  userId,
  cursor,
  limit = FEED_PAGE_SIZE,
  db = prisma,
}: {
  userId: string;
  cursor?: string | null;
  limit?: number;
  db?: FeedReadDb;
}): Promise<FeedListResponse> {
  const saves = await db.feedSave.findMany({
    where: {
      userId,
      post: { is: PUBLIC_FEED_POST_WHERE },
    },
    orderBy: [{ createdAt: "desc" }, { postId: "desc" }],
    take: limit + 1,
    ...(cursor
      ? {
          cursor: { userId_postId: { userId, postId: cursor } },
          skip: 1,
        }
      : {}),
    select: { postId: true },
  });

  const hasMore = saves.length > limit;
  const page = hasMore ? saves.slice(0, limit) : saves;
  if (page.length === 0) return { items: [], nextCursor: null };

  const postIds = page.map((save) => save.postId);
  const serialized = await listFeedPosts({
    viewerUserId: userId,
    postIds,
    db,
  });

  return {
    items: orderFeedItemsByPostIds(postIds, serialized.items),
    nextCursor: hasMore ? page[page.length - 1].postId : null,
  };
}

type CommentListOptions = {
  postId: string;
  cursor?: string | null;
  viewerUserId?: string | null;
  additionalRootIds?: readonly string[];
  db?: Pick<
    Prisma.TransactionClient,
    "feedComment" | "feedCommentLike" | "user"
  >;
};

const FEED_COMMENT_THREAD_INCLUDE = {
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
} satisfies Prisma.FeedCommentInclude;

function mapFeedComment(
  c: {
    id: string;
    postId: string;
    parentCommentId: string | null;
    content: string;
    deletedAt: Date | null;
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
      deletedAt: Date | null;
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
  const isDeleted = c.deletedAt !== null;
  // Mention handle di content yang merupakan akun official → kirim ke
  // client untuk brand-override render. Skip kalau tidak ada official
  // handle yang ke-mention (mayoritas komentar).
  const officialMentions =
    !isDeleted && officialHandles.size > 0
      ? [...extractMentionHandles(c.content)].filter((h) =>
          officialHandles.has(h)
        )
      : [];
  return {
    id: c.id,
    postId: c.postId,
    parentCommentId: c.parentCommentId,
    content: isDeleted ? "Komentar dihapus" : c.content,
    isDeleted,
    isAdminOfficial: c.isAdminOfficial,
    officialMentions,
    isHidden: c.isHidden,
    likeCount: isDeleted ? 0 : c.likeCount,
    createdAt: c.createdAt.toISOString(),
    author: {
      id: c.author.id,
      // Akun official (admin) → brand name + foto null (klien render logo).
      name: brandDisplayName(c.author.role, c.author.name),
      username: c.author.username ?? null,
      role: (c.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as
        | "ADMIN"
        | "CUSTOMER",
      profilePhotoUrl: brandPhotoUrl(c.author.role, c.author.profilePhotoUrl),
    },
    viewerLiked: !isDeleted && viewerLikedIds.has(c.id),
    replies:
      c.replies?.map((reply) =>
        mapFeedComment(reply, viewerLikedIds, officialHandles)
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
  db: Pick<Prisma.TransactionClient, "user"> = prisma
): Promise<Set<string>> {
  const handles = new Set<string>();
  for (const content of contents) {
    for (const h of extractMentionHandles(content)) handles.add(h);
  }
  if (handles.size === 0) return new Set();
  const admins = await db.user.findMany({
    where: { username: { in: [...handles] }, role: "ADMIN" },
    select: { username: true },
  });
  return new Set(
    admins
      .map((a) => a.username?.toLowerCase())
      .filter((u): u is string => Boolean(u))
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
  additionalRootIds = [],
  db = prisma,
}: CommentListOptions): Promise<FeedCommentsResponse> {
  const comments = await db.feedComment.findMany({
    where: visibleFeedCommentRootWhere(postId),
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: COMMENT_PAGE_SIZE + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: FEED_COMMENT_THREAD_INCLUDE,
  });

  const hasMore = comments.length > COMMENT_PAGE_SIZE;
  const page = hasMore ? comments.slice(0, COMMENT_PAGE_SIZE) : comments;
  const pageIds = new Set(page.map((comment) => comment.id));
  const extraRootIds = [...new Set(additionalRootIds)].filter(
    (commentId) => !pageIds.has(commentId)
  );
  const extraComments =
    extraRootIds.length === 0
      ? []
      : await db.feedComment.findMany({
          where: {
            AND: [
              visibleFeedCommentRootWhere(postId),
              {
                id: { in: extraRootIds },
              },
            ],
          },
          include: FEED_COMMENT_THREAD_INCLUDE,
        });
  const extraById = new Map(
    extraComments.map((comment) => [comment.id, comment])
  );
  const combined = [
    ...page,
    ...extraRootIds.flatMap((commentId) => {
      const comment = extraById.get(commentId);
      return comment ? [comment] : [];
    }),
  ];

  let viewerLikedIds = new Set<string>();
  if (viewerUserId && combined.length > 0) {
    const commentIds = combined.flatMap((c) => [
      c.id,
      ...c.replies.map((reply) => reply.id),
    ]);
    const likes = await db.feedCommentLike.findMany({
      where: {
        userId: viewerUserId,
        commentId: { in: commentIds },
      },
      select: { commentId: true },
    });
    viewerLikedIds = new Set(likes.map((l) => l.commentId));
  }

  // Resolve handle official yang ke-mention di seluruh page (parent +
  // reply) → 1 query. Dipakai untuk brand-override render di client.
  const officialHandles = await resolveOfficialMentionHandles(
    combined.flatMap((c) => [
      c.content,
      ...c.replies.map((reply) => reply.content),
    ]),
    db
  );

  const items: FeedCommentItem[] = combined.map((c) =>
    mapFeedComment(c, viewerLikedIds, officialHandles)
  );

  return {
    items,
    nextCursor: hasMore ? page[page.length - 1].id : null,
  };
}

export type FeedCommentDetailResult =
  | { status: "not-found" }
  | { status: "post-gone" }
  | { status: "ok"; comment: FeedCommentItem };

/**
 * Ambil satu komentar (utk composer balas dari notifikasi). Brand-safe via
 * mapFeedComment (admin → identitas brand, foto null). Bedakan "komentar
 * hilang" vs "post induk hilang" supaya client bisa pesan yang tepat —
 * comment routes tak cascade-delete komentar saat post dihapus, jadi guard
 * post WAJIB (pola sama seperti like-route).
 */
export async function getFeedCommentDetail({
  commentId,
  viewerUserId,
  db = prisma,
}: {
  commentId: string;
  viewerUserId?: string | null;
  db?: Pick<
    Prisma.TransactionClient,
    "feedComment" | "feedCommentLike" | "user"
  >;
}): Promise<FeedCommentDetailResult> {
  const comment = await db.feedComment.findUnique({
    where: { id: commentId },
    include: {
      ...FEED_COMMENT_THREAD_INCLUDE,
      post: { select: { status: true, deletedAt: true } },
      parent: { select: { isHidden: true } },
    },
  });
  if (
    !comment ||
    comment.deletedAt !== null ||
    comment.isHidden ||
    comment.parent?.isHidden
  ) {
    return { status: "not-found" };
  }
  if (
    !comment.post ||
    comment.post.status !== "ACTIVE" ||
    comment.post.deletedAt !== null
  ) {
    return { status: "post-gone" };
  }

  let viewerLikedIds = new Set<string>();
  if (viewerUserId) {
    const commentIds = [comment.id, ...comment.replies.map((r) => r.id)];
    const likes = await db.feedCommentLike.findMany({
      where: { userId: viewerUserId, commentId: { in: commentIds } },
      select: { commentId: true },
    });
    viewerLikedIds = new Set(likes.map((l) => l.commentId));
  }

  const officialHandles = await resolveOfficialMentionHandles(
    [comment.content, ...comment.replies.map((r) => r.content)],
    db,
  );

  return {
    status: "ok",
    comment: mapFeedComment(comment, viewerLikedIds, officialHandles),
  };
}
