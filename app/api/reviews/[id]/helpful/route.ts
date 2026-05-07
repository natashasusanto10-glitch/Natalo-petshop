/**
 * POST /api/reviews/[id]/helpful — toggle helpful vote
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { toggleHelpful } from "@/lib/reviews";

export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const session = await getSession();
    if (!session) return NextResponse.json({ error: "Login dulu" }, { status: 401 });

    const { id } = await params;
    const result = await toggleHelpful(id, session.sub);
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal vote" },
      { status: 400 }
    );
  }
}
