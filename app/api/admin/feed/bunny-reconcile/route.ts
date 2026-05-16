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
  bunnyMp4Url,
  bunnyThumbnailUrl,
  getBunnyVideo,
} from "@/lib/feed/bunny";
import { sendFeedPendingReviewNotification } from "@/lib/feed/notifications";

export const dynamic = "force-dynamic";

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
    /** Rewrite legacy Bunny HLS rows to point at the MP4 progressive URL. */
    migrateHlsToMp4?: boolean;
  };

  // One-shot: convert any existing posts whose videoUrl still points at
  // `playlist.m3u8` over to the MP4 URL. Run once after deploying the
  // MP4 switch so playback hits the much-better-cached MP4 path even for
  // rows written before the change.
  if (body.migrateHlsToMp4) {
    const oldRows = await prisma.feedPost.findMany({
      where: {
        videoGuid: { not: null },
        videoUrl: { endsWith: "playlist.m3u8" },
      },
      select: { id: true, videoGuid: true },
    });
    const migrated: string[] = [];
    for (const row of oldRows) {
      if (!row.videoGuid) continue;
      await prisma.feedPost.update({
        where: { id: row.id },
        data: {
          videoUrl: bunnyMp4Url(row.videoGuid, 720),
          videoMimeType: "video/mp4",
        },
      });
      migrated.push(row.id);
    }
    return NextResponse.json({ ok: true, mode: "migrate-hls-to-mp4", migrated });
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

  const posts = await prisma.feedPost.findMany({
    where: {
      ...(body.postId ? { id: body.postId } : {}),
      encodingStatus: "uploading",
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
          videoUrl: bunnyMp4Url(post.videoGuid, 720),
          thumbnailUrl: bunnyThumbnailUrl(post.videoGuid),
          videoMimeType: "video/mp4",
          videoDurationSec: meta.length ? Math.round(meta.length) : null,
          videoWidth: meta.width ?? null,
          videoHeight: meta.height ?? null,
          videoSizeBytes: meta.storageSize ?? null,
        },
      });
      void sendFeedPendingReviewNotification({ postId: post.id });
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
