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
  bunnyDisplayDimensions,
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
      authorId: true,
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
      // WAJIB await — void promise bisa dibekukan Vercel sebelum jalan
      // (lihat komentar panjang di bawah). Error ditelan internal.
      await sendFeedEncodingFailedNotification({
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
        // Rotation-corrected display dims — see bunnyDisplayDimensions.
        videoWidth: bunnyDisplayDimensions(meta).width,
        videoHeight: bunnyDisplayDimensions(meta).height,
        videoSizeBytes: meta.storageSize ?? null,
      },
    });
    // WAJIB await — alasan sama dengan publish-push di bawah.
    await sendFeedPendingReviewNotification({ postId: post.id });
    // Tag People VIDEO fix (final review Spec B) — notif tagged-user
    // dipindah ke SINI (ready-transition), BUKAN provision time. Lihat
    // notifyTaggedUsersOnVideoReady di lib/feed/activity-notifications.ts
    // untuk alasan lengkap (notif phantom kalau upload dibatalkan/encoding
    // gagal). WAJIB await — alasan sama dengan publish-push di bawah.
    const { notifyTaggedUsersOnVideoReady } = await import(
      "@/lib/feed/activity-notifications"
    );
    await notifyTaggedUsersOnVideoReady({
      postId: post.id,
      actorUserId: post.authorId,
    });
    // Publish-push — HARUS dipicu di sini juga, bukan cuma di webhook.
    // Bunny webhook feed sering miss FINISHED (lihat komentar bunny-reconcile),
    // jadi reconcile-lah yang biasanya menandai post "ready". Kalau trigger
    // hanya di webhook, "Beri tahu pelanggan" tak pernah jalan untuk post yang
    // di-ready via reconcile. Guard internal (admin/ACTIVE/notifyOnPublish/
    // klaim atomik) memutuskan kirim atau tidak — aman dipanggil ganda.
    // WAJIB di-await: Vercel serverless membekukan function begitu response
    // terkirim — promise yang di-void bisa tak pernah jalan (akar bug push
    // tak terkirim padahal broadcast manual — yang meng-await — selalu jalan).
    // Aman: sendFeedPublishPush menelan semua error internal.
    await import("@/lib/feed/publish-push").then(({ sendFeedPublishPush }) =>
      sendFeedPublishPush(post.id),
    );
    // Pre-warm CDN edge — same alasan dengan webhook path. SENGAJA tetap
    // void (satu-satunya pengecualian): boleh hilang kalau function keburu
    // dibekukan — dampaknya cuma user pertama kena cold-cache CDN, dan
    // meng-await fetch 256KB × N asset menahan response tanpa manfaat user.
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
    // WAJIB await — void promise bisa dibekukan Vercel (lihat atas).
    await sendFeedEncodingFailedNotification({
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
    // WAJIB await — void promise bisa dibekukan Vercel (lihat atas).
    await sendFeedEncodingFailedNotification({
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
