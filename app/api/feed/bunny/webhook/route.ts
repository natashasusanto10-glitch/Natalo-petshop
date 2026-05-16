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
  bunnyMp4Url,
  bunnyThumbnailUrl,
  getBunnyConfig,
  getBunnyVideo,
} from "@/lib/feed/bunny";
import { sendFeedPendingReviewNotification } from "@/lib/feed/notifications";
import { USER_VIDEO_CONFIG } from "@/lib/feed/video-config";

export const dynamic = "force-dynamic";

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
    select: { id: true, encodingStatus: true },
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
  if (
    meta?.length &&
    (meta.length < USER_VIDEO_CONFIG.minDuration ||
      meta.length > USER_VIDEO_CONFIG.maxDuration)
  ) {
    await prisma.feedPost.update({
      where: { id: post.id },
      data: {
        encodingStatus: "failed",
        moderationNote: `Durasi video harus ${USER_VIDEO_CONFIG.minDuration}–${USER_VIDEO_CONFIG.maxDuration} detik.`,
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
  await prisma.feedPost.update({
    where: { id: post.id },
    data: {
      encodingStatus: "ready",
      videoUrl: bunnyMp4Url(guid, 720),
      thumbnailUrl: bunnyThumbnailUrl(guid),
      videoMimeType: "video/mp4",
      videoDurationSec: meta?.length ? Math.round(meta.length) : null,
      videoWidth: meta?.width ?? null,
      videoHeight: meta?.height ?? null,
      videoSizeBytes: meta?.storageSize ?? null,
    },
  });
  void sendFeedPendingReviewNotification({ postId: post.id });

  return NextResponse.json({ ok: true, encoded: "ready" });
}
