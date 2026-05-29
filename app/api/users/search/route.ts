/**
 * GET /api/users/search?q=as&limit=8
 *
 * Autocomplete dropdown buat @mention picker + Feed user search di Flutter.
 * Match username + name supaya social discovery bisa cari akun dari
 * username maupun nama tampilan.
 * Login required — supaya gak ke-scrape oleh bot anonymous.
 *
 * Ordering rules:
 *   1. Exact match `q == username` di posisi pertama (kalau ada).
 *   2. Match prefix username → sort by relevance (length asc — handle
 *      lebih pendek = lebih relevan, e.g. q="asi" → "asiong" di atas
 *      "asihanjaya").
 *   3. Name match sebagai fallback untuk Feed Search.
 *   4. Limit 8 default, max 20.
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
  const wantsSuggested =
    request.nextUrl.searchParams.get("suggested") === "1" ||
    request.nextUrl.searchParams.get("suggested") === "true";

  const rawLimit = Number(
    request.nextUrl.searchParams.get("limit") ?? `${DEFAULT_LIMIT}`,
  );
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(MAX_LIMIT, Math.max(1, Math.floor(rawLimit)))
      : DEFAULT_LIMIT;

  const users =
    q.length === 0
      ? wantsSuggested
        ? await prisma.user.findMany({
            where: {
              id: { not: session.sub },
              role: "CUSTOMER",
              NOT: { username: null },
            },
            select: userSearchSelect,
            take: limit,
            orderBy: [{ followersCount: "desc" }, { createdAt: "desc" }],
          })
        : []
      : await prisma.user.findMany({
          where: {
            OR: [
              { username: { startsWith: q } },
              { username: { contains: q } },
              { name: { contains: qRaw.trim(), mode: "insensitive" } },
            ],
            // Skip null usernames (existing user yang belum set) — gak bisa
            // di-mention anyway.
            NOT: { username: null },
          },
          select: userSearchSelect,
          // Fetch 2× limit untuk reorder client-side (exact match dulu).
          take: limit * 2,
          orderBy: { username: "asc" },
        });

  const followedIds = new Set<string>();
  const candidateIds = users.map((u) => u.id);
  if (candidateIds.length > 0) {
    const follows = await prisma.userFollow.findMany({
      where: {
        followerId: session.sub,
        followingId: { in: candidateIds },
      },
      select: { followingId: true },
    });
    for (const follow of follows) followedIds.add(follow.followingId);
  }

  // Sort: exact username first, username prefix next, then name matches.
  // Alphabetical tie-break supaya hasil stabil. Suggested list already
  // sorted by followersCount/newness from DB.
  const sorted =
    q.length === 0
      ? users
      : users.sort((a, b) => {
          const aRank = relevanceRank(a, q);
          const bRank = relevanceRank(b, q);
          if (aRank !== bRank) return aRank - bRank;
          const lenDiff =
            (a.username?.length ?? 0) - (b.username?.length ?? 0);
          if (lenDiff !== 0) return lenDiff;
          return (a.username ?? "").localeCompare(b.username ?? "");
        });

  return NextResponse.json({
    items: sorted.slice(0, limit).map((u) => ({
      id: u.id,
      name: u.name,
      username: u.username,
      profilePhotoUrl: u.profilePhotoUrl,
      bio: u.bio,
      followersCount: u.followersCount,
      followingCount: u.followingCount,
      isFollowing: u.id === session.sub ? false : followedIds.has(u.id),
      isSelf: u.id === session.sub,
    })),
  });
}

const userSearchSelect = {
  id: true,
  name: true,
  username: true,
  profilePhotoUrl: true,
  bio: true,
  followersCount: true,
  followingCount: true,
} as const;

function relevanceRank(
  user: { name: string; username: string | null },
  q: string,
) {
  const username = user.username ?? "";
  const name = user.name.toLowerCase();
  if (username === q) return 0;
  if (username.startsWith(q)) return 1;
  if (name.startsWith(q)) return 2;
  if (username.includes(q)) return 3;
  if (name.includes(q)) return 4;
  return 9;
}
