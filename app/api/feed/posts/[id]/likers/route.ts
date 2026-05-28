/**
 * GET /api/feed/posts/[id]/likers?cursor=<ISO>&limit=20
 *
 * Public endpoint — return paginated list user yang like sebuah feed post.
 * Dipakai oleh Flutter `_PostLikersSheet` (IG-style "Likes" bottom sheet)
 * yang muncul saat user tap "X orang lainnya" atau avatar stack di
 * `_LikedByLine` widget.
 *
 * Pagination: cursor = `createdAt.toISOString()` dari like terakhir di
 * batch sebelumnya. FeedLike pakai composite primary key (userId, postId)
 * tanpa id sendiri, jadi cursor pakai timestamp (orderBy createdAt desc).
 *
 * Auth optional — kalau viewer login, tambah field `isFollowing` per row
 * supaya UI bisa tampilkan tombol Follow/Mengikuti yang akurat tanpa
 * extra round-trip per row. Kalau anon (belum login), `isFollowing`
 * selalu false.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const session = await getSession("CUSTOMER");
  const viewerUserId = session?.sub ?? null;

  // Verify post exists + visible. Tidak strict like API u/[username] yang
  // filter status ACTIVE — likers list untuk post Anda sendiri (yang
  // mungkin PENDING_REVIEW) juga harus accessible.
  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: { id: true, deletedAt: true },
  });
  if (!post || post.deletedAt) {
    return NextResponse.json({ error: "Post tidak ditemukan." }, { status: 404 });
  }

  // Compound keyset cursor — format "<ISO>_<userId>". FeedLike composite
  // PK (userId, postId) tanpa id sendiri, jadi createdAt saja TIDAK
  // cukup sebagai cursor: kalau ≥2 like punya createdAt identik
  // (bulk/seeded data atau like cepat berturut), filter `lt: createdAt`
  // bakal exclude SELURUH timestamp itu → rows sisa di boundary
  // ke-skip silent. Encode userId sebagai tiebreaker supaya keyset
  // pagination strict-total-order: (createdAt, userId) DESC.
  const cursorRaw = request.nextUrl.searchParams.get("cursor");
  let cursorDate: Date | null = null;
  let cursorUserId: string | null = null;
  if (cursorRaw && cursorRaw.length > 0) {
    const sep = cursorRaw.lastIndexOf("_");
    const datePart = sep >= 0 ? cursorRaw.slice(0, sep) : cursorRaw;
    cursorUserId = sep >= 0 ? cursorRaw.slice(sep + 1) : null;
    const parsed = new Date(datePart);
    if (!Number.isNaN(parsed.getTime())) cursorDate = parsed;
  }
  const isValidCursor = cursorDate !== null;

  const limitRaw = Number(
    request.nextUrl.searchParams.get("limit") ?? `${DEFAULT_LIMIT}`,
  );
  const limit =
    Number.isFinite(limitRaw) && limitRaw > 0
      ? Math.min(MAX_LIMIT, Math.max(1, Math.floor(limitRaw)))
      : DEFAULT_LIMIT;

  const rows = await prisma.feedLike.findMany({
    where: {
      postId,
      // Keyset: (createdAt < cursor) OR (createdAt == cursor AND
      // userId < cursorUserId). Match orderBy [createdAt desc,
      // userId desc] supaya tidak ada row ke-skip maupun duplikat.
      ...(isValidCursor
        ? {
            OR: [
              { createdAt: { lt: cursorDate! } },
              ...(cursorUserId
                ? [
                    {
                      createdAt: cursorDate!,
                      userId: { lt: cursorUserId },
                    },
                  ]
                : []),
            ],
          }
        : {}),
    },
    orderBy: [{ createdAt: "desc" }, { userId: "desc" }],
    take: limit + 1,
    select: {
      createdAt: true,
      userId: true,
      user: {
        select: {
          id: true,
          name: true,
          username: true,
          profilePhotoUrl: true,
          bio: true,
          followersCount: true,
          followingCount: true,
        },
      },
    },
  });

  const hasMore = rows.length > limit;
  const sliced = hasMore ? rows.slice(0, limit) : rows;

  // Batch resolve viewer's follow state untuk semua user di batch ini —
  // 1 query sebagai Set, alih-alih N queries per row. Tanpa session,
  // skip resolve (isFollowing default false).
  const followedIds = new Set<string>();
  if (viewerUserId && sliced.length > 0) {
    const targetIds = sliced
      .map((row) => row.user.id)
      .filter((id) => id !== viewerUserId);
    if (targetIds.length > 0) {
      const follows = await prisma.userFollow.findMany({
        where: {
          followerId: viewerUserId,
          followingId: { in: targetIds },
        },
        select: { followingId: true },
      });
      for (const f of follows) followedIds.add(f.followingId);
    }
  }

  return NextResponse.json({
    items: sliced.map((row) => ({
      id: row.user.id,
      name: row.user.name,
      username: row.user.username,
      profilePhotoUrl: row.user.profilePhotoUrl,
      bio: row.user.bio,
      followersCount: row.user.followersCount,
      followingCount: row.user.followingCount,
      isFollowing: followedIds.has(row.user.id),
      isSelf: viewerUserId === row.user.id,
    })),
    nextCursor: hasMore
      ? `${sliced[sliced.length - 1].createdAt.toISOString()}_${
          sliced[sliced.length - 1].userId
        }`
      : null,
  });
}
