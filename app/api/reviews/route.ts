import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function GET(req: NextRequest) {
  const productId = req.nextUrl.searchParams.get("productId");
  if (!productId) return NextResponse.json({ error: "productId required" }, { status: 400 });

  const reviews = await prisma.review.findMany({
    where: { productId, isApproved: true },
    orderBy: { createdAt: "desc" },
    select: { id: true, name: true, rating: true, comment: true, createdAt: true },
  });

  return NextResponse.json(reviews);
}

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid body" }, { status: 400 });

  const { productId, name, rating, comment } = body;
  if (!productId || !name || !rating || !comment) {
    return NextResponse.json({ error: "productId, name, rating, comment wajib diisi" }, { status: 400 });
  }
  if (typeof rating !== "number" || rating < 1 || rating > 5) {
    return NextResponse.json({ error: "Rating harus 1–5" }, { status: 400 });
  }

  const session = await getSession();

  const review = await prisma.review.create({
    data: {
      productId,
      name: String(name).slice(0, 80),
      rating: Math.round(rating),
      comment: String(comment).slice(0, 1000),
      userId: session?.sub ?? null,
      isApproved: false,
    },
  });

  return NextResponse.json({ id: review.id }, { status: 201 });
}
