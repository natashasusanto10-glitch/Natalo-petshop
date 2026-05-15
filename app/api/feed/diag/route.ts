/**
 * GET /api/feed/diag
 *
 * Read-only diagnostic. Returns the last 10 FeedPost rows with their
 * moderation + encoding state, stripped of any sensitive fields, so a
 * developer can curl prod directly to debug "upload didn't show in feed"
 * issues without a logged-in admin session. Remove after migration ships.
 */
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET() {
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
  return NextResponse.json({ ok: true, count: summary.length, recent: summary });
}
