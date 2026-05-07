/**
 * POST /api/reviews — buat review baru
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createReview } from "@/lib/reviews";

export async function POST(request: NextRequest) {
  try {
    const session = await getSession();
    if (!session)
      return NextResponse.json({ error: "Login dulu" }, { status: 401 });

    const body = await request.json();
    const review = await createReview({
      userId: session.sub,
      orderItemId: String(body.orderItemId ?? ""),
      rating: Number(body.rating),
      title: body.title ?? null,
      content: body.content ?? null,
      imageUrls: Array.isArray(body.imageUrls) ? body.imageUrls : [],
    });

    return NextResponse.json({ review });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal membuat review" },
      { status: 400 }
    );
  }
}
