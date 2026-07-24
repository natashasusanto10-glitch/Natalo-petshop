import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { isValidHashtagName, hashtagPostsWhere } from "@/lib/feed/hashtags";
import {
  buildFeedPostInclude,
  resolveFeedBatchContext,
  serializeFeedPostRow,
} from "@/lib/feed/queries";

const PAGE_SIZE = 24;

/**
 * GET /api/feed/hashtags/[name]
 *
 * Halaman hashtag (Spec C, Task 7b) — list post publik yang mengandung
 * hashtag tertentu di caption, urut createdAt desc, cursor pagination.
 * Shape JSON per-post IDENTIK dengan feed utama (GET /api/feed/posts) —
 * reuse `buildFeedPostInclude`/`resolveFeedBatchContext`/`serializeFeedPostRow`
 * dari lib/feed/queries.ts (diekstrak Task 7a dari `listFeedPosts`) supaya
 * tidak ada serializer kedua yang bisa drift dari feed utama.
 *
 * viewerUserId di-resolve persis seperti GET /api/feed/posts: `getSession()`
 * tanpa role (opsional) — anon viewer tetap dapat 200 dengan
 * isLiked/isSaved/isFollowing/viewerTagHidden semua false/null, bukan 401.
 *
 * Catatan postCount: nilai di respons ini dihitung LIVE via
 * `prisma.feedPost.count` (EXACT, di baris `total` di bawah) — beda dengan
 * `postCount` di GET /api/feed/hashtag-search yang cuma cache
 * `Hashtag.postCount` (approximate, bisa stale).
 */
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ name: string }> },
) {
  const { name: raw } = await params;
  const name = raw.toLowerCase();
  if (!isValidHashtagName(name)) {
    return NextResponse.json({ error: "Tag tidak valid." }, { status: 400 });
  }

  const session = await getSession().catch(() => null);
  const viewerUserId = session?.sub ?? null;

  const cursor = new URL(req.url).searchParams.get("cursor");
  const where = hashtagPostsWhere(name);
  // Satu instant `now`, diteruskan ke KEDUA pemanggilan di bawah —
  // buildFeedPostInclude (filter discountItems aktif di query) dan
  // resolveFeedBatchContext (resolveFeedProductDiscount saat serialize).
  // Dua `new Date()` terpisah akan reintroduce drift query/serialize yang
  // sudah dihilangkan Task 7a (lihat komentar buildFeedPostInclude +
  // listFeedPosts di lib/feed/queries.ts).
  const now = new Date();

  const [total, rows] = await Promise.all([
    prisma.feedPost.count({ where }),
    prisma.feedPost.findMany({
      where,
      // Composite sort key (bukan cuma createdAt) — sama seperti
      // listFeedPosts (lib/feed/queries.ts). Tie-breaker `id` WAJIB untuk
      // cursor pagination yang deterministik: dua post dengan createdAt
      // identik tanpa tie-breaker bisa bikin cursor pagination skip/ulangi
      // baris antar-halaman.
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: PAGE_SIZE + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      include: buildFeedPostInclude(now),
    }),
  ]);

  const hasMore = rows.length > PAGE_SIZE;
  const page = hasMore ? rows.slice(0, PAGE_SIZE) : rows;
  // Batch context dihitung atas `page` (sudah di-slice), BUKAN `rows` —
  // beda dengan listFeedPosts yang batch atas seluruh hasil fetch termasuk
  // lookahead row. Baris lookahead di sini tidak pernah diserialize, jadi
  // menghitung batch data untuknya cuma kerja sia-sia.
  const ctx = await resolveFeedBatchContext(page, viewerUserId, now);

  return NextResponse.json({
    name,
    postCount: total, // hitungan akurat dari query, BUKAN Hashtag.postCount cache
    posts: page.map((row) => serializeFeedPostRow(row, ctx)),
    nextCursor: hasMore ? page[page.length - 1].id : null,
  });
}
