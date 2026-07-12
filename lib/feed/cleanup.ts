/**
 * UploadThing asset cleanup for feed posts.
 *
 * Called when a customer post is rejected / hidden / hard-deleted so the
 * underlying video + thumbnail files don't pile up forever in UploadThing
 * storage. We don't store the file `key` separately — it's encoded as the
 * last segment of the ufsUrl (https://{appId}.ufs.sh/f/{key}), so we
 * extract it from the saved url string.
 *
 * Never-throw by design: a storage delete failure must never roll back
 * the moderation transition the admin just made. Callers should still
 * await it (or wrap in `after()`) — a `void`-ed promise can be frozen by
 * Vercel before it runs, leaving orphan assets that keep billing storage.
 */

import { utapi } from "@/lib/uploadthing";
import { deleteBunnyVideo } from "@/lib/feed/bunny";

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
  /** Bunny video GUID, when the post was uploaded through Bunny Stream. */
  videoGuid?: string | null;
  /**
   * Untuk PHOTO_CAROUSEL post — array of FeedMedia rows. Tiap row punya
   * URL (untuk extract key fallback) atau uploadthingKey langsung (preferred).
   */
  mediaItems?: Array<{ url?: string | null; uploadthingKey?: string | null }>;
  context?: string;
}): Promise<number> {
  // Bunny Stream — delete the whole video record (covers playlist + every
  // bitrate variant + auto thumbnails). This is the primary path for new
  // customer uploads going forward.
  // Di-await (bukan void) — Vercel bisa membekukan function sebelum
  // promise void jalan, meninggalkan orphan video yang terus menagih
  // storage. deleteBunnyVideo tidak pernah throw (return false on error).
  if (params.videoGuid) {
    await deleteBunnyVideo(params.videoGuid);
  }

  // UploadThing keys — collect dari semua source:
  //   1. videoUrl + thumbnailUrl (legacy single-video posts)
  //   2. mediaItems.uploadthingKey langsung (preferred, akurat)
  //   3. mediaItems.url fallback (extract key dari URL segment)
  const keys = [
    extractUploadThingKey(params.videoUrl),
    extractUploadThingKey(params.thumbnailUrl),
    ...(params.mediaItems ?? []).flatMap((m) => [
      m.uploadthingKey ?? null,
      // Hanya extract dari URL kalau uploadthingKey null — avoid double
      // delete request untuk key yang sama.
      m.uploadthingKey ? null : extractUploadThingKey(m.url),
    ]),
  ].filter((k): k is string => Boolean(k));

  if (keys.length === 0) return params.videoGuid ? 1 : 0;

  try {
    await utapi.deleteFiles(keys);
    return keys.length + (params.videoGuid ? 1 : 0);
  } catch (err) {
    console.warn(
      `[feed-cleanup] deleteFiles failed${params.context ? ` (${params.context})` : ""}:`,
      err,
    );
    return params.videoGuid ? 1 : 0;
  }
}
