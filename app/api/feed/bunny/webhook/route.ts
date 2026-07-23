/**
 * POST /api/feed/bunny/webhook
 *
 * Bunny Stream calls this when a video transitions between encoding
 * states. Non-terminal callbacks mark the row as processing so the user
 * can leave the creator flow while Bunny handles compression/transcoding:
 *
 *   Status 4 (FINISHED) → revalidate duration, set encodingStatus=ready,
 *                         fill videoUrl + thumbnailUrl, surface in feed.
 *   Status 5 (ERROR)    → set encodingStatus=failed. Post never appears
 *                         in the public feed. Customer gets a "video gagal
 *                         diproses" notification via the existing
 *                         feed-moderation notification helper.
 *
 * Webhook body shape (Bunny standard payload):
 *   {
 *     "VideoLibraryId": 12345,
 *     "VideoGuid": "abcd-efgh-...",
 *     "Status": 4
 *   }
 *
 * Optional auth: if BUNNY_WEBHOOK_SECRET is set, Bunny appends an
 * `Authorization: Bearer <secret>` header. We verify before mutating
 * the DB so a random POST from the internet can't flip our posts.
 */

import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  BUNNY_VIDEO_STATUS,
  bunnyDisplayDimensions,
  bunnyPlaylistUrl,
  bunnyThumbnailUrl,
  getBunnyConfig,
  getBunnyVideo,
  preWarmBunnyAssets,
} from "@/lib/feed/bunny";
import { sendFeedPendingReviewNotification } from "@/lib/feed/notifications";
import { ADMIN_VIDEO_CONFIG, USER_VIDEO_CONFIG } from "@/lib/feed/video-config";
import { generateBlurhashFromUrl } from "@/lib/feed/blurhash";

export const dynamic = "force-dynamic";
// Fan-out publish-push kini di-await di handler — beri ruang seperti
// broadcast route (default 10s bisa kurang saat kirim ke banyak user).
export const maxDuration = 60;

type WebhookPayload = {
  VideoLibraryId?: number;
  VideoGuid?: string;
  Status?: number;
};

function isAuthorized(request: NextRequest): boolean {
  const cfg = getBunnyConfig();
  // If no webhook secret configured, accept anything (still safe-ish — we
  // only flip rows whose videoGuid matches one we created ourselves, and
  // worst case is a noop on a guid that doesn't exist).
  if (!cfg?.webhookSecret) return true;
  const auth = request.headers.get("authorization") ?? "";
  return auth === `Bearer ${cfg.webhookSecret}`;
}

/**
 * Bunny dashboard validates the webhook URL by probing it with GET before
 * letting the admin save. Without this handler the probe gets a 405 and
 * Bunny rejects the URL as "invalid". Return a tiny 200 so the validator
 * passes; real webhook traffic comes in as POST.
 */
export async function GET() {
  return NextResponse.json({ ok: true, hint: "POST only — this URL receives Bunny Stream callbacks." });
}

