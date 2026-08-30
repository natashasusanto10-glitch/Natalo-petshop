/**
 * GET /api/admin/reviews?status=...&rating=...&q=...&cursor=...
 *
 * List endpoint untuk admin review moderation screen di mobile app.
 *
 * Filter status (default: all):
 *   - visible / hidden / deleted / all
 *
 * Filter rating (optional): 1..5 — kalau diisi cuma return rating tsb.
 *
 * Filter q (optional): cari di title/content review atau nama produk.
 *
 * Sort default newest-first. Cursor-based pagination, page 20.
 *
 * Response include product (slug/name/imageUrl), user (id/name), reply,
 * dan first image — supaya mobile bisa render card lengkap tanpa extra
 * fetch per-row.
 */
import { NextRequest, NextResponse } from "next/server";
import type { Prisma, ReviewStatus } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { reviewSearchWhere } from "@/lib/admin-search";

const PAGE_SIZE = 20;
const VALID_STATUS: ReadonlyArray<string> = ["visible", "hidden", "deleted", "all"];
const STATUS_MAP: Record<string, ReviewStatus> = {
  visible: "VISIBLE",
  hidden: "HIDDEN",
  deleted: "DELETED",
};

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const url = new URL(request.url);
  const rawStatus = (url.searchParams.get("status") ?? "all").toLowerCase();
  const statusFilter = VALID_STATUS.includes(rawStatus) ? rawStatus : "all";
  const ratingRaw = url.searchParams.get("rating");
  const rating = ratingRaw ? parseInt(ratingRaw, 10) : null;
  const q = (url.searchParams.get("q") ?? "").trim();
  const cursor = url.searchParams.get("cursor") || null;

  const where: Prisma.ReviewWhereInput = {};
  if (statusFilter !== "all") {
    where.status = STATUS_MAP[statusFilter];
  }
  if (rating && rating >= 1 && rating <= 5) {
    where.rating = rating;
  }
  // Token-based supaya frasa parsial di isi ulasan tetap ketemu, dan nama
  // produk multi-kata tidak harus diketik urut persis.
  const searchWhere = reviewSearchWhere(q);
  if (searchWhere) where.AND = searchWhere.AND;

  const reviews = await prisma.review.findMany({
    where,
    orderBy: { createdAt: "desc" },
    take: PAGE_SIZE + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: {
      product: {
        select: { id: true, slug: true, name: true, imageUrl: true },
      },
      user: {
        select: { id: true, name: true, profilePhotoUrl: true },
      },
      reply: {
        select: {
          id: true,
          content: true,
          createdAt: true,
          updatedAt: true,
        },
      },
      images: {
        orderBy: { position: "asc" },
        take: 3,
        select: {
          imageUrl: true,
          mediaType: true,
          thumbnailUrl: true,
        },
      },
    },
  });

  const hasMore = reviews.length > PAGE_SIZE;
  const sliced = hasMore ? reviews.slice(0, PAGE_SIZE) : reviews;
  const nextCursor = hasMore ? sliced[sliced.length - 1].id : null;

  // Counts per status untuk tab badge.
  const [visibleCount, hiddenCount, deletedCount] = await Promise.all([
    prisma.review.count({ where: { status: "VISIBLE" } }),
    prisma.review.count({ where: { status: "HIDDEN" } }),
    prisma.review.count({ where: { status: "DELETED" } }),
  ]);

  return NextResponse.json({
    reviews: sliced.map((r) => ({
      id: r.id,
      productId: r.productId,
      product: r.product
        ? {
            id: r.product.id,
            slug: r.product.slug,
            name: r.product.name,
            imageUrl: r.product.imageUrl,
          }
        : null,
      user: r.user
        ? {
            id: r.user.id,
            name: r.user.name,
            profilePhotoUrl: r.user.profilePhotoUrl,
          }
        : null,
      rating: r.rating,
      title: r.title,
      content: r.content,
      status: r.status,
      hiddenReason: r.hiddenReason,
      helpfulCount: r.helpfulCount,
      variantLabel: r.variantLabel,
      images: r.images.map((img) => ({
        imageUrl: img.imageUrl,
        mediaType: img.mediaType,
        thumbnailUrl: img.thumbnailUrl,
      })),
      reply: r.reply
        ? {
            id: r.reply.id,
            content: r.reply.content,
            createdAt: r.reply.createdAt.toISOString(),
            updatedAt: r.reply.updatedAt.toISOString(),
          }
        : null,
      createdAt: r.createdAt.toISOString(),
      updatedAt: r.updatedAt.toISOString(),
    })),
    nextCursor,
    counts: {
      visible: visibleCount,
      hidden: hiddenCount,
      deleted: deletedCount,
    },
    filter: { status: statusFilter, rating, q },
  });
}
