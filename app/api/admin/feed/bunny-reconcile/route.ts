/**
 * POST /api/admin/feed/bunny-reconcile
 *
 * Manual reconciliation for FeedPost rows stuck at encodingStatus="uploading".
 * Polls Bunny Stream for each video's real status and finalizes the row when
 * Bunny reports FINISHED (or marks it failed when ERROR). Use this when the
 * webhook didn't fire (network blip, Bunny outage, misconfigured URL, etc).
 *
 * Body (optional):
 *   { postId?: string }   // reconcile just one post; otherwise scan all
 *
 * Returns:
 *   { ok: true, reconciled: [{postId, action: "ready"|"failed"|"skipped"}] }
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  BUNNY_VIDEO_STATUS,
  bunnyDisplayDimensions,
  bunnyPlaylistUrl,
  bunnyThumbnailUrl,
  getBunnyVideo,
} from "@/lib/feed/bunny";
import { sendFeedPendingReviewNotification } from "@/lib/feed/notifications";

export const dynamic = "force-dynamic";
// Fan-out publish-push kini di-await di handler — beri ruang seperti
// broadcast route (default 10s bisa kurang saat kirim ke banyak user).
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    postId?: string;
    debug?: boolean;
    /** DEPRECATED — kept for backward-compat. Use migrateMp4ToHls instead. */
    migrateHlsToMp4?: boolean;
    /**
     * Migrate existing posts dari `play_720p.mp4` URL → `playlist.m3u8` URL.
     * Run sekali setelah deploy switch HLS supaya post lama playable lagi
     * (MP4 720p sering 404 karena Bunny library tidak generate variant
     * specific itu; HLS playlist selalu ada).
     */
    migrateMp4ToHls?: boolean;
  };

  // One-shot migration: convert posts yang masih punya videoUrl
  // `play_720p.mp4` → `playlist.m3u8`. Trigger setelah deploy HLS switch.
  if (body.migrateMp4ToHls) {
    const oldRows = await prisma.feedPost.findMany({
      where: {
        videoGuid: { not: null },
        videoUrl: { endsWith: ".mp4" },
      },
      select: { id: true, videoGuid: true },
    });
    const migrated: string[] = [];
    for (const row of oldRows) {
      if (!row.videoGuid) continue;
      await prisma.feedPost.update({
        where: { id: row.id },
        data: {
          videoUrl: bunnyPlaylistUrl(row.videoGuid),
          videoMimeType: "application/vnd.apple.mpegurl",
        },
      });
      migrated.push(row.id);
    }
    return NextResponse.json({ ok: true, mode: "migrate-mp4-to-hls", migrated });
  }

  // Legacy mode — DEPRECATED. Original intent was migrate HLS → MP4, tapi
  // sekarang kita switch ke HLS lagi (per fix 404). Keep handler tapi noop
  // dengan info message supaya admin tidak bingung kalau ke-trigger.
  if (body.migrateHlsToMp4) {
    return NextResponse.json({
      ok: false,
      mode: "deprecated",
      message:
        "migrateHlsToMp4 DEPRECATED — sekarang pakai HLS playlist. Gunakan migrateMp4ToHls untuk forward migration.",
    });
  }

  // Debug mode: dump last 5 feed posts with their key state — no mutation.
  // Use this to see why a recently uploaded post isn't showing in the feed.
  if (body.debug) {
    const recent = await prisma.feedPost.findMany({
      orderBy: { createdAt: "desc" },
      take: 5,
      select: {
        id: true,
        status: true,
        encodingStatus: true,
        videoGuid: true,
        videoUrl: true,
        thumbnailUrl: true,
        tab: true,
        kind: true,
        createdAt: true,
        publishedAt: true,
        moderatedAt: true,
        deletedAt: true,
        title: true,
      },
    });
    // Also try to get Bunny status for the most recent one with a guid.
    const firstWithGuid = recent.find((p) => p.videoGuid);
    const bunnyMeta = firstWithGuid?.videoGuid
      ? await getBunnyVideo(firstWithGuid.videoGuid)
      : null;
    return NextResponse.json({
      ok: true,
      mode: "debug",
      recent,
      bunnyMetaForFirst: bunnyMeta,
    });
  }

  // Scan SEMUA state non-terminal — bukan cuma "uploading". Banyak post
  // nyangkut di "processing" karena Bunny webhook miss callback FINISHED;
  // kalau cuma scan "uploading", post-post itu tetap invisible.
  const posts = await prisma.feedPost.findMany({
    where: {
      ...(body.postId ? { id: body.postId } : {}),
      encodingStatus: { in: ["uploading", "processing"] },
      videoGuid: { not: null },
    },
    select: { id: true, videoGuid: true },
    take: 50,
  });

  const results: Array<{ postId: string; action: string; detail?: string }> = [];

  for (const post of posts) {
    if (!post.videoGuid) continue;
    const meta = await getBunnyVideo(post.videoGuid);
    if (!meta) {
      results.push({ postId: post.id, action: "skipped", detail: "Bunny returned null (transient or 404)" });
      continue;
    }
    if (meta.status === BUNNY_VIDEO_STATUS.FINISHED) {
      await prisma.feedPost.update({
        where: { id: post.id },
        data: {
          encodingStatus: "ready",
          // HLS playlist (consistent dengan webhook + reconcile.ts).
          videoUrl: bunnyPlaylistUrl(post.videoGuid),
          thumbnailUrl: bunnyThumbnailUrl(post.videoGuid),
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
      // Publish-push — samakan dengan webhook + reconcile.ts. Guard internal
      // (admin/ACTIVE/notifyOnPublish/klaim atomik) yang memutuskan.
      // WAJIB await — void promise bisa dibekukan Vercel sebelum jalan
      // (lihat komentar di lib/feed/reconcile.ts). Error ditelan internal.
      await import("@/lib/feed/publish-push").then(({ sendFeedPublishPush }) =>
        sendFeedPublishPush(post.id),
      );
      results.push({ postId: post.id, action: "ready" });
    } else if (meta.status === BUNNY_VIDEO_STATUS.ERROR) {
      await prisma.feedPost.update({
        where: { id: post.id },
        data: { encodingStatus: "failed" },
      });
      results.push({ postId: post.id, action: "failed" });
    } else {
      results.push({
        postId: post.id,
        action: "skipped",
        detail: `Bunny status=${meta.status} (still processing)`,
      });
    }
  }

  return NextResponse.json({ ok: true, scanned: posts.length, results });
}
