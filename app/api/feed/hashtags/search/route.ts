import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { searchHashtags } from "@/lib/feed/hashtags";

/**
 * GET /api/feed/hashtags/search?q=ku
 *
 * Autocomplete hashtag (Spec C, Task 8) — dipakai HashtagPickerController
 * (Task 12) saat user mengetik '#' di composer caption. Prefix match
 * lowercase, urut postCount desc, maks 8 — lihat `searchHashtags` di
 * lib/feed/hashtags.ts untuk aturan lengkap.
 *
 * Auth: login required, disamakan dengan GET /api/users/search (picker
 * autocomplete lain di app ini) — supaya tidak bisa di-scrape bot anonymous.
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
