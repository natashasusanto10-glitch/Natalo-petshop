import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { searchHashtags } from "@/lib/feed/hashtags";

/**
 * GET /api/feed/hashtag-search?q=ku
 *
 * Autocomplete hashtag (Spec C, Task 8) — dipakai HashtagPickerController
 * (Task 12) saat user mengetik '#' di composer caption. Prefix match
 * lowercase, urut postCount desc, maks 8 — lihat `searchHashtags` di
 * lib/feed/hashtags.ts untuk aturan lengkap.
 *
 * Auth: login required, disamakan dengan GET /api/users/search (picker
 * autocomplete lain di app ini) — supaya tidak bisa di-scrape bot anonymous.
 *
 * Rute ini SENGAJA dipindah keluar dari `app/api/feed/hashtags/[name]/` (top-
 * level `hashtag-search`, bukan `hashtags/search`) — Next.js mencocokkan
 * segmen statis `search` sebelum sibling dinamis `[name]`, jadi hashtag yang
 * literally bernama "search" tidak akan pernah bisa reach halaman
 * hashtag-nya sendiri kalau kedua rute berbagi parent `hashtags/`.
 *
 * Catatan postCount: nilai di respons ini adalah cache `Hashtag.postCount`
 * (APPROXIMATE, cuma untuk ranking hasil autocomplete, bisa stale) — beda
 * dengan `postCount` di GET /api/feed/hashtags/[name] yang dihitung live via
 * `prisma.feedPost.count` (exact).
 */
export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "LOGIN_REQUIRED" }, { status: 401 });
  }

  const q = request.nextUrl.searchParams.get("q") ?? "";
  const hashtags = await searchHashtags(prisma, q);
  return NextResponse.json({ hashtags });
}
