import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { setReviewStatus } from "@/lib/reviews";
import type { ReviewStatus } from "@prisma/client";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const session = await getSession();
    if (!session || session.role !== "ADMIN")
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const { id } = await params;
    const body = await request.json();
    const status = body.status as ReviewStatus;
    if (!["VISIBLE", "HIDDEN", "DELETED"].includes(status))
      return NextResponse.json({ error: "Status tidak valid" }, { status: 400 });

    const review = await setReviewStatus(id, status, body.hiddenReason);
    return NextResponse.json({ review });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal update status" },
      { status: 400 }
    );
  }
}
