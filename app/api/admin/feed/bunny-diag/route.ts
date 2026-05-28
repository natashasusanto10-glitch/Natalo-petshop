/**
 * GET /api/admin/feed/bunny-diag
 *
 * Read-only diagnostic endpoint untuk debug "kenapa upload-ku tidak
 * muncul di feed". Return state 10 post feed terbaru.
 *
 * SECURITY: sekarang WAJIB admin session. Sebelumnya endpoint ini
 * sengaja unauthenticated ("untuk curl server-side") tapi itu bocorkan
 * internal feed lintas user — title, status, encodingStatus, bahkan
 * post PENDING_REVIEW / deleted yang belum public — ke siapa saja. Info
 * disclosure. Sekarang di-guard sama seperti admin endpoint lain.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
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
