/**
 * PATCH /api/reviews/[id] — edit review (owner, dalam 30 hari)
 * DELETE /api/reviews/[id] — soft delete (owner)
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { editReview, softDeleteReview } from "@/lib/reviews";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: "Login dulu" }, { status: 401 });

    const { id } = await params;
    const body = await request.json();

    const review = await editReview({
      reviewId: id,
      userId: session.sub,
      rating: body.rating !== undefined ? Number(body.rating) : undefined,
      title: body.title,
      content: body.content,
      imageUrls: Array.isArray(body.imageUrls) ? body.imageUrls : undefined,
    });

    return NextResponse.json({ review });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal edit review" },
      { status: 400 }
    );
  }
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: "Login dulu" }, { status: 401 });

    const { id } = await params;
    await softDeleteReview(id, session.sub);
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal hapus review" },
      { status: 400 }
    );
  }
}
