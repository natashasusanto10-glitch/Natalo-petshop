/**
 * GET /api/products/[slug]/feed-posts
 *
 * Return semua FeedPost yang tag produk dengan slug ini. Dipakai untuk
 * section "Postingan Pelanggan" di product detail page — UGC video review
 * sebagai social proof.
 *
 * Query strategy:
 *   - Resolve slug → productId (1 query)
 *   - JOIN via FeedPostProduct (many-to-many) + fallback ke FeedPost.productId
 *     (legacy posts yang belum di-backfill)
 *   - Filter: status=ACTIVE, deletedAt=null, dan punya thumbnail/cover.
 *     Video harus encodingStatus=ready; PHOTO_CAROUSEL pakai media pertama.
 *   - Sort: likeCount DESC + createdAt DESC (paling banyak interaksi dulu)
 *   - Limit: ?limit=N (default 12, max 24)
 *
 * Cache 60s — UGC tidak diharapkan update tiap detik, satu menit window OK.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { signBunnyUrl } from "@/lib/feed/bunny";

export const revalidate = 60;

const DEFAULT_LIMIT = 12;
const MAX_LIMIT = 24;

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ slug: string }> }
) {
  const { slug } = await params;
  const { searchParams } = new URL(request.url);
  const rawLimit = Number(searchParams.get("limit") ?? DEFAULT_LIMIT);
  const limit = Math.max(
    1,
    Math.min(MAX_LIMIT, Number.isFinite(rawLimit) ? rawLimit : DEFAULT_LIMIT)
  );

  const product = await prisma.product.findUnique({
    where: { slug },
    select: { id: true, name: true },
  });
  if (!product) {
    return NextResponse.json({ items: [], total: 0 }, { status: 404 });
  }

  // Two queries digabung dengan UNION semantics di app layer:
  //   1. Posts yang reference produk lewat FeedPostProduct (multi-tag)
  //   2. Posts legacy yang cuma punya FeedPost.productId (pre-migration)
  // Pakai distinct di app-level supaya satu post tidak duplicate.
  const posts = await prisma.feedPost.findMany({
    where: {
      status: "ACTIVE",
      deletedAt: null,
      OR: [
        {
          encodingStatus: "ready",
          videoUrl: { not: null },
          thumbnailUrl: { not: null },
        },
        {
          kind: "PHOTO_CAROUSEL",
          media: { some: { url: { not: "" } } },
        },
      ],
      AND: {
        OR: [
          { productId: product.id },
          { taggedProducts: { some: { productId: product.id } } },
        ],
      },
    },
    orderBy: [{ likeCount: "desc" }, { createdAt: "desc" }],
    take: limit,
    select: {
      id: true,
      kind: true,
      title: true,
      thumbnailUrl: true,
      videoDurationSec: true,
      likeCount: true,
      commentCount: true,
      createdAt: true,
      author: { select: { id: true, name: true, role: true } },
      media: {
        orderBy: { sortOrder: "asc" },
        take: 1,
        select: { url: true, thumbnailUrl: true },
      },
    },
  });

  const totalCount = await prisma.feedPost.count({
    where: {
      status: "ACTIVE",
      deletedAt: null,
      OR: [
        {
          encodingStatus: "ready",
          videoUrl: { not: null },
          thumbnailUrl: { not: null },
        },
        {
          kind: "PHOTO_CAROUSEL",
          media: { some: { url: { not: "" } } },
        },
      ],
      AND: {
        OR: [
          { productId: product.id },
          { taggedProducts: { some: { productId: product.id } } },
        ],
      },
    },
  });

  return NextResponse.json({
    productSlug: slug,
    productName: product.name,
    total: totalCount,
    items: posts.map((p) => {
      const firstMedia = p.media[0] ?? null;
      const coverUrl =
        p.kind === "PHOTO_CAROUSEL"
          ? firstMedia?.thumbnailUrl ?? firstMedia?.url ?? null
          : p.thumbnailUrl;

      return {
        id: p.id,
        kind: p.kind,
        title: p.title,
        thumbnailUrl: signBunnyUrl(coverUrl) ?? null,
        videoDurationSec: p.videoDurationSec,
        likeCount: p.likeCount,
        commentCount: p.commentCount,
        createdAt: p.createdAt.toISOString(),
        author: {
          id: p.author.id,
          name: p.author.name,
          role: p.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
        },
      };
    }),
  });
}
