/**
 * POST /api/admin/feed/blurhash-backfill
 *
 * Backfill thumbnailBlurhash untuk post existing yang sudah ACTIVE +
 * punya thumbnailUrl tapi belum punya blurhash. Idempotent — skip post
 * yang sudah ada blurhash. Process batch (?limit=N, default 20) untuk
 * hindari Vercel timeout 60s.
 *
 * Admin only — tidak boleh callable dari user session.
 *
 * Response:
 *   { ok: true, processed: N, blurhashed: M, errors: K }
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { generateBlurhashFromUrl } from "@/lib/feed/blurhash";

export const dynamic = "force-dynamic";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const rawLimit = Number(searchParams.get("limit"));
  const limit = Math.min(
    MAX_LIMIT,
    Number.isFinite(rawLimit) && rawLimit > 0 ? rawLimit : DEFAULT_LIMIT,
  );

  // Cari post yang masih butuh backfill — thumbnailUrl ada, blurhash NULL,
  // post visible (deletedAt=null + encodingStatus=ready). Urut by created
  // desc supaya yang baru di-prioritas (lebih sering di-view).
  const candidates = await prisma.feedPost.findMany({
    where: {
      thumbnailUrl: { not: null },
      thumbnailBlurhash: null,
      deletedAt: null,
      encodingStatus: "ready",
    },
    orderBy: { createdAt: "desc" },
    take: limit,
    select: { id: true, thumbnailUrl: true },
  });

  let blurhashed = 0;
  let errors = 0;

  for (const post of candidates) {
    if (!post.thumbnailUrl) continue;
    const hash = await generateBlurhashFromUrl(post.thumbnailUrl);
    if (hash) {
      try {
        await prisma.feedPost.update({
          where: { id: post.id },
          data: { thumbnailBlurhash: hash },
        });
        blurhashed += 1;
      } catch {
        errors += 1;
      }
    } else {
      errors += 1;
    }
  }

  return NextResponse.json({
    ok: true,
    processed: candidates.length,
    blurhashed,
    errors,
    hint:
      candidates.length === limit
        ? "Masih ada post yang belum di-backfill. Run lagi untuk lanjutkan."
        : "Backfill selesai untuk batch ini.",
  });
}
