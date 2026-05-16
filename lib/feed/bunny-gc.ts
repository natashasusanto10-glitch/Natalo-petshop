/**
 * Bunny Stream orphan video sweeper.
 *
 * Walks the Bunny library and deletes any video record that's no longer
 * referenced by a non-deleted FeedPost. Catches orphans from:
 *
 *   - Soft-deleted posts where the cleanup hook didn't run (pre-fix
 *     7c0fd0b: user delete used to skip Bunny cleanup entirely).
 *   - Upload failures mid-flow: server reserved a Bunny placeholder via
 *     POST /api/feed/bunny/upload-url, but the client crashed before
 *     PUT-ing the raw bytes. The placeholder still counts against storage.
 *   - `deleteBunnyVideo()` network failures at delete time (rare).
 *
 * Strategy:
 *   1. Collect `videoGuid` from all non-deleted FeedPost rows → referenced set.
 *   2. Paginate through Bunny library videos.
 *   3. For each Bunny video whose guid is NOT in the referenced set,
 *      delete it (best-effort, log on failure).
 *
 * Safety:
 *   - Soft-deleted posts have `deletedAt != null` → their guids are NOT
 *     in the referenced set → their Bunny videos ARE swept. This is
 *     intentional: if admin/user soft-deleted the post, the video has
 *     no business staying in storage.
 *   - Restore feature (`/api/admin/feed/posts/[id]` action=restore) only
 *     works on rows that still have videoUrl set — restore after Bunny
 *     sweep won't get the playback back. Cron should run AFTER any
 *     possible restore window; the existing weekly schedule is safe.
 */

import { prisma } from "@/lib/prisma";
import { deleteBunnyVideo, listBunnyLibraryVideos } from "./bunny";

export type BunnyGcResult = {
  scanned: number;
  referenced: number;
  orphanFound: number;
  orphanDeleted: number;
  orphanBytes: number;
  errors: number;
};

const PAGE_SIZE = 100;

export async function sweepBunnyOrphans(options?: {
  dryRun?: boolean;
}): Promise<BunnyGcResult> {
  const dryRun = options?.dryRun === true;

  // Collect referenced guids dari FeedPost rows yang masih aktif. Soft-
  // deleted (deletedAt != null) EXCLUDED supaya video-nya boleh di-sweep.
  const activePosts = await prisma.feedPost.findMany({
    where: {
      deletedAt: null,
      videoGuid: { not: null },
    },
    select: { videoGuid: true },
  });
  const referenced = new Set<string>();
  for (const p of activePosts) {
    if (p.videoGuid) referenced.add(p.videoGuid);
  }

  const result: BunnyGcResult = {
    scanned: 0,
    referenced: referenced.size,
    orphanFound: 0,
    orphanDeleted: 0,
    orphanBytes: 0,
    errors: 0,
  };

  let page = 1;
  while (true) {
    const items = await listBunnyLibraryVideos(page, PAGE_SIZE);
    if (!items) {
      result.errors += 1;
      break;
    }
    if (items.length === 0) break;

    for (const item of items) {
      result.scanned += 1;
      if (referenced.has(item.guid)) continue;
      // Orphan found.
      result.orphanFound += 1;
      result.orphanBytes += item.storageSize ?? 0;
      if (!dryRun) {
        const ok = await deleteBunnyVideo(item.guid);
        if (ok) {
          result.orphanDeleted += 1;
        } else {
          result.errors += 1;
        }
      }
    }

    if (items.length < PAGE_SIZE) break;
    page += 1;
    // Safety cap di 50 pages (5000 videos) untuk hindari accidental
    // infinite loop kalau Bunny pagination behave aneh.
    if (page > 50) break;
  }

  return result;
}
