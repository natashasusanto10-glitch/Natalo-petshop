/**
 * UploadThing asset cleanup for feed posts.
 *
 * Called when a customer post is rejected / hidden / hard-deleted so the
 * underlying video + thumbnail files don't pile up forever in UploadThing
 * storage. We don't store the file `key` separately — it's encoded as the
 * last segment of the ufsUrl (https://{appId}.ufs.sh/f/{key}), so we
 * extract it from the saved url string.
 *
 * Fire-and-forget by design: a storage delete failure must never roll
 * back the moderation transition the admin just made.
 */

import { utapi } from "@/lib/uploadthing";

/**
 * Pull the UploadThing file key out of a ufsUrl. Returns null when the URL
 * is missing or doesn't match the expected `/f/{key}` shape — better to
 * skip than try to delete the wrong file.
 */
export function extractUploadThingKey(url: string | null | undefined): string | null {
  if (!url) return null;
  // Match the segment after `/f/` and before any trailing slash / query.
  const match = url.match(/\/f\/([^/?#]+)/);
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    return match[1];
  }
}

/**
 * Best-effort delete of one feed post's video + thumbnail from UploadThing.
 * Returns the number of keys actually submitted to the delete batch (0 if
 * neither URL parses) — useful for logging. Never throws.
 */
export async function deleteFeedAssets(params: {
  videoUrl?: string | null;
  thumbnailUrl?: string | null;
  context?: string;
}): Promise<number> {
  const keys = [
    extractUploadThingKey(params.videoUrl),
    extractUploadThingKey(params.thumbnailUrl),
  ].filter((k): k is string => Boolean(k));

  if (keys.length === 0) return 0;

  try {
    await utapi.deleteFiles(keys);
    return keys.length;
  } catch (err) {
    console.warn(
      `[feed-cleanup] deleteFiles failed${params.context ? ` (${params.context})` : ""}:`,
      err,
    );
    return 0;
  }
}
