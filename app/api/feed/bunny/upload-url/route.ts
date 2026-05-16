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
 *     productIds?:     string[] (customer max 3, admin max 5)
 *     thumbnailUrl?:   string | null (client-generated preview)
 *     videoDurationSec?: number | null
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
import type { FeedPostKind, FeedPostTab } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { createBunnyVideo, getBunnyConfig, bunnyUploadUrl } from "@/lib/feed/bunny";

export const dynamic = "force-dynamic";

const CUSTOMER_RATE_LIMIT_PER_DAY = 10;
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_TITLE_LENGTH = 200;
const MAX_DESC_LENGTH = 2000;

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  // Cek ADMIN session DULU — kalau admin user juga punya member cookie
  // dari testing-as-customer atau sesi parallel, default getSession() yang
  // priority MEMBER bikin admin upload masuk PENDING_REVIEW (bug).
  // Try admin first, fallback customer.
  const session =
    (await getSession("ADMIN")) ?? (await getSession("CUSTOMER"));
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

  const isAdmin = session.role === "ADMIN";

  // Rate limit — same logic as legacy upload-video.
  if (!isAdmin) {
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
    thumbnailUrl?: string | null;
    videoDurationSec?: number | null;
    // Admin-only fields. Customer sessions always create COMMUNITY posts to
    // the KOMUNITAS tab regardless of what's sent.
    kind?: string;
    tab?: string;
    productId?: string | null;
    promoOriginalPrice?: number | null;
    promoDiscountPrice?: number | null;
    promoStartsAt?: string | null;
    promoEndsAt?: string | null;
    // Per-product promo pricing. Map productId → discountPrice. null =
    // no discount untuk produk itu (display harga normal).
    productPromos?: Record<string, number | null>;
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

  const maxTaggedProducts = isAdmin ? 5 : 3;
  const productIdsFromBody = Array.isArray(body.productIds)
    ? body.productIds.map((v) => String(v ?? "").trim()).filter(Boolean)
    : [];
  const productIds = [...new Set(productIdsFromBody)];
  if (
    productIdsFromBody.length > maxTaggedProducts ||
    productIds.length > maxTaggedProducts
  ) {
    return NextResponse.json(
      { error: `Maksimal ${maxTaggedProducts} produk yang bisa di-tag.` },
      { status: 400 },
    );
  }

  // Bunny: create the video record first. If this fails, no DB row is
  // created — caller can retry without orphan.
  const bunnyCreated = await createBunnyVideo({
    title: `feed-${session.sub}-${Date.now()}`,
  });
  if (!bunnyCreated || "error" in bunnyCreated) {
    const reason =
      bunnyCreated && "error" in bunnyCreated ? bunnyCreated.error : "no response";
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
  const thumbnailUrl = body.thumbnailUrl
    ? String(body.thumbnailUrl).trim()
    : null;
  const videoDurationSec = Number(body.videoDurationSec);

  // Admin can publish to other kinds/tabs (VIDEO_ONLY, PRODUCT_ONLY,
  // VIDEO_PRODUCT, PROMO). Customer is always COMMUNITY → KOMUNITAS.
  const ADMIN_KINDS: FeedPostKind[] = ["VIDEO_ONLY", "PRODUCT_ONLY", "VIDEO_PRODUCT", "PROMO"];
  let kind: FeedPostKind = "COMMUNITY";
  let tab: FeedPostTab = "KOMUNITAS";
  if (isAdmin) {
    const rawKind = String(body.kind ?? "VIDEO_ONLY");
    kind = (ADMIN_KINDS as ReadonlyArray<string>).includes(rawKind)
      ? (rawKind as FeedPostKind)
      : "VIDEO_ONLY";
    if (kind === "PROMO") {
      tab = "PROMO";
    } else {
      const rawTab = String(body.tab ?? "REKOMENDASI");
      tab = rawTab === "PROMO" ? "PROMO" : "REKOMENDASI";
    }
  }

  // Optional admin promo + product fields.
  const productIdSingle = isAdmin && body.productId
    ? String(body.productId).trim()
    : productIds[0] ?? null;
  const productIdsToStore =
    productIds.length > 0 ? productIds : productIdSingle ? [productIdSingle] : [];
  const promoOriginalPrice =
    isAdmin && kind === "PROMO" && Number.isFinite(Number(body.promoOriginalPrice))
      ? Number(body.promoOriginalPrice)
      : null;
  const promoDiscountPrice =
    isAdmin && kind === "PROMO" && Number.isFinite(Number(body.promoDiscountPrice))
      ? Number(body.promoDiscountPrice)
      : null;
  const promoStartsAt =
    isAdmin && body.promoStartsAt ? new Date(body.promoStartsAt) : null;
  const promoEndsAt =
    isAdmin && body.promoEndsAt ? new Date(body.promoEndsAt) : null;

  // Insert FeedPost row in uploading state. videoUrl + thumbnailUrl filled
  // when webhook reports "ready" (encodingStatus=ready). Until then the
  // feed list query excludes this row.
  //
  // Shop the Look: simpan multi-tag ke FeedPostProduct table dalam satu
  // transaction. FeedPost.productId tetap di-set ke primary product
  // (productIds[0]) untuk legacy display + product page query.
  const post = await prisma.$transaction(async (tx) => {
    const created = await tx.feedPost.create({
      data: {
        authorId: session.sub,
        authorRole: isAdmin ? "ADMIN" : "CUSTOMER",
        kind,
        tab,
        status: isAdmin ? "ACTIVE" : "PENDING_REVIEW",
        publishedAt: isAdmin ? new Date() : null,
        title,
        description: finalDescription,
        thumbnailUrl,
        videoDurationSec:
          Number.isFinite(videoDurationSec) && videoDurationSec > 0
            ? Math.round(videoDurationSec)
            : null,
        videoGuid: bunnyCreated.guid,
        encodingStatus: "uploading",
        productId: productIdSingle,
        promoOriginalPrice,
        promoDiscountPrice,
        promoStartsAt: promoStartsAt && !Number.isNaN(promoStartsAt.getTime()) ? promoStartsAt : null,
        promoEndsAt: promoEndsAt && !Number.isNaN(promoEndsAt.getTime()) ? promoEndsAt : null,
      },
      select: { id: true },
    });
    if (productIdsToStore.length > 0) {
      // Resolve per-product promo price untuk setiap tagged product. Hanya
      // admin yang post kind=PROMO yang boleh set promoPrice. Untuk
      // customer / non-PROMO, promoPrice di-paksa null (no discount badge).
      const promoMap =
        isAdmin && kind === "PROMO" && body.productPromos
          ? body.productPromos
          : null;
      await tx.feedPostProduct.createMany({
        data: productIdsToStore.map((productId, position) => {
          const rawPromo = promoMap ? promoMap[productId] : null;
          const promoPrice =
            rawPromo === null || rawPromo === undefined
              ? null
              : Number.isFinite(Number(rawPromo))
                ? Number(rawPromo)
                : null;
          return {
            feedPostId: created.id,
            productId,
            position,
            promoPrice,
          };
        }),
        skipDuplicates: true,
      });
    }
    return created;
  });

  return NextResponse.json({
    ok: true,
    postId: post.id,
    videoGuid: bunnyCreated.guid,
    uploadUrl: bunnyUploadUrl(bunnyCreated.guid),
    uploadHeaders: {
      AccessKey: cfg.apiKey,
      "Content-Type": "application/octet-stream",
    },
  });
}
