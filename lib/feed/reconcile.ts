/**
 * Reconcile a feed post against Bunny Stream when our webhook may have
 * missed the FINISHED/ERROR transition. Idempotent: post yang sudah
 * `ready` / `failed` di-skip; yang masih `uploading` / `processing`
 * di-polling ulang dari Bunny dan di-update kalau Bunny bilang FINISHED.
 *
 * Dipakai oleh:
 *   - GET /api/feed/diag?force=1 (batch reconcile semua stuck)
 *   - PATCH /api/admin/feed/posts/[id] action=approve (auto-reconcile post
 *     yang baru disetujui supaya admin tidak perlu manual trigger reconcile)
 */
import { prisma } from "@/lib/prisma";
import {
  BUNNY_VIDEO_STATUS,
  bunnyPlaylistUrl,
  bunnyThumbnailUrl,
  getBunnyVideo,
  preWarmBunnyAssets,
} from "./bunny";
import { generateBlurhashFromUrl } from "./blurhash";
import { sendFeedPendingReviewNotification } from "./notifications";

export type ReconcileResult =
  | { action: "ready"; postId: string }
  | { action: "failed"; postId: string }
  | { action: "skipped"; postId: string; detail: string };

/**
 * Reconcile satu post by ID. Return apa yang terjadi supaya caller bisa
 * log/expose ke user. Aman dipanggil meski post sudah ready (cuma return
 * skipped).
 */
export async function reconcileFeedPost(
  postId: string,
): Promise<ReconcileResult> {
  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: {
      id: true,
      encodingStatus: true,
      videoGuid: true,
    },
  });
  if (!post) return { action: "skipped", postId, detail: "post-not-found" };
  if (post.encodingStatus === "ready" || post.encodingStatus === "failed") {
    return { action: "skipped", postId, detail: "already-settled" };
  }
  if (!post.videoGuid) {
    return { action: "skipped", postId, detail: "no-videoGuid" };
  }

  const meta = await getBunnyVideo(post.videoGuid);
  if (!meta) return { action: "skipped", postId, detail: "bunny-null" };

  if (meta.status === BUNNY_VIDEO_STATUS.FINISHED) {
    const thumbnailUrl = bunnyThumbnailUrl(post.videoGuid);
    // Best-effort blurhash — sama dengan webhook path supaya post yang
    // ke-reconcile manual (bukan via webhook) tetap dapat LQIP.
    const blurhash = await generateBlurhashFromUrl(thumbnailUrl);
    await prisma.feedPost.update({
      where: { id: post.id },
      data: {
        encodingStatus: "ready",
        // HLS playlist — match webhook handler. Selalu ada saat video
        // ready, tidak depend on "MP4 Fallback 720p" library config.
        videoUrl: bunnyPlaylistUrl(post.videoGuid),
        thumbnailUrl,
        thumbnailBlurhash: blurhash,
        videoMimeType: "application/vnd.apple.mpegurl",
        videoDurationSec: meta.length ? Math.round(meta.length) : null,
        videoWidth: meta.width ?? null,
        videoHeight: meta.height ?? null,
        videoSizeBytes: meta.storageSize ?? null,
      },
    });
    void sendFeedPendingReviewNotification({ postId: post.id });
    // Pre-warm CDN edge — same alasan dengan webhook path.
    void preWarmBunnyAssets(post.videoGuid);
    return { action: "ready", postId };
  }

  if (meta.status === BUNNY_VIDEO_STATUS.ERROR) {
    await prisma.feedPost.update({
      where: { id: post.id },
      data: { encodingStatus: "failed" },
    });
    return { action: "failed", postId };
  }

  return {
    action: "skipped",
    postId,
    detail: `bunny-status-${meta.status}`,
  };
}
