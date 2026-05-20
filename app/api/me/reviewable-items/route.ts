/**
 * GET /api/me/reviewable-items
 *
 * Return SEMUA order items dari order DELIVERED milik user — baik yang
 * belum direview maupun sudah. Item yang sudah direview di-attach
 * `review` map supaya Flutter bisa render tab "Sudah Review".
 *
 * Sebelumnya endpoint ini filter `reviews: { none: ... }` → item yang
 * sudah direview hilang dari response → tab "Sudah Review" di Flutter
 * selalu kosong padahal user sudah submit. Filter dipindah ke layer
 * include (only show this user's own active reviews) supaya UI bisa
 * dapat full picture: pending + reviewed dalam satu response.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) return NextResponse.json({ error: "Login dulu" }, { status: 401 });

  const items = await prisma.orderItem.findMany({
    where: {
      order: { userId: session.sub, status: "DELIVERED" },
    },
    include: {
      product: { select: { id: true, slug: true, imageUrl: true } },
      order: { select: { orderNumber: true, createdAt: true } },
      reviews: {
        where: {
          userId: session.sub,
          status: { not: "DELETED" },
        },
        select: {
          id: true,
          rating: true,
          title: true,
          content: true,
          createdAt: true,
        },
        // Theoretically ada multiple kalau user soft-delete + resubmit
        // (lihat comment di schema model Review.reviews[]). Ambil yang
        // paling baru sebagai "active" review untuk UI consumer.
        orderBy: { createdAt: "desc" },
        take: 1,
      },
    },
    orderBy: { order: { createdAt: "desc" } },
  });

  // Flatten `reviews[]` → singular `review`. Flutter ReviewableItem
  // model expect `review` map (singular) — lihat models/review.dart
  // ReviewableItem.fromJson `final review = json['review']`.
  const mapped = items.map((item) => {
    const review = item.reviews[0] ?? null;
    const { reviews: _reviews, ...rest } = item;
    return {
      ...rest,
      review,
      hasReviewed: review !== null,
    };
  });

  return NextResponse.json({ items: mapped });
}
