/**
 * GET /api/cron/feed-storage-gc
 *
 * Scheduled cleanup that walks UploadThing storage and removes files
 * the DB no longer references. Catches orphans from:
 *   - partial uploads that 500'd before the FeedPost row was committed
 *   - hard-deleted posts where storage cleanup failed
 *   - legacy uploads from before the cleanup hook was added
 *
 * Triggered weekly by Vercel Cron (see vercel.json). Auth via the
 * CRON_SECRET header — Vercel injects it on cron-originated calls.
 *
 * Throughput: UploadThing's list API paginates; we walk pages until
 * empty. For each page, batch-delete the orphans in a single API call.
 *
 * Safety: only files in `feed-video-*` and `feed-thumb-*` namespaces
 * are considered. Other product/review/payment-proof uploads share the
 * UploadThing bucket but live in different naming prefixes, so this
 * job will not touch them.
 */

import { NextRequest, NextResponse } from "next/server";
import { utapi } from "@/lib/uploadthing";
import { prisma } from "@/lib/prisma";
import { extractUploadThingKey } from "@/lib/feed/cleanup";
import { sweepBunnyOrphans } from "@/lib/feed/bunny-gc";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const FEED_FILE_PREFIXES = ["feed-video-", "feed-thumb-"];
const PAGE_SIZE = 500;

function isAuthorized(request: NextRequest): boolean {
  const expected = process.env.CRON_SECRET;
  if (!expected) return false;
  const got = request.headers.get("authorization") ?? "";
  return got === `Bearer ${expected}`;
}

export async function GET(request: NextRequest) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // 1. UploadThing sweep (legacy posts pre-Bunny migration).
  const referencedKeys = await collectReferencedKeys();
  const uploadthingSummary = await sweepOrphans(referencedKeys);

  // 2. Bunny Stream sweep (current Feed storage backend). Catch orphans
  //    dari upload failure mid-flow + soft-deleted posts yang cleanup
  //    hook miss/failed di delete time.
  const bunnySummary = await sweepBunnyOrphans({ dryRun: false });

  return NextResponse.json({
    ok: true,
    uploadthing: uploadthingSummary,
    bunny: bunnySummary,
  });
}

/**
 * Build the set of UploadThing keys still referenced by FeedPost rows
 * (videoUrl OR thumbnailUrl). Soft-deleted posts (deletedAt set) are
 * EXCLUDED because their assets have already been freed; if a soft-deleted
 * row still has its URL set we treat it as orphan-eligible.
 */
async function collectReferencedKeys(): Promise<Set<string>> {
  const keys = new Set<string>();
  const posts = await prisma.feedPost.findMany({
    where: { deletedAt: null },
    select: { videoUrl: true, thumbnailUrl: true },
  });
  for (const post of posts) {
    const v = extractUploadThingKey(post.videoUrl);
    const t = extractUploadThingKey(post.thumbnailUrl);
    if (v) keys.add(v);
    if (t) keys.add(t);
  }
  return keys;
}

/**
 * Walk UploadThing's listFiles pages, compare each page to the referenced
 * set, batch-delete the misses. Returns totals for logging.
 */
async function sweepOrphans(referenced: Set<string>) {
  let scanned = 0;
  let orphaned = 0;
  let deleted = 0;
  let pageCursor: number | undefined = undefined;

  while (true) {
    const page = await utapi.listFiles({
      limit: PAGE_SIZE,
      offset: pageCursor ?? 0,
    });
    const items = page.files ?? [];
    if (items.length === 0) break;

    const orphanKeys: string[] = [];
    for (const file of items) {
      scanned += 1;
      const name = file.name ?? "";
      // Only manage feed-scoped uploads.
      if (!FEED_FILE_PREFIXES.some((p) => name.startsWith(p))) continue;
      const key = file.key;
      if (!key) continue;
      if (!referenced.has(key)) {
        orphanKeys.push(key);
      }
    }

    if (orphanKeys.length > 0) {
      orphaned += orphanKeys.length;
      try {
        await utapi.deleteFiles(orphanKeys);
        deleted += orphanKeys.length;
      } catch (err) {
        console.warn(
          `[feed-gc] deleteFiles batch failed (${orphanKeys.length} keys):`,
          err,
        );
      }
    }

    if (items.length < PAGE_SIZE) break;
    pageCursor = (pageCursor ?? 0) + items.length;
  }

  return {
    scanned,
    referenced: referenced.size,
    orphaned,
    deleted,
  };
}
