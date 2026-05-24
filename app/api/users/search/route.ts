/**
 * GET /api/users/search?q=as&limit=8
 *
 * Autocomplete dropdown buat @mention picker di Flutter
 * (caption + komentar composer). Prefix match by username.
 * Login required — supaya gak ke-scrape oleh bot anonymous.
 *
 * Ordering rules:
 *   1. Exact match `q == username` di posisi pertama (kalau ada).
 *   2. Match prefix username → sort by relevance (length asc — handle
 *      lebih pendek = lebih relevan, e.g. q="asi" → "asiong" di atas
 *      "asihanjaya").
 *   3. Limit 8 default, max 20.
 *
 * Skip user yang belum punya username (null) supaya picker tidak
 * tampil entry yang gak bisa di-mention.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const DEFAULT_LIMIT = 8;
const MAX_LIMIT = 20;

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "LOGIN_REQUIRED" }, { status: 401 });
  }

  const qRaw = request.nextUrl.searchParams.get("q") ?? "";
  const q = qRaw.trim().toLowerCase().replace(/^@+/, "");
  if (q.length === 0) {
    return NextResponse.json({ items: [] });
  }

  const rawLimit = Number(
    request.nextUrl.searchParams.get("limit") ?? `${DEFAULT_LIMIT}`,
  );
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(MAX_LIMIT, Math.max(1, Math.floor(rawLimit)))
      : DEFAULT_LIMIT;

  // Prefix match query. Username case-insensitive di DB (semua lowercase
  // saat save), jadi prefix match q lowercased langsung work via Prisma
  // `startsWith`.
  const users = await prisma.user.findMany({
    where: {
      username: { startsWith: q },
      // Skip null usernames (existing user yang belum set) — gak bisa
      // di-mention anyway.
      NOT: { username: null },
    },
    select: {
      id: true,
      name: true,
      username: true,
      profilePhotoUrl: true,
    },
    // Fetch 2× limit untuk reorder client-side (exact match dulu).
    take: limit * 2,
    orderBy: { username: "asc" },
  });

  // Sort: exact match first, then by username length (shorter = closer
  // to query prefix → more relevant). Alphabetical tie-break.
  const sorted = users.sort((a, b) => {
    const aExact = a.username === q ? 0 : 1;
    const bExact = b.username === q ? 0 : 1;
    if (aExact !== bExact) return aExact - bExact;
    const lenDiff = (a.username?.length ?? 0) - (b.username?.length ?? 0);
    if (lenDiff !== 0) return lenDiff;
    return (a.username ?? "").localeCompare(b.username ?? "");
  });

  return NextResponse.json({
    items: sorted.slice(0, limit).map((u) => ({
      id: u.id,
      name: u.name,
      username: u.username,
      profilePhotoUrl: u.profilePhotoUrl,
    })),
  });
}
