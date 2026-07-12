/**
 * POST /api/admin/feed/push-debug  (admin-only, CSRF)
 *
 * Alat diagnosa sementara: untuk post notify terakhir yang publishPushSentAt
 * terisi TAPI Announcement lonceng-nya tak ada, coba jalankan ULANG
 * `announcement.create` + `resolveSegmentUserIds` + satu percobaan kirim,
 * lalu KEMBALIKAN error asli (yang di production ditelan `console.warn` di
 * sendFeedPublishPush). Kalau announcement.create ternyata berhasil, entri
 * lonceng yang hilang jadi terbuat (bonus perbaikan retroaktif).
 *
 * GET (bisa dibuka langsung di browser saat login admin, biar mudah
 * di-screenshot seperti push-info). Query opsional: ?postId=... — kalau
 * kosong, ambil post notify terakhir yang punya publishPushSentAt.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { buildFeedPushPayload } from "@/lib/feed/publish-push-payload";
import {
  resolveSegmentUserIds,
  type PushSegment,
} from "@/lib/feed/publish-push";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function errInfo(err: unknown) {
  if (err instanceof Error) {
    return {
      name: err.name,
      message: err.message,
      // Prisma error code kalau ada (mis. P2002 unique, P2003 FK).
      code: (err as { code?: string }).code ?? null,
      meta: (err as { meta?: unknown }).meta ?? null,
    };
  }
  return { name: "Unknown", message: String(err), code: null, meta: null };
}

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const postId = request.nextUrl.searchParams.get("postId") ?? undefined;

  const post = postId
    ? await prisma.feedPost.findUnique({
        where: { id: postId },
        select: {
          id: true,
          title: true,
          description: true,
          pushSegment: true,
          publishPushSentAt: true,
        },
      })
    : await prisma.feedPost.findFirst({
        where: { notifyOnPublish: true, publishPushSentAt: { not: null } },
        orderBy: { createdAt: "desc" },
        select: {
          id: true,
          title: true,
          description: true,
          pushSegment: true,
          publishPushSentAt: true,
        },
      });

  if (!post) {
    return NextResponse.json({ error: "Tidak ada post notify untuk diuji." }, { status: 404 });
  }

  const { title, body: pushBody, url } = buildFeedPushPayload(
    post.id,
    post.title,
    post.description,
  );
  const segment: PushSegment = (post.pushSegment as PushSegment | null) ?? "members";

  const result: Record<string, unknown> = {
    postId: post.id,
    segment,
    payloadTitleLen: title.length,
    payloadBodyLen: pushBody.length,
    url,
  };

  // Langkah 1: announcement.create (tersangka utama).
  const existing = await prisma.announcement.findFirst({ where: { url } });
  if (existing) {
    result.announcement = { alreadyExists: true, id: existing.id };
  } else {
    try {
      const created = await prisma.announcement.create({
        data: {
          title,
          body: pushBody,
          url,
          segment,
          type: "announcement",
          ctaLabel: "Lihat Post",
          publishedAt: new Date(),
          status: "PUBLISHED",
        },
      });
      result.announcement = { created: true, id: created.id };
    } catch (err) {
      result.announcement = { created: false, error: errInfo(err) };
    }
  }

  // Langkah 2: resolve target (cek apakah ini yang melempar).
  try {
    const ids = await resolveSegmentUserIds(segment);
    result.resolveSegment = { ok: true, count: ids.length };
  } catch (err) {
    result.resolveSegment = { ok: false, error: errInfo(err) };
  }

  return NextResponse.json(result);
}
