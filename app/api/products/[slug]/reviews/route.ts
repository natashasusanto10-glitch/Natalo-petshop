/**
 * GET /api/products/[slug]/reviews?rating=5&with_image=true&sort=newest|helpful|rating_high|rating_low&cursor=ID&limit=10
 * GET /api/products/[slug]/reviews/summary  → return {avgRating, reviewCount, ratingBreakdown}
 *
 * Untuk endpoint ini (route.ts), GET return list. Summary ada di /summary route.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { maskName } from "@/lib/reviews";
import { brandPhotoUrl } from "@/lib/social/brand-user";
import type { Prisma } from "@prisma/client";

const PAGE_SIZE = 10;

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ slug: string }> }
) {
  try {
    const { slug } = await params;
    const sp = request.nextUrl.searchParams;
    const ratingParam = sp.get("rating");
    const withImage = sp.get("with_image") === "true";
    const sort = sp.get("sort") ?? "newest";
    const cursor = sp.get("cursor");
    const limit = Math.min(50, Number(sp.get("limit") ?? PAGE_SIZE));

    const product = await prisma.product.findUnique({
      where: { slug },
      select: { id: true },
    });
    if (!product) {
      return NextResponse.json(
        { error: "Produk tidak ditemukan" },
        { status: 404 }
      );
    }

    const where: Prisma.ReviewWhereInput = {
      productId: product.id,
      status: "VISIBLE",
    };
    if (ratingParam) {
      const r = Number(ratingParam);
      if (r >= 1 && r <= 5) where.rating = r;
    }
    if (withImage) {
      where.images = { some: {} };
    }

    let orderBy:
      | Prisma.ReviewOrderByWithRelationInput
      | Prisma.ReviewOrderByWithRelationInput[] = { createdAt: "desc" };
    if (sort === "helpful")
      orderBy = [{ helpfulCount: "desc" }, { createdAt: "desc" }];
    else if (sort === "rating_high")
      orderBy = [{ rating: "desc" }, { createdAt: "desc" }];
    else if (sort === "rating_low")
      orderBy = [{ rating: "asc" }, { createdAt: "desc" }];

    const reviews = await prisma.review.findMany({
      where,
      orderBy,
      take: limit + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      include: {
        user: { select: { name: true, role: true, profilePhotoUrl: true } },
        images: { orderBy: { position: "asc" } },
        reply: true,
      },
    });

    const hasMore = reviews.length > limit;
    const results = hasMore ? reviews.slice(0, limit) : reviews;
    const nextCursor = hasMore ? results[results.length - 1].id : null;

    return NextResponse.json({
      reviews: results.map((r) => {
        const reviewImages = r.images as Array<{
          imageUrl: string;
          mediaType?: string | null;
          videoUrl?: string | null;
          thumbnailUrl?: string | null;
        }>;

        return {
          id: r.id,
          rating: r.rating,
          title: r.title,
          content: r.content,
          variantLabel: r.variantLabel,
          helpfulCount: r.helpfulCount,
          createdAt: r.createdAt,
          userName: maskName(r.user.name),
          // Brand-safe: kalau reviewer adalah akun ADMIN, foto pribadi
          // pemilik tidak boleh bocor — lihat lib/social/brand-user.ts.
          userAvatarUrl: brandPhotoUrl(r.user.role, r.user.profilePhotoUrl),
          images: reviewImages
            .filter((i) => i.mediaType !== "video")
            .map((i) => i.imageUrl),
          media: reviewImages.map((i) => ({
            type: i.mediaType === "video" ? "video" : "image",
            url:
              i.mediaType === "video" ? i.videoUrl ?? i.imageUrl : i.imageUrl,
            thumbnailUrl: i.thumbnailUrl ?? i.imageUrl,
          })),
          reply: r.reply
            ? { content: r.reply.content, createdAt: r.reply.createdAt }
            : null,
        };
      }),
      nextCursor,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Gagal mengambil review",
      },
      { status: 500 }
    );
  }
}