export async function POST(request: NextRequest) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }

  const payload = (await request.json().catch(() => null)) as WebhookPayload | null;
  const guid = payload?.VideoGuid;
  const status = payload?.Status;
  if (!guid || typeof status !== "number") {
    return NextResponse.json({ ok: false, error: "Invalid payload" }, { status: 400 });
  }

  const post = await prisma.feedPost.findUnique({
    where: { videoGuid: guid },
    // authorRole dipakai untuk pilih duration limit yang benar. Bug
    // sebelumnya: webhook pakai USER_VIDEO_CONFIG untuk semua post, jadi
    // saat limit admin berbeda video bisa salah di-mark "failed".
    select: {
      id: true,
      encodingStatus: true,
      authorRole: true,
      status: true,
      authorId: true,
    },
  });
  if (!post) {
    return NextResponse.json({ ok: true, skipped: "unknown-guid" });
  }
  if (post.encodingStatus === "ready" || post.encodingStatus === "failed") {
    // Already settled — webhook retry, ignore.
    return NextResponse.json({ ok: true, skipped: "already-settled" });
  }

  if (status !== BUNNY_VIDEO_STATUS.FINISHED && status !== BUNNY_VIDEO_STATUS.ERROR) {
    if (post.encodingStatus !== "processing") {
      await prisma.feedPost.update({
        where: { id: post.id },
        data: { encodingStatus: "processing" },
      });
    }
    return NextResponse.json({ ok: true, encoded: "processing" });
  }

  if (status === BUNNY_VIDEO_STATUS.ERROR) {
    await prisma.feedPost.update({
      where: { id: post.id },
      data: { encodingStatus: "failed" },
    });
    return NextResponse.json({ ok: true, encoded: "failed" });
  }

  // FINISHED — pull real dimensions + duration from Bunny so the feed
  // knows the aspect ratio before the first frame loads.
  const meta = await getBunnyVideo(guid);
  // Pilih duration config sesuai role author. Sebelumnya hard-coded ke
  // USER_VIDEO_CONFIG, jadi perubahan limit role tertentu bisa membuat
  // webhook salah menolak video yang sudah valid di frontend.
  const durationCfg =
    post.authorRole === "ADMIN" ? ADMIN_VIDEO_CONFIG : USER_VIDEO_CONFIG;
  if (
    meta?.length &&
    (meta.length < durationCfg.minDuration ||
      meta.length > durationCfg.maxDuration)
  ) {
    await prisma.feedPost.update({
      where: { id: post.id },
      data: {
        encodingStatus: "failed",
        moderationNote: `Durasi video harus ${durationCfg.minDuration}–${durationCfg.maxDuration} detik.`,
      },
    });
    return NextResponse.json({
      ok: true,
      encoded: "failed",
      reason: "invalid-duration",
    });
  }

  // Use the MP4 progressive URL instead of HLS playlist. Short feed clips
  // play and CDN-cache much better as a single MP4 than as a manifest +
  // dozens of HLS segments. iOS Safari plays it natively with no extra
  // player code. We default to 720p — sharp on portrait phone, ~5-10 MB.
  const thumbnailUrl = bunnyThumbnailUrl(guid);

  // Generate blurhash LQIP — fetch thumbnail + encode ke string ~30 byte.
  // Best-effort; kalau gagal (network glitch, sharp error), tetap commit
  // post tanpa blurhash. UI fallback ke bg-black. Awaited supaya 1 round-
  // trip ke DB cukup, tapi sudah ada timeout di fetchnya supaya webhook
  // tidak ngegantung indefinite.
  const blurhash = await generateBlurhashFromUrl(thumbnailUrl);

  const displayDims = bunnyDisplayDimensions(meta);

  await prisma.feedPost.update({
    where: { id: post.id },
    data: {
      encodingStatus: "ready",
      // HLS playlist URL instead of direct MP4 — selalu ada saat
      // encoding selesai, tidak depend on "MP4 Fallback resolutions"
      // config di library. Adaptive bitrate juga, otomatis pilih
      // quality based on user network. Bunny library Singapore default
      // tidak generate 720p MP4 (cuma 240/360/480) → playback 404.
      // Switch ke HLS = always works.
      videoUrl: bunnyPlaylistUrl(guid),
      thumbnailUrl,
      thumbnailBlurhash: blurhash,
      videoMimeType: "application/vnd.apple.mpegurl",
      videoDurationSec: meta?.length ? Math.round(meta.length) : null,
      // Display-oriented dims (rotation-corrected) so a portrait clip stored
      // as landscape pixels + rotation flag frames correctly in the feed.
      videoWidth: displayDims.width,
      videoHeight: displayDims.height,
      videoSizeBytes: meta?.storageSize ?? null,
    },
  });
  // WAJIB await — alasan sama dengan publish-push di bawah. No-op kalau post
  // sudah ACTIVE (helper early-return kalau status != PENDING_REVIEW), jadi
  // aman dipanggil untuk video customer yang kini auto-approve.
  await sendFeedPendingReviewNotification({ postId: post.id });

  // Tag People VIDEO fix (final review Spec B) — notif tagged-user dipindah
  // ke SINI (ready-transition), BUKAN provision time
  // (app/api/feed/bunny/upload-url/route.ts tidak lagi kirim notif ini).
  // Lihat notifyTaggedUsersOnVideoReady di lib/feed/activity-notifications.ts
  // untuk alasan lengkap (notif phantom kalau upload dibatalkan/encoding
  // gagal sebelum video pernah tayang). WAJIB await — alasan sama dgn
  // publish-push di bawah.
  const { notifyTaggedUsersOnVideoReady } = await import(
    "@/lib/feed/activity-notifications"
  );
  await notifyTaggedUsersOnVideoReady({
    postId: post.id,
    actorUserId: post.authorId,
  });

  // Video customer auto-approve (ACTIVE sejak create, tapi baru visible saat
  // ready sekarang) → beri tahu follower author. Analog dengan foto/carousel
  // yang fire sendNewPostToFollowersNotification saat create (di route posts).
  // Untuk video, momen "mulai tayang" adalah ready ini, bukan create. Admin
  // di-skip oleh helper-nya sendiri. WAJIB await — void bisa dibekukan Vercel.
  if (post.authorRole === "CUSTOMER" && post.status === "ACTIVE") {
    const { sendNewPostToFollowersNotification } = await import(
      "@/lib/social/notifications"
    );
    await sendNewPostToFollowersNotification(post.id);
  }
  // Publish-push — guard internal memutuskan (admin post yang tadi masih
  // `uploading` sekarang `ready`; kalau notifyOnPublish=true, kirim di sini).
  // WAJIB await — void promise bisa dibekukan Vercel sebelum jalan
  // (lihat komentar di lib/feed/reconcile.ts). Error ditelan internal.
  await import("@/lib/feed/publish-push").then(({ sendFeedPublishPush }) =>
    sendFeedPublishPush(post.id),
  );
  // Fire-and-forget CDN edge pre-warm — fetch first 256KB MP4 + thumbnail
  // dari server supaya edge POP terdekat sudah cache file sebelum user
  // pertama buka. Tanpa ini, user pertama selalu kena cold-cache latency
  // 2-5 detik (TTFB lambat). Lihat preWarmBunnyAssets() di lib/feed/bunny.ts.
  // SENGAJA tetap void (pengecualian dari aturan await): boleh hilang kalau
  // function keburu dibekukan — dampak cuma cold-cache untuk user pertama.
  void preWarmBunnyAssets(guid);

  return NextResponse.json({ ok: true, encoded: "ready" });
}
