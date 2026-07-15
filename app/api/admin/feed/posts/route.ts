/**
 * GET /api/admin/feed/posts?filter=...&cursor=...
 *
 * Admin-only listing dgn filter:
 *   - all             → semua post (default, EXCLUDE soft-deleted)
 *   - admin_video     → kind in (VIDEO_ONLY, VIDEO_PRODUCT, PRODUCT_ONLY, PROMO)
 *   - user_video      → kind = COMMUNITY
 *   - pending         → status = PENDING_REVIEW (queue moderasi)
 *   - rejected        → status = REJECTED
 *   - hidden          → status = HIDDEN
 *   - deleted         → soft-deleted (deletedAt != null) — explicit trash view
 *
 * Default: semua filter exclude soft-deleted posts. Filter `deleted`
 * khusus untuk admin yang mau lihat trash / restore.
 *
 * Sort: PENDING queue oldest-first (FIFO), lainnya newest-first.
 * Return shape mirip FeedListResponse tapi exposed full status + moderation
 * fields supaya admin bisa decide action.
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedPostKind, FeedPostStatus, Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { bunnyThumbnailUrl, signBunnyUrl } from "@/lib/feed/bunny";
import { feedAccessibilityPayload } from "@/lib/feed/accessibility";
import { reconcileFeedPost } from "@/lib/feed/reconcile";

const PAGE_SIZE = 20;

type AdminFilter =
  | "all"
  | "admin_video"
  | "user_video"
  | "pending"
  | "rejected"
  | "hidden"
  | "deleted";

const VALID_FILTERS: AdminFilter[] = [
  "all",
  "admin_video",
  "user_video",
  "pending",
  "rejected",
  "hidden",
  "deleted",
];

const ADMIN_KINDS: FeedPostKind[] = [
  "VIDEO_ONLY",
  "PRODUCT_ONLY",
  "VIDEO_PRODUCT",
  "PROMO",
];

function buildWhere(filter: AdminFilter): Prisma.FeedPostWhereInput {
  // Default: exclude soft-deleted post. Filter `deleted` khusus override.
  const notDeleted: Prisma.FeedPostWhereInput = { deletedAt: null };
  switch (filter) {
    case "admin_video":
      return { ...notDeleted, kind: { in: ADMIN_KINDS } };
    case "user_video":
      return { ...notDeleted, kind: "COMMUNITY" };
    case "pending":
      return { ...notDeleted, status: "PENDING_REVIEW" };
    case "rejected":
      return { ...notDeleted, status: "REJECTED" };
    case "hidden":
      return { ...notDeleted, status: "HIDDEN" };
    case "deleted":
      // Trash view — hanya soft-deleted yang muncul.
      return { deletedAt: { not: null } };
    case "all":
    default:
      return notDeleted;
  }
}

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const rawFilter = searchParams.get("filter") ?? "all";
  const filter: AdminFilter = (VALID_FILTERS as string[]).includes(rawFilter)
    ? (rawFilter as AdminFilter)
    : "all";
  const cursor = searchParams.get("cursor") || null;

  const where = buildWhere(filter);
  // Pending queue FIFO (oldest first); lainnya newest first.
  const orderBy: Prisma.FeedPostOrderByWithRelationInput[] =
    filter === "pending"
      ? [{ createdAt: "asc" }, { id: "asc" }]
      : [{ createdAt: "desc" }, { id: "desc" }];

  const posts = await prisma.feedPost.findMany({
    where,
    orderBy,
    take: PAGE_SIZE + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: {
      author: { select: { id: true, name: true, role: true } },
      product: { select: { id: true, slug: true, name: true } },
      moderatedBy: { select: { id: true, name: true } },
      // PHOTO_CAROUSEL media — admin list butuh first photo sebagai
      // thumbnail (PHOTO_CAROUSEL post tidak punya videoUrl/thumbnailUrl,
      // jadi tanpa media tampil "No thumb" placeholder yang messy).
      // Take 1 saja (urutan pertama by sortOrder) untuk performance.
      media: {
        select: {
          id: true,
          url: true,
          thumbnailUrl: true,
          altText: true,
          sortOrder: true,
        },
        orderBy: { sortOrder: "asc" },
        take: 1,
      },
      // Count semua media untuk display "Foto (N)" badge.
      _count: { select: { media: true } },
    },
  });

  const hasMore = posts.length > PAGE_SIZE;
  const sliced = hasMore ? posts.slice(0, PAGE_SIZE) : posts;

  // Self-heal: kalau ada post yang nyangkut di "uploading" / "processing"
  // padahal Bunny webhook seharusnya udah firing, polling Bunny secara
  // background. Fire-and-forget (tidak await) supaya admin list response
  // tetap cepat. Cap 10 row per request supaya tidak abuse Bunny API
  // bahkan saat ada banyak post stuck. Admin refresh halaman → row yang
  // udah selesai re-render sebagai "ready".
  // Hanya di-trigger untuk first page (cursor null) supaya pagination tidak
  // re-trigger reconcile setiap scroll.
  if (!cursor) {
    const stuck = sliced.filter(
      (p) =>
        p.videoGuid &&
        (p.encodingStatus === "uploading" || p.encodingStatus === "processing"),
    );
    if (stuck.length > 0) {
      for (const p of stuck.slice(0, 10)) {
        void reconcileFeedPost(p.id).catch((err) => {
          console.warn("[admin-list] reconcile failed:", p.id, err);
        });
      }
    }
  }

  type Item = {
    id: string;
    status: FeedPostStatus;
    // Bunny encoding lifecycle ("uploading" | "processing" | "ready" |
    // "failed"). Admin UI pakai field ini untuk disable tombol Approve
    // selama video belum siap — kalau di-approve saat encodingStatus ≠
    // "ready", post di-set ACTIVE tapi feed query tetap exclude (lihat
    // lib/feed/queries.ts encodingStatus filter), jadi admin lihat
    // "sudah approve" tapi post tidak muncul di feed.
    encodingStatus: string;
    kind: FeedPostKind;
    tab: string;
    title: string;
    description: string | null;
    videoUrl: string | null;
    thumbnailUrl: string | null;
    videoAltText: string | null;
    hasAudio: boolean | null;
    subtitleUrl: string | null;
    subtitleLanguage: string | null;
    // First media URL untuk PHOTO_CAROUSEL — admin list pakai sebagai
    // thumbnail kalau thumbnailUrl null (video) tidak ada. Null untuk
    // post tanpa media (PRODUCT_ONLY, etc).
    firstMediaUrl: string | null;
    firstMediaAltText: string | null;
    /** Total media count — display "Foto (N)" badge di list. */
    mediaCount: number;
    videoDurationSec: number | null;
    product: { id: string; slug: string; name: string } | null;
    promo: {
      originalPrice: number;
      discountPrice: number;
      startsAt: string | null;
      endsAt: string | null;
    } | null;
    likeCount: number;
    commentCount: number;
    viewCount: number;
    author: { id: string; name: string; role: string };
    moderatedBy: { id: string; name: string } | null;
    moderatedAt: string | null;
    moderationNote: string | null;
    publishedAt: string | null;
    createdAt: string;
  };

  const items: Item[] = sliced.map((p) => ({
    id: p.id,
    status: p.status,
    encodingStatus: p.encodingStatus,
    kind: p.kind,
    tab: p.tab,
    title: p.title,
    description: p.description,
    videoUrl: signBunnyUrl(p.videoUrl) ?? null,
    thumbnailUrl:
      signBunnyUrl(
        p.thumbnailUrl ?? (p.videoGuid ? bunnyThumbnailUrl(p.videoGuid) : null),
      ) ?? null,
    ...feedAccessibilityPayload(p, signBunnyUrl),
    // First media item (PHOTO_CAROUSEL) — pakai thumbnailUrl kalau ada
    // (uploaded thumbnail), fallback ke url full image. Sign kalau dari
    // Bunny CDN (defensive — biasanya UploadThing direct URL untuk photo).
    firstMediaUrl: p.media[0]
      ? signBunnyUrl(p.media[0].thumbnailUrl ?? p.media[0].url) ?? null
      : null,
    firstMediaAltText: p.media[0]?.altText ?? null,
    mediaCount: p._count.media,
    videoDurationSec: p.videoDurationSec,
    product: p.product
      ? { id: p.product.id, slug: p.product.slug, name: p.product.name }
      : null,
    promo:
      p.promoOriginalPrice != null && p.promoDiscountPrice != null
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
    author: { id: p.author.id, name: p.author.name, role: p.author.role },
    moderatedBy: p.moderatedBy ? { id: p.moderatedBy.id, name: p.moderatedBy.name } : null,
    moderatedAt: p.moderatedAt?.toISOString() ?? null,
    moderationNote: p.moderationNote,
    publishedAt: p.publishedAt?.toISOString() ?? null,
    createdAt: p.createdAt.toISOString(),
  }));

  // Counts untuk filter badges. SEMUA count EXCLUDE soft-deleted kecuali
  // deletedCount yang khusus untuk "deleted" filter badge.
  const [pendingCount, totalCount, deletedCount] = await Promise.all([
    prisma.feedPost.count({
      where: { status: "PENDING_REVIEW", deletedAt: null },
    }),
    prisma.feedPost.count({ where: { deletedAt: null } }),
    prisma.feedPost.count({ where: { deletedAt: { not: null } } }),
  ]);

  return NextResponse.json({
    items,
    nextCursor: hasMore ? sliced[sliced.length - 1].id : null,
    counts: {
      pending: pendingCount,
      total: totalCount,
      deleted: deletedCount,
    },
  });
}
