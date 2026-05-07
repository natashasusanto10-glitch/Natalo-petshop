import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { upsertAdminReply } from "@/lib/reviews";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const session = await getSession("ADMIN");
    if (!session || session.role !== "ADMIN")
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const { id } = await params;
    const body = await request.json();
    const reply = await upsertAdminReply(id, session.sub, String(body.content ?? ""));
    return NextResponse.json({ reply });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal balas" },
      { status: 400 }
    );
  }
}

export const PATCH = POST; // upsert: PATCH = same as POST
