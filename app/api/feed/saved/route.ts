import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { listSavedFeedPosts } from "@/lib/feed/queries";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      {
        error: "LOGIN_REQUIRED",
        message: "Login dulu untuk lihat postingan tersimpan.",
      },
      { status: 401 },
    );
  }

  const result = await listSavedFeedPosts({
    userId: session.sub,
    cursor: request.nextUrl.searchParams.get("cursor"),
  });
  return NextResponse.json(result);
}
