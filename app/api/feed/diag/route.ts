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
 *
 * GET /api/feed/diag?gc=1 — dry-run Bunny orphan sweep. Returns count
 * + bytes of orphan videos di Bunny library (yang tidak referenced oleh
 * non-deleted FeedPost). Tidak delete apa-apa.
 *
 * GET /api/feed/diag?gc=1&force=1 — execute Bunny orphan sweep. Delete
 * orphan Bunny videos. Idempotent. Cron-based sweep di
 * /api/cron/feed-storage-gc juga jalan setiap minggu otomatis.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { bunnyPlaylistUrl } from "@/lib/feed/bunny";
import { sweepBunnyOrphans, type BunnyGcResult } from "@/lib/feed/bunny-gc";
import { reconcileFeedPost } from "@/lib/feed/reconcile";

export const dynamic = "force-dynamic";

/**
 * GET /api/feed/diag?notifsFor=<userId>&limit=10
 *   Returns the latest feed-related Announcement rows targeted at that
 *   user — lets the developer see whether moderation/like/comment
 *   notifications actually got created (and if so, when). When the row
 *   is present but push didn't show on the phone, the issue is delivery;
 *   when the row is missing, the issue is the server-side trigger logic.
 */
export async function GET(request: NextRequest) {
  const notifsFor = request.nextUrl.searchParams.get("notifsFor");
  if (notifsFor) {
    const rows = await prisma.announcement.findMany({
      where: {
        targetUserId: notifsFor,
        source: "feed",
      },
      orderBy: { createdAt: "desc" },
      take: 20,
      select: {
        id: true,
        eventType: true,
        title: true,
        body: true,
        feedPostId: true,
        feedStatus: true,
        createdAt: true,
      },
    });
    return NextResponse.json({ ok: true, userId: notifsFor, count: rows.length, notifs: rows });
  }

  const force = request.nextUrl.searchParams.get("force") === "1";
  // ?gc=1 → run Bunny orphan sweep. Default dry-run kalau tidak ?force=1
  // supaya bisa cek hasil dulu sebelum execute delete.
  const gc = request.nextUrl.searchParams.get("gc") === "1";
  const actions: Array<{ postId: string; action: string; detail?: string }> = [];
  let bunnyGc: BunnyGcResult | null = null;

  if (gc) {
    // Kalau ?force=1 juga ada, delete benar-benar dilakukan.
    // Kalau cuma ?gc=1, dry-run report orphan count + bytes tanpa delete.
    bunnyGc = await sweepBunnyOrphans({ dryRun: !force });
  }

  if (force) {
    // 1. Reconcile semua post stuck di encodingStatus uploading/processing.
    // Pakai reconcileFeedPost() helper (lib/feed/reconcile.ts) — same
    // logic dengan cron /api/cron/feed-reconcile-videos. Auto-fail kalau
    // stuck > 60 menit. Sebelumnya hanya scan "uploading" (miss yang
    // sudah ke-update ke "processing" tapi webhook lost).
    const stuck = await prisma.feedPost.findMany({
      where: {
        encodingStatus: { in: ["uploading", "processing"] },
        videoGuid: { not: null },
        deletedAt: null,
      },
      select: { id: true },
      take: 50,
    });
    for (const post of stuck) {
      const result = await reconcileFeedPost(post.id, {
        failAfterStuckMinutes: 60,
      });
      actions.push({
        postId: result.postId,
        action: result.action,
        detail:
          result.action === "skipped"
            ? result.detail
            : result.action === "failed"
              ? result.reason
              : undefined,
      });
    }

    // 2. Migrate any existing MP4 rows ke HLS playlist (forward
    // migration setelah switch ke HLS — MP4 720p sering 404 karena
    // Bunny library tidak generate variant itu).
    const mp4Rows = await prisma.feedPost.findMany({
      where: {
        videoGuid: { not: null },
        videoUrl: { endsWith: ".mp4" },
      },
      select: { id: true, videoGuid: true },
    });
    for (const row of mp4Rows) {
      if (!row.videoGuid) continue;
      await prisma.feedPost.update({
        where: { id: row.id },
        data: {
          videoUrl: bunnyPlaylistUrl(row.videoGuid),
          videoMimeType: "application/vnd.apple.mpegurl",
        },
      });
      actions.push({ postId: row.id, action: "migrated-to-hls" });
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
  return NextResponse.json({
    ok: true,
    count: summary.length,
    actions,
    recent: summary,
    bunnyGc, // null kalau ?gc bukan ?gc=1; result kalau di-trigger.
  });
}
