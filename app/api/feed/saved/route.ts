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

  const rawLimit = request.nextUrl.searchParams.get("limit");
  const requestedLimit = rawLimit === null ? Number.NaN : Number(rawLimit);
  const limit = Number.isInteger(requestedLimit)
    ? Math.min(Math.max(requestedLimit, 1), 30)
    : 20;
  const result = await listSavedFeedPosts({
    userId: session.sub,
    cursor: request.nextUrl.searchParams.get("cursor"),
    limit,
  });
  return NextResponse.json(result);
}
