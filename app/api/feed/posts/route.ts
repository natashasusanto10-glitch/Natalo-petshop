/**
 * GET /api/feed/posts?tab=REKOMENDASI|PROMO|KOMUNITAS&cursor=<postId>
 *
 * Public endpoint — kalau session ada, response include `viewerLiked`
 * per item. Tanpa session, semua `viewerLiked` = false.
 *
 * MVP: hanya GET (list). POST untuk admin create di F4/F5.
 *
 * Rate limit: skip dulu — public read endpoint dgn cursor pagination
 * relatif murah. Bisa di-add nanti kalau abuse pattern muncul.
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedPostTab } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { listFeedPosts } from "@/lib/feed/queries";

const VALID_TABS: ReadonlyArray<FeedPostTab> = ["REKOMENDASI", "PROMO", "KOMUNITAS"];

function isValidTab(value: string | null): value is FeedPostTab {
  return value !== null && (VALID_TABS as ReadonlyArray<string>).includes(value);
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const rawTab = searchParams.get("tab");
  if (!isValidTab(rawTab)) {
    return NextResponse.json(
      { error: "Parameter `tab` harus REKOMENDASI, PROMO, atau KOMUNITAS." },
      { status: 400 },
    );
  }

  const cursor = searchParams.get("cursor") || null;

  // Session lookup di endpoint public ini opsional. Kalau ada, kita
  // compute viewerLiked per item. Tidak melempar error kalau gagal —
  // fallback ke anonymous read.
  const session = await getSession().catch(() => null);

  const result = await listFeedPosts({
    tab: rawTab,
    cursor,
    viewerUserId: session?.sub ?? null,
  });

  return NextResponse.json(result);
}
