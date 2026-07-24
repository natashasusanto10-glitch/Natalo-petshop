import assert from "node:assert/strict";
import test from "node:test";

import { listSavedFeedPosts, type FeedReadDb } from "../lib/feed/queries";

/**
 * Regression guard for the saved-feed truncation/cursor-skip bug.
 *
 * `listSavedFeedPosts` paginates the `feedSave` rows itself (up to `limit`,
 * e.g. 20) and then asks `listFeedPosts` to serialize that batch by id. The
 * bug: `listFeedPosts` hard-capped its own Prisma `take`/slice at
 * FEED_PAGE_SIZE (10) regardless of how many ids the batch asked for, so any
 * saved page larger than 10 silently lost its 11th..Nth posts — and because
 * `nextCursor` was derived from the full saves page, the next fetch skipped
 * right past them, so they vanished from "Tersimpan" permanently.
 *
 * These tests drive the real production functions through an injected
 * in-memory Prisma seam whose `findMany` honours `take` (the SQL LIMIT), which
 * is exactly the layer where the truncation happened.
 */

const BASE_TIME = new Date("2026-07-01T00:00:00.000Z").getTime();

type SavedRow = { postId: string };

/** Minimal-but-complete feedPost row for the serializer (product-less video). */
function makePostRow(id: string, index: number) {
  return {
    id,
    // Newest first: lower index => more recent createdAt, matching save order.
    createdAt: new Date(BASE_TIME - index * 60_000),
    publishedAt: new Date(BASE_TIME - index * 60_000),
    kind: "COMMUNITY",
    tab: "KOMUNITAS",
    status: "ACTIVE",
    title: `post ${id}`,
    description: null,
    videoUrl: `https://example.test/${id}.m3u8`,
    videoGuid: null,
    thumbnailUrl: `https://example.test/${id}.jpg`,
    thumbnailBlurhash: null,
    videoDurationSec: 12,
    videoWidth: 1080,
    videoHeight: 1920,
    videoAltText: null,
    hasAudio: true,
    subtitleUrl: null,
    subtitleLanguage: null,
    authorRole: "CUSTOMER",
    promoOriginalPrice: null,
    promoDiscountPrice: null,
    promoStartsAt: null,
    promoEndsAt: null,
    likeCount: 0,
    commentCount: 0,
    viewCount: 0,
    shareCount: 0,
    product: null,
    taggedProducts: [],
    media: [],
    taggedUsers: [],
    likes: [],
    author: {
      id: `author-${id}`,
      name: `Author ${id}`,
      username: `author_${id}`,
      role: "CUSTOMER",
      profilePhotoUrl: null,
    },
  };
}

/**
 * Build an injected Prisma seam over an ordered (newest-first) list of saved
 * post ids. `feedPost.findMany` deliberately honours `take` + the `id IN (...)`
 * filter + the `createdAt desc` ordering, reproducing the SQL LIMIT semantics
 * that caused the drop.
 */
function makeFakeDb(savedNewestFirst: readonly string[]): FeedReadDb {
  const postById = new Map(
    savedNewestFirst.map((id, index) => [id, makePostRow(id, index)]),
  );

  const db = {
    feedSave: {
      // Two distinct call shapes hit this:
      //  1. listSavedFeedPosts — paginated saves page (orderBy/take/cursor).
      //  2. getViewerSavedPostIds — membership check (where.postId.in).
      findMany: async (args: {
        where?: { postId?: { in?: string[] } };
        take?: number;
        skip?: number;
        cursor?: { userId_postId?: { postId?: string } };
      }): Promise<SavedRow[]> => {
        const inIds = args.where?.postId?.in;
        if (inIds) {
          return inIds
            .filter((id) => postById.has(id))
            .map((postId) => ({ postId }));
        }
        let start = 0;
        const cursorPostId = args.cursor?.userId_postId?.postId;
        if (cursorPostId) {
          start = savedNewestFirst.indexOf(cursorPostId) + (args.skip ?? 0);
        }
        const take = args.take ?? savedNewestFirst.length;
        return savedNewestFirst
          .slice(start, start + take)
          .map((postId) => ({ postId }));
      },
    },
    feedPost: {
      findMany: async (args: {
        where?: { id?: { in?: string[] } };
        take?: number;
      }): Promise<ReturnType<typeof makePostRow>[]> => {
        const inIds = args.where?.id?.in ?? [];
        const rows = inIds
          .map((id) => postById.get(id))
          .filter((row): row is ReturnType<typeof makePostRow> => Boolean(row))
          .sort((a, b) => {
            const byTime = b.createdAt.getTime() - a.createdAt.getTime();
            return byTime !== 0 ? byTime : (a.id < b.id ? 1 : -1);
          });
        // The SQL LIMIT — this is the exact layer the bug truncated at.
        return typeof args.take === "number" ? rows.slice(0, args.take) : rows;
      },
    },
    feedLike: {
      findMany: async (): Promise<Array<{ postId: string }>> => [],
    },
    userFollow: {
      findMany: async (): Promise<Array<{ followingId: string }>> => [],
    },
  };

  return db as unknown as FeedReadDb;
}

test("saved feed returns every id in a single over-sized page (no 10-item truncation)", async () => {
  // 15 saved posts, requested page size 20 (the live Flutter/route value).
  const saved = Array.from({ length: 15 }, (_, i) => `p${String(i).padStart(2, "0")}`);
  const db = makeFakeDb(saved);

  const page = await listSavedFeedPosts({ userId: "viewer-1", limit: 20, db });

  assert.equal(
    page.items.length,
    15,
    "all 15 saved posts must serialize on one page, not be capped at FEED_PAGE_SIZE",
  );
  assert.deepEqual(
    page.items.map((item) => item.id),
    saved,
    "order must follow save order",
  );
  assert.equal(page.nextCursor, null, "single page fits everything → no cursor");
});

test("saved feed never drops or skips posts across paginated pages", async () => {
  // 25 saved posts, page size 20 → forces a second page. The old code lost
  // ids 11..20 of page 1 (truncated to 10) AND advanced the cursor past them.
  const saved = Array.from({ length: 25 }, (_, i) => `p${String(i).padStart(2, "0")}`);
  const db = makeFakeDb(saved);

  const collected: string[] = [];
  let cursor: string | null = null;
  let pages = 0;
  do {
    const page = await listSavedFeedPosts({
      userId: "viewer-1",
      cursor,
      limit: 20,
      db,
    });
    collected.push(...page.items.map((item) => item.id));
    cursor = page.nextCursor;
    if (++pages > 10) throw new Error("pagination did not terminate");
  } while (cursor);

  assert.equal(
    collected.length,
    saved.length,
    "every saved post must appear on exactly one page — none dropped",
  );
  assert.deepEqual(
    new Set(collected),
    new Set(saved),
    "the union of all pages must equal the full saved set (no id skipped by the cursor)",
  );
  assert.deepEqual(
    collected,
    saved,
    "posts must stay in save order with no gaps",
  );
});
