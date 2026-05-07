import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function GET(req: NextRequest) {
  const productId = req.nextUrl.searchParams.get("productId");
  if (!productId) return NextResponse.json({ error: "productId required" }, { status: 400 });

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
    return NextResponse.json({ error: "Login dulu untuk ulasan." }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid body" }, { status: 400 });

  const { productId, orderItemId, rating, title, content } = body;
  if (!productId || !orderItemId || !rating) {
    return NextResponse.json(
      { error: "productId, orderItemId, rating wajib diisi" },
      { status: 400 }
    );
  }
  if (typeof rating !== "number" || rating < 1 || rating > 5) {
    return NextResponse.json({ error: "Rating harus 1–5" }, { status: 400 });
  }

  // Verifikasi: order item ini milik user yang login & sudah selesai
  const orderItem = await prisma.orderItem.findUnique({
    where: { id: orderItemId },
    include: { order: { select: { userId: true, status: true } } },
  });
  if (!orderItem || orderItem.order.userId !== session.sub) {
    return NextResponse.json({ error: "Order item tidak ditemukan." }, { status: 404 });
  }
  if (orderItem.order.status !== "DELIVERED") {
    return NextResponse.json(
      { error: "Hanya order yang sudah diterima bisa direview." },
      { status: 400 }
    );
  }

  const review = await prisma.review.create({
    data: {
      productId,
      orderItemId,
      userId: session.sub,
      variantId: orderItem.variantId,
      variantLabel: orderItem.variantLabel,
      rating: Math.round(rating),
      title: title ? String(title).slice(0, 120) : null,
      content: content ? String(content).slice(0, 2000) : null,
    },
  });

  return NextResponse.json({ id: review.id }, { status: 201 });
}
