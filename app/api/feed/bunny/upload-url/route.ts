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
 * Rate-limited: 10 VIDEO uploads / 24h (count over VIDEO_ONLY + COMMUNITY
 * kinds — PHOTO_CAROUSEL unlimited & tidak counted). Admin sessions exempt.
 */

import { NextRequest, NextResponse } from "next/server";
import type { FeedPostKind, FeedPostTab } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  createBunnyVideo,
  deleteBunnyVideo,
  generateBunnyTusCredentials,
  getBunnyConfig,
} from "@/lib/feed/bunny";
import { parseFeedAccessibilityMetadata } from "@/lib/feed/accessibility";
import { resolveInitialPostStatus } from "@/lib/feed/post-moderation";
import {
  parseTaggedUsersInput,
  type TaggedUserInput,
} from "@/lib/feed/tagged-users";

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

  // Rate limit — count ONLY video kinds (VIDEO_ONLY + COMMUNITY) supaya
  // PHOTO_CAROUSEL post (yang unlimited) tidak ikut burn video slot.
  // Heavy photo poster harusnya tetap bisa upload 10 video/hari penuh.
  if (!isAdmin) {
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);
    const recent = await prisma.feedPost.count({
      where: {
        authorId: session.sub,
        createdAt: { gte: since },
        kind: { in: ["VIDEO_ONLY", "COMMUNITY"] },
      },
    });
    if (recent >= CUSTOMER_RATE_LIMIT_PER_DAY) {
      return NextResponse.json(
        { error: `Batas upload video tercapai (${CUSTOMER_RATE_LIMIT_PER_DAY}/hari). Coba lagi besok atau post foto.` },
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
    taggedUsers?: unknown;
    thumbnailUrl?: string | null;
    videoDurationSec?: number | null;
    videoAltText?: string | null;
    hasAudio?: boolean | null;
    subtitleUrl?: string | null;
    subtitleLanguage?: string | null;
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
    // Admin-only: kirim push notification ke pelanggan saat post publish
    // (setelah video ready). Diabaikan kalau bukan admin.
    notifyOnPublish?: boolean;
    pushSegment?: string;
  };
  // Caption (mapped ke `title` di DB) opsional — kalau user tidak isi caption,
  // simpan string KOSONG (kolom title NOT NULL di DB tetap valid dgn "").
  // JANGAN auto-isi placeholder: post tanpa caption harus tampil polos tanpa
  // baris caption/username (paritas IG). Caption full disimpan di `description`.
  const title = String(body.title ?? "").trim();
  const description = body.description ? String(body.description).trim() : null;
  if (title.length > MAX_TITLE_LENGTH) {
    return NextResponse.json({ error: "Judul terlalu panjang." }, { status: 400 });
  }
  if (description && description.length > MAX_DESC_LENGTH) {
    return NextResponse.json(
      { error: `Deskripsi maksimal ${MAX_DESC_LENGTH} karakter.` },
      { status: 400 },
    );
  }
  const accessibility = parseFeedAccessibilityMetadata(
    body as Record<string, unknown>,
  );
  if (!accessibility.ok) {
    return NextResponse.json({ error: accessibility.error }, { status: 400 });
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

  // Validate productIds DULU sebelum bikin Bunny placeholder — supaya kalau
  // user kirim ID invalid, kita gagal cepat tanpa leak orphan video di
  // Bunny library. Sebelumnya: validasi cuma di transaction (FK violation)
  // yang throw setelah Bunny placeholder dibuat → orphan video numpuk.
  const productIdsToVerify = [
    ...new Set([
      ...productIds,
      ...(productIds.length === 0 && body.productId
        ? [String(body.productId).trim()]
        : []),
    ]),
  ].filter(Boolean);
  if (productIdsToVerify.length > 0) {
    const validProducts = await prisma.product.findMany({
      where: { id: { in: productIdsToVerify } },
      select: { id: true },
    });
    if (validProducts.length !== productIdsToVerify.length) {
      return NextResponse.json(
        {
          error:
            "Produk yang di-tag tidak ditemukan. Refresh app lalu coba lagi.",
        },
        { status: 400 },
      );
    }
  }

  const taggedParse = parseTaggedUsersInput(body.taggedUsers, {
    mediaCount: 0,
    isVideo: true,
  });
  if (!taggedParse.ok) {
    return NextResponse.json({ error: taggedParse.error }, { status: 400 });
  }
  let taggedUsers: TaggedUserInput[] = taggedParse.tags;
  if (taggedUsers.length > 0) {
    const found = await prisma.user.findMany({
      where: { id: { in: taggedUsers.map((t) => t.userId) } },
      select: { id: true },
    });
    if (found.length !== taggedUsers.length) {
      return NextResponse.json(
        { error: "Ada akun yang ditandai tapi tidak ditemukan." },
        { status: 400 },
      );
    }
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

  // Admin can publish kind VIDEO_ONLY / VIDEO_PRODUCT / PROMO via Bunny
  // upload flow. PRODUCT_ONLY sengaja TIDAK termasuk — upload flow ini
  // wajib video (yang di-upload ke Bunny), dan feed sudah video-first
  // (lihat AdminFeedCreateClient). Customer always COMMUNITY → KOMUNITAS.
  const ADMIN_KINDS: FeedPostKind[] = ["VIDEO_ONLY", "VIDEO_PRODUCT", "PROMO"];
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

  // Admin-only: opsi "beri tahu pelanggan" via push saat post publish
  // (dipicu nanti oleh webhook Bunny saat encodingStatus=ready). Sama
  // persis dengan gating di app/api/feed/posts/route.ts.
  const VALID_PUSH_SEGMENTS: ReadonlyArray<string> = ["all", "members", "active30d"];
  const notifyOnPublish = isAdmin && body.notifyOnPublish === true;
  const pushSegment = notifyOnPublish
    ? VALID_PUSH_SEGMENTS.includes(String(body.pushSegment))
      ? String(body.pushSegment)
      : "members"
    : null;

  // Insert FeedPost row in uploading state. videoUrl + thumbnailUrl filled
  // when webhook reports "ready" (encodingStatus=ready). Until then the
  // feed list query excludes this row.
  //
  // Shop the Look: simpan multi-tag ke FeedPostProduct table dalam satu
  // transaction. FeedPost.productId tetap di-set ke primary product
  // (productIds[0]) untuk legacy display + product page query.
  // Status awal — sumber kebenaran tunggal di lib/feed/post-moderation.ts.
  // Sekarang semua konten auto-ACTIVE; gate `encodingStatus: ready` di
  // PUBLIC_FEED_POST_WHERE menjaga video baru muncul setelah encoding selesai
  // (row dibuat dgn encodingStatus=uploading di bawah).
  const { status: initialStatus, publishedAt: initialPublishedAt } =
    resolveInitialPostStatus({ isAdmin, kind });

  let post: { id: string };
  try {
    post = await prisma.$transaction(async (tx) => {
    const created = await tx.feedPost.create({
      data: {
        authorId: session.sub,
        authorRole: isAdmin ? "ADMIN" : "CUSTOMER",
        kind,
        tab,
        status: initialStatus,
        publishedAt: initialPublishedAt,
        title,
        description: finalDescription,
        thumbnailUrl,
        videoDurationSec:
          Number.isFinite(videoDurationSec) && videoDurationSec > 0
            ? Math.round(videoDurationSec)
            : null,
        ...accessibility.data,
        videoGuid: bunnyCreated.guid,
        encodingStatus: "uploading",
        productId: productIdSingle,
        promoOriginalPrice,
        promoDiscountPrice,
        promoStartsAt: promoStartsAt && !Number.isNaN(promoStartsAt.getTime()) ? promoStartsAt : null,
        promoEndsAt: promoEndsAt && !Number.isNaN(promoEndsAt.getTime()) ? promoEndsAt : null,
        notifyOnPublish,
        pushSegment,
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
    if (taggedUsers.length > 0) {
      await tx.feedTaggedUser.createMany({
        data: taggedUsers.map((tag) => ({
          feedPostId: created.id,
          taggedUserId: tag.userId,
          mediaId: null,
          x: null,
          y: null,
        })),
        skipDuplicates: true,
      });
    }
    return created;
    });
  } catch (err) {
    // Prisma transaction gagal padahal Bunny placeholder sudah dibuat.
    // Tanpa cleanup, placeholder jadi orphan video kosong di Bunny library
    // (lihat 2 video "Created" 0x0 yang muncul saat user pertama gagal
    // upload). Di-await — void promise bisa dibekukan Vercel sebelum jalan
    // (error path, latensi tak penting; deleteBunnyVideo tidak throw).
    await deleteBunnyVideo(bunnyCreated.guid).catch((delErr) => {
      console.warn("[upload-url] orphan cleanup failed:", delErr);
    });
    console.error("[upload-url] prisma transaction failed:", err);
    return NextResponse.json(
      {
        error:
          "Gagal simpan postingan ke database. Coba lagi, atau hubungi admin kalau berulang.",
      },
      { status: 500 },
    );
  }

  // Tag People notif — WAJIB await (Vercel void-promise freeze).
  if (taggedUsers.length > 0) {
    try {
      const { sendTaggedUserNotifications } = await import(
        "@/lib/feed/activity-notifications"
      );
      await sendTaggedUserNotifications({
        actorUserId: session.sub,
        recipientUserIds: taggedUsers.map((t) => t.userId),
        postId: post.id,
      });
    } catch (err) {
      console.warn("[upload-url] tagged notif failed:", err);
    }
  }

  // TUS resumable upload — SATU-SATUNYA path sekarang. Pakai signature
  // scoped per-video (generateBunnyTusCredentials), bukan master key.
  //
  // SECURITY: legacy PUT path DIHAPUS. Sebelumnya response include
  // `uploadHeaders.AccessKey = cfg.apiKey` (full BUNNY_API_KEY = master
  // write key library) ke SETIAP customer login. Customer bisa pakai key
  // itu buat create/delete/list SEMUA video di library langsung ke
  // video.bunnycdn.com. Flutter client sudah pakai TUS sebagai path
  // utama (`if (provision.tus != null)` dulu, PUT cuma fallback), dan
  // backend selalu generate TUS, jadi PUT fallback praktis tidak pernah
  // kepakai — aman dihapus tanpa break upload.
  const tusCredentials = await generateBunnyTusCredentials(bunnyCreated.guid);

  return NextResponse.json({
    ok: true,
    postId: post.id,
    videoGuid: bunnyCreated.guid,
    tus: tusCredentials,
  });
}
