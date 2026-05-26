/**
 * Reconcile a feed post against Bunny Stream when our webhook may have
 * missed the FINISHED/ERROR transition. Idempotent: post yang sudah
 * `ready` / `failed` di-skip; yang masih `uploading` / `processing`
 * di-polling ulang dari Bunny dan di-update kalau Bunny bilang FINISHED.
 *
 * Dipakai oleh:
 *   - GET /api/feed/diag?force=1 (manual batch reconcile)
 *   - GET /api/cron/feed-reconcile-videos (cron 10-menit auto reconcile)
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
import {
  sendFeedEncodingFailedNotification,
  sendFeedPendingReviewNotification,
} from "./notifications";

export type ReconcileResult =
  | { action: "ready"; postId: string }
  | { action: "failed"; postId: string; reason: string }
  | { action: "skipped"; postId: string; detail: string };

/**
 * Threshold timeout untuk auto-fail post yang stuck terlalu lama. Saat
 * post sudah lebih lama dari `failAfterStuckMinutes` di state encoding
 * non-terminal, kita stop tunggu dan mark FAILED (kemungkinan besar
 * Bunny asset hilang / upload partial / webhook permanently dropped).
 *
 * Tanpa threshold ini, post bisa stuck PROCESSING indefinitely → user
 * confused, gak tau harus upload ulang atau menunggu.
 */
const DEFAULT_FAIL_AFTER_STUCK_MINUTES = 60;

/**
 * Reconcile satu post by ID. Return apa yang terjadi supaya caller bisa
 * log/expose ke user. Aman dipanggil meski post sudah ready (cuma return
 * skipped).
 *
 * Options:
 *   - failAfterStuckMinutes: kalau post stuck encoding > X menit AND
 *     Bunny menolak (null / status error / still processing), mark FAILED
 *     + notify user. Default 60 menit.
 */
export async function reconcileFeedPost(
  postId: string,
  options: { failAfterStuckMinutes?: number } = {},
): Promise<ReconcileResult> {
  const failAfterStuckMinutes =
    options.failAfterStuckMinutes ?? DEFAULT_FAIL_AFTER_STUCK_MINUTES;

  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: {
      id: true,
      encodingStatus: true,
      videoGuid: true,
      createdAt: true,
    },
  });
  if (!post) return { action: "skipped", postId, detail: "post-not-found" };
  if (post.encodingStatus === "ready" || post.encodingStatus === "failed") {
    return { action: "skipped", postId, detail: "already-settled" };
  }
  if (!post.videoGuid) {
    return { action: "skipped", postId, detail: "no-videoGuid" };
  }

  const stuckMinutes =
    (Date.now() - post.createdAt.getTime()) / (1000 * 60);
  const isStuckTooLong = stuckMinutes >= failAfterStuckMinutes;

  const meta = await getBunnyVideo(post.videoGuid);

  // Case 1: Bunny tidak punya record video ini (kemungkinan upload partial
  // yang gak pernah complete, atau Bunny GC hapus duluan). Setelah threshold,
  // mark FAILED supaya user tau perlu upload ulang.
  if (!meta) {
    if (isStuckTooLong) {
      await prisma.feedPost.update({
        where: { id: post.id },
        data: {
          encodingStatus: "failed",
          moderationNote: `Video gagal di-upload ke Bunny (tidak ditemukan setelah ${Math.round(stuckMinutes)} menit).`,
        },
      });
      void sendFeedEncodingFailedNotification({
        postId: post.id,
        reason: "Upload tidak selesai",
      });
      return {
        action: "failed",
        postId,
        reason: "bunny-null-after-timeout",
      };
    }
    return { action: "skipped", postId, detail: "bunny-null-waiting" };
  }

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
      data: {
        encodingStatus: "failed",
        moderationNote: "Encoding error di Bunny Stream.",
      },
    });
    void sendFeedEncodingFailedNotification({
      postId: post.id,
      reason: "Encoding error",
    });
    return { action: "failed", postId, reason: "bunny-error-status" };
  }

  // Case 2: Bunny masih PROCESSING. Kalau sudah lewat threshold, treat
  // sebagai "stuck encoding" — Bunny biasanya selesai 1-5 menit untuk video
  // pendek, 10-15 menit untuk video panjang. Lebih dari 60 menit = abnormal.
  if (isStuckTooLong) {
    await prisma.feedPost.update({
      where: { id: post.id },
      data: {
        encodingStatus: "failed",
        moderationNote: `Encoding stuck di Bunny lebih dari ${Math.round(stuckMinutes)} menit (status ${meta.status}).`,
      },
    });
    void sendFeedEncodingFailedNotification({
      postId: post.id,
      reason: "Encoding timeout",
    });
    return {
      action: "failed",
      postId,
      reason: `bunny-stuck-${meta.status}-after-${Math.round(stuckMinutes)}min`,
    };
  }

  return {
    action: "skipped",
    postId,
    detail: `bunny-status-${meta.status}-waiting`,
  };
}
