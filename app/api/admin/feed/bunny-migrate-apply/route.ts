/**
 * POST /api/admin/feed/bunny-migrate-apply
 *
 * Apply Bunny library migration mapping ke DB. Dipanggil oleh
 * scripts/migrate-bunny-to-sg.mjs dalam mode=api supaya tidak butuh
 * DATABASE_URL di local environment.
 *
 * Body:
 *   {
 *     mapping: [
 *       {
 *         postId: string,
 *         oldGuid: string,
 *         newGuid: string,
 *         newVideoUrl: string,
 *         newThumbnailUrl: string,
 *       },
 *       ...
 *     ]
 *   }
 *
 * Update FeedPost row: videoGuid, videoUrl, thumbnailUrl. Encoding status
 * dipertahankan "ready" — kita yakin video sudah finish di library SG
 * (script poll sampai status=4 sebelum kirim mapping).
 *
 * Idempotent: kalau row sudah punya newGuid sebagai videoGuid, skip.
 *
 * Admin-gated. Operasi destructive (rewrite videoUrl) butuh confirm via
 * `dryRun: true` first untuk lihat plan tanpa execute.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

type MappingItem = {
  postId: string;
  oldGuid: string;
  newGuid: string;
  newVideoUrl: string;
  newThumbnailUrl: string;
};

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    mapping?: MappingItem[];
    dryRun?: boolean;
  };
  const dryRun = Boolean(body.dryRun);
  const items = Array.isArray(body.mapping) ? body.mapping : [];
  if (items.length === 0) {
    return NextResponse.json({ error: "Empty mapping" }, { status: 400 });
  }
  if (items.length > 500) {
    return NextResponse.json(
      { error: "Mapping terlalu besar (max 500). Split jadi batch." },
      { status: 400 },
    );
  }

  // Validate shape
  for (const item of items) {
    if (
      !item.postId ||
      !item.oldGuid ||
      !item.newGuid ||
      !item.newVideoUrl ||
      !item.newThumbnailUrl
    ) {
      return NextResponse.json(
        { error: `Invalid item: ${JSON.stringify(item)}` },
        { status: 400 },
      );
    }
  }

  const results: Array<{
    postId: string;
    status: "applied" | "skipped" | "not-found" | "error";
    detail?: string;
  }> = [];

  for (const item of items) {
    try {
      const post = await prisma.feedPost.findUnique({
        where: { id: item.postId },
        select: { id: true, videoGuid: true },
      });
      if (!post) {
        results.push({ postId: item.postId, status: "not-found" });
        continue;
      }
      // Idempotent skip
      if (post.videoGuid === item.newGuid) {
        results.push({
          postId: item.postId,
          status: "skipped",
          detail: "already migrated",
        });
        continue;
      }
      // Defensive: kalau current videoGuid bukan oldGuid yang di-claim,
      // hindari overwrite — bisa indikasi stale mapping atau race.
      if (post.videoGuid !== item.oldGuid) {
        results.push({
          postId: item.postId,
          status: "error",
          detail: `Current guid ${post.videoGuid} != mapping oldGuid ${item.oldGuid}`,
        });
        continue;
      }
      if (dryRun) {
        results.push({
          postId: item.postId,
          status: "applied",
          detail: "dry-run, no write",
        });
        continue;
      }
      await prisma.feedPost.update({
        where: { id: item.postId },
        data: {
          videoGuid: item.newGuid,
          videoUrl: item.newVideoUrl,
          thumbnailUrl: item.newThumbnailUrl,
        },
      });
      results.push({ postId: item.postId, status: "applied" });
    } catch (err) {
      results.push({
        postId: item.postId,
        status: "error",
        detail: err instanceof Error ? err.message : String(err),
      });
    }
  }

  const summary = results.reduce(
    (acc, r) => {
      acc[r.status] = (acc[r.status] ?? 0) + 1;
      return acc;
    },
    {} as Record<string, number>,
  );

  return NextResponse.json({
    ok: true,
    dryRun,
    summary,
    results,
  });
}
