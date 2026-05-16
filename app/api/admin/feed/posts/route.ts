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
    },
  });

  const hasMore = posts.length > PAGE_SIZE;
  const sliced = hasMore ? posts.slice(0, PAGE_SIZE) : posts;

  type Item = {
    id: string;
    status: FeedPostStatus;
    kind: FeedPostKind;
    tab: string;
    title: string;
    description: string | null;
    videoUrl: string | null;
    thumbnailUrl: string | null;
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
    kind: p.kind,
    tab: p.tab,
    title: p.title,
    description: p.description,
    videoUrl: p.videoUrl,
    thumbnailUrl: p.thumbnailUrl,
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
