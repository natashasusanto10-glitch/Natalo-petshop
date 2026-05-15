/**
 * GET /api/admin/feed/bunny-diag
 *
 * Read-only diagnostic endpoint. Returns enough state about the latest
 * feed posts to debug "why isn't my upload showing in the feed" without
 * requiring an admin session — useful when we (the developer) need to
 * inspect from a server-side curl. No PII / no full URLs / no internal
 * details that aren't already public via /api/feed/posts. Strip this
 * endpoint once the migration is stable.
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
  // Truncate sensitive-ish fields, return only what's needed for diagnosis.
  const summary = recent.map((p) => ({
    id: p.id,
    status: p.status,
    encodingStatus: p.encodingStatus,
    hasVideoGuid: Boolean(p.videoGuid),
    hasVideoUrl: Boolean(p.videoUrl),
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
