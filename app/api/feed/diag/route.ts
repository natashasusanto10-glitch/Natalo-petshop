/**
 * GET /api/feed/diag
 *
 * Read-only diagnostic. Returns the last 10 FeedPost rows with their
 * moderation + encoding state, stripped of any sensitive fields, so a
 * developer can curl prod directly to debug "upload didn't show in feed"
 * issues without a logged-in admin session.
 *
 * GET /api/feed/diag?force=1 — also runs reconcile (poll Bunny for any
 * posts still in encodingStatus="uploading" and finalize them) and
 * migrate (rewrite legacy HLS rows to MP4). Idempotent. Remove this
 * route once the migration is stable.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  BUNNY_VIDEO_STATUS,
  bunnyMp4Url,
  bunnyThumbnailUrl,
  getBunnyVideo,
} from "@/lib/feed/bunny";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const force = request.nextUrl.searchParams.get("force") === "1";
  const actions: Array<{ postId: string; action: string; detail?: string }> = [];

  if (force) {
    // 1. Reconcile any posts still stuck in encodingStatus=uploading.
    const stuck = await prisma.feedPost.findMany({
      where: { encodingStatus: "uploading", videoGuid: { not: null } },
      select: { id: true, videoGuid: true },
      take: 50,
    });
    for (const post of stuck) {
      if (!post.videoGuid) continue;
      const meta = await getBunnyVideo(post.videoGuid);
      if (!meta) {
        actions.push({ postId: post.id, action: "skipped", detail: "Bunny null" });
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
        actions.push({ postId: post.id, action: "ready" });
      } else if (meta.status === BUNNY_VIDEO_STATUS.ERROR) {
        await prisma.feedPost.update({
          where: { id: post.id },
          data: { encodingStatus: "failed" },
        });
        actions.push({ postId: post.id, action: "failed" });
      } else {
        actions.push({
          postId: post.id,
          action: "skipped",
          detail: `Bunny status=${meta.status}`,
        });
      }
    }

    // 2. Migrate any HLS Bunny rows to MP4 progressive.
    const hls = await prisma.feedPost.findMany({
      where: {
        videoGuid: { not: null },
        videoUrl: { endsWith: "playlist.m3u8" },
      },
      select: { id: true, videoGuid: true },
    });
    for (const row of hls) {
      if (!row.videoGuid) continue;
      await prisma.feedPost.update({
        where: { id: row.id },
        data: {
          videoUrl: bunnyMp4Url(row.videoGuid, 720),
          videoMimeType: "video/mp4",
        },
      });
      actions.push({ postId: row.id, action: "migrated-to-mp4" });
    }
  }


  const recent = await prisma.feedPost.findMany({
    orderBy: { createdAt: "desc" },
    take: 10,
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
      authorRole: true,
    },
  });
  const summary = recent.map((p) => ({
    id: p.id,
    status: p.status,
    encodingStatus: p.encodingStatus,
    hasVideoGuid: Boolean(p.videoGuid),
    videoGuidSuffix: p.videoGuid?.slice(-8) ?? null,
    videoUrlKind: p.videoUrl?.endsWith(".m3u8")
      ? "hls"
      : p.videoUrl?.endsWith(".mp4")
        ? "mp4"
        : p.videoUrl
          ? "other"
          : null,
    hasThumb: Boolean(p.thumbnailUrl),
    tab: p.tab,
    kind: p.kind,
    role: p.authorRole,
    createdAt: p.createdAt,
    publishedAt: p.publishedAt,
    moderatedAt: p.moderatedAt,
    deletedAt: p.deletedAt,
    title: p.title,
  }));
  return NextResponse.json({ ok: true, count: summary.length, actions, recent: summary });
}
