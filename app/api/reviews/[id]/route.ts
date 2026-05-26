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
    const session = await getSession("CUSTOMER");
    if (!session) return NextResponse.json({ error: "Login dulu" }, { status: 401 });

    const { id } = await params;
    const body = await request.json();

    const result = await editReview({
      reviewId: id,
      userId: session.sub,
      rating: body.rating !== undefined ? Number(body.rating) : undefined,
      title: body.title,
      content: body.content,
      imageUrls: Array.isArray(body.imageUrls) ? body.imageUrls : undefined,
    });

    // pointsAwarded > 0 = user upgrade review jadi LENGKAP via edit
    // (retroactive). Flutter pakai untuk snackbar "Selamat! +5 poin loyal".
    return NextResponse.json({
      review: result.review,
      pointsAwarded: result.pointsAwarded,
    });
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
    const session = await getSession("CUSTOMER");
    if (!session) return NextResponse.json({ error: "Login dulu" }, { status: 401 });

    const { id } = await params;
    const result = await softDeleteReview(id, session.sub);
    // pointsRolledBack > 0 = user kehilangan poin karena delete review
    // lengkap yang sebelumnya dapat 5 poin. Flutter pakai untuk warn user.
    return NextResponse.json({
      ok: true,
      pointsRolledBack: result.pointsRolledBack,
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal hapus review" },
      { status: 400 }
    );
  }
}
