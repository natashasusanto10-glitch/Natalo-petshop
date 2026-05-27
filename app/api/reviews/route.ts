import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { createReview } from "@/lib/reviews";

export async function GET(req: NextRequest) {
  const productId = req.nextUrl.searchParams.get("productId");
  if (!productId)
    return NextResponse.json({ error: "productId required" }, { status: 400 });

  const reviews = await prisma.review.findMany({
    where: { productId, status: "VISIBLE" },
    orderBy: { createdAt: "desc" },
    select: {
      id: true,
      rating: true,
      title: true,
      content: true,
      createdAt: true,
      user: { select: { name: true } },
    },
  });

  return NextResponse.json(reviews);
}

export async function POST(req: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu untuk ulasan." },
      { status: 401 }
    );
  }

  const body = await req.json().catch(() => null);
  if (!body)
    return NextResponse.json({ error: "Invalid body" }, { status: 400 });

  const { productId, orderItemId, rating, title, content, imageUrls, media } =
    body;
  if (!productId || !orderItemId || !rating) {
    return NextResponse.json(
      { error: "productId, orderItemId, rating wajib diisi" },
      { status: 400 }
    );
  }
  if (typeof rating !== "number" || rating < 1 || rating > 5) {
    return NextResponse.json({ error: "Rating harus 1–5" }, { status: 400 });
  }

  try {
    const result = await createReview({
      userId: session.sub,
      orderItemId,
      rating: Math.round(rating),
      title: title ? String(title).slice(0, 120) : null,
      content: content ? String(content).slice(0, 2000) : null,
      imageUrls: Array.isArray(imageUrls) ? imageUrls.map(String) : [],
      media: Array.isArray(media) ? media : undefined,
    });

    // pointsAwarded = 5 kalau review LENGKAP (bintang+desk min 10 char+min 1 foto),
    // 0 kalau belum. Flutter pakai untuk snackbar conditional.
    return NextResponse.json(
      {
        id: result.review.id,
        pointsAwarded: result.pointsAwarded,
      },
      { status: 201 }
    );
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Gagal mengirim review.",
      },
      { status: 400 }
    );
  }
}
