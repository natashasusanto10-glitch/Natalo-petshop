/**
 * POST /api/feed/bunny/upload-url
 *
 * Server-side mediation for the Bunny direct-upload flow:
 *
 *   1. Server creates a video placeholder in the Bunny library via the
 *      authenticated API (using BUNNY_API_KEY which the client must
 *      never see).
 *   2. Server creates a FeedPost row pre-filled with the Bunny GUID +
 *      encodingStatus=`uploading` so we have a database handle before
 *      the upload finishes.
 *   3. Returns the upload URL + a short-lived auth token (the real API
 *      key, but the client will throw it away after the one PUT call).
 *
 * Body:
 *   {
 *     title:           string  (3-200 char)
 *     description?:    string  (optional, max 2000)
 *     petType?:        string | null
 *     petName?:        string
 *     productIds?:     string[] (max 3, must belong to user's order history)
 *   }
 *
 * Response:
 *   {
 *     postId:        string         FeedPost.id (use for webhook correlation)
 *     videoGuid:     string         Bunny GUID
 *     uploadUrl:     string         PUT here with raw video bytes
 *     uploadHeaders: { AccessKey: string, "Content-Type": "application/octet-stream" }
 *   }
 *
 * Rate-limited: same 3-per-24h cap as the legacy /api/feed/upload-video
 * route. Admin sessions exempt.
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { createBunnyVideo, getBunnyConfig, bunnyUploadUrl } from "@/lib/feed/bunny";

export const dynamic = "force-dynamic";

const CUSTOMER_RATE_LIMIT_PER_DAY = 3;
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_TITLE_LENGTH = 200;
const MAX_DESC_LENGTH = 2000;

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu untuk upload video." },
      { status: 401 },
    );
  }

  const cfg = getBunnyConfig();
  if (!cfg) {
    return NextResponse.json(
      { error: "Stream service belum dikonfigurasi." },
      { status: 503 },
    );
  }

  // Rate limit — same logic as legacy upload-video.
  if (session.role !== "ADMIN") {
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);
    const recent = await prisma.feedPost.count({
      where: { authorId: session.sub, createdAt: { gte: since } },
    });
    if (recent >= CUSTOMER_RATE_LIMIT_PER_DAY) {
      return NextResponse.json(
        { error: `Batas upload tercapai (${CUSTOMER_RATE_LIMIT_PER_DAY}/hari). Coba lagi besok.` },
        { status: 429 },
      );
    }
  }

  const body = (await request.json().catch(() => ({}))) as {
    title?: string;
    description?: string | null;
    petType?: string | null;
    petName?: string;
    productIds?: unknown;
  };

  // Caption (mapped ke `title` di DB) sekarang opsional sesuai flow baru —
  // kalau user tidak isi caption, kita pakai placeholder "Postingan baru"
  // supaya kolom title (NOT NULL di DB) tetap valid. Caption full disimpan
  // di `description`.
  const rawTitle = String(body.title ?? "").trim();
  const description = body.description ? String(body.description).trim() : null;
  const title = rawTitle.length > 0 ? rawTitle : "Postingan baru";
  if (title.length > MAX_TITLE_LENGTH) {
    return NextResponse.json({ error: "Judul terlalu panjang." }, { status: 400 });
  }
  if (description && description.length > MAX_DESC_LENGTH) {
    return NextResponse.json(
      { error: `Deskripsi maksimal ${MAX_DESC_LENGTH} karakter.` },
      { status: 400 },
    );
  }

  const productIdsFromBody = Array.isArray(body.productIds)
    ? body.productIds.map((v) => String(v ?? "").trim()).filter(Boolean)
    : [];
  const productIds = [...new Set(productIdsFromBody)].slice(0, 3);

  // Bunny: create the video record first. If this fails, no DB row is
  // created — caller can retry without orphan.
  const created = await createBunnyVideo({
    title: `feed-${session.sub}-${Date.now()}`,
  });
  if (!created || "error" in created) {
    const reason = created && "error" in created ? created.error : "no response";
    return NextResponse.json(
      {
        error: "Gagal create video di Bunny.",
        debug: reason,
        hint: "Pastikan BUNNY_LIBRARY_ID adalah angka (contoh 392164), bukan pull zone vz-xxxxx.",
      },
      { status: 502 },
    );
  }

  // Compose the description so it includes pet info, mirroring the legacy
  // upload pipeline's payload shape.
  const petInfo = [body.petType, (body.petName ?? "").trim()]
    .filter(Boolean)
    .join(" · ");
  const descParts = [description ?? "", petInfo ? `Info peliharaan: ${petInfo}` : ""]
    .filter(Boolean);
  const finalDescription = descParts.join("\n\n") || null;

  // Insert FeedPost row in uploading state. videoUrl + thumbnailUrl filled
  // when webhook reports "ready" (encodingStatus=ready). Until then the
  // feed list query excludes this row.
  const post = await prisma.feedPost.create({
    data: {
      authorId: session.sub,
      authorRole: session.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
      kind: "COMMUNITY",
      tab: "KOMUNITAS",
      status: session.role === "ADMIN" ? "ACTIVE" : "PENDING_REVIEW",
      title,
      description: finalDescription,
      videoGuid: created.guid,
      encodingStatus: "uploading",
      productId: productIds[0] ?? null,
    },
    select: { id: true },
  });

  return NextResponse.json({
    ok: true,
    postId: post.id,
    videoGuid: created.guid,
    uploadUrl: bunnyUploadUrl(created.guid),
    uploadHeaders: {
      AccessKey: cfg.apiKey,
      "Content-Type": "application/octet-stream",
    },
  });
}
