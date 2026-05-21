/**
 * GET /api/feed/me/likes-count
 *
 * Return jumlah feed post yang user (current session) LIKE — bukan
 * jumlah likes yang user terima di post-nya sendiri.
 *
 * Source: FeedLike table (composite PK userId+postId). Count distinct
 * post yang user pernah like.
 *
 * Dipakai di halaman Akun untuk stat "Disukai" — total post yang
 * pernah user sukai. Lihat flutter_app/lib/screens/member_screen.dart.
 *
 * Auth: customer session required (401 kalau guest).
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "UNAUTHORIZED", count: 0 },
      { status: 401 },
    );
  }

  try {
    const count = await prisma.feedLike.count({
      where: { userId: session.sub },
    });
    return NextResponse.json({ count });
  } catch {
    return NextResponse.json({ count: 0 });
  }
}
