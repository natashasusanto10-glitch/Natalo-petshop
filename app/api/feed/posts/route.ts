/**
 * GET /api/feed/posts?tab=...&cursor=...  — list (public, viewerLiked-aware)
 * POST /api/feed/posts  — create post (auth required)
 *
 * Create routing:
 * - Admin session: bisa create kind VIDEO_ONLY / VIDEO_PRODUCT / PROMO
 *   ke tab REKOMENDASI atau PROMO. status auto-ACTIVE + publishedAt=now.
 *   PRODUCT_ONLY deprecated dari create — feed sekarang video-first.
 *   Existing PRODUCT_ONLY post di DB tetap render (backward compat).
 * - Customer session: hanya bisa create kind COMMUNITY ke tab KOMUNITAS.
 *   status auto-PENDING_REVIEW (admin moderasi sebelum tampil).
 *
 * Validasi per kind:
 * - VIDEO_ONLY / COMMUNITY: wajib videoUrl + thumbnailUrl, optional productId
 * - VIDEO_PRODUCT: wajib videoUrl + thumbnailUrl + productId
 * - PROMO: wajib productId + (productPromos atau legacy promoOriginal/Discount)
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedPostKind, FeedPostTab } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { sendFeedPendingReviewNotification } from "@/lib/feed/notifications";
import { sendMentionNotifications } from "@/lib/feed/activity-notifications";
import {
  extractMentionHandles,
  resolveMentionedUsers,
} from "@/lib/feed/mentions";
import { listFeedPosts } from "@/lib/feed/queries";
import { ADMIN_VIDEO_CONFIG, USER_VIDEO_CONFIG } from "@/lib/feed/video-config";

// Make sure the feed list never gets cached at the edge — newly approved
// posts must appear on the next pull without waiting for a revalidation
// window or a service-worker bust.
export const dynamic = "force-dynamic";
export const revalidate = 0;

const VALID_TABS: ReadonlyArray<FeedPostTab> = ["REKOMENDASI", "PROMO", "KOMUNITAS"];
const CUSTOMER_MIN_VIDEO_DURATION_SEC = USER_VIDEO_CONFIG.minDuration;
const CUSTOMER_MAX_VIDEO_DURATION_SEC = USER_VIDEO_CONFIG.maxDuration;
const ADMIN_MIN_VIDEO_DURATION_SEC = ADMIN_VIDEO_CONFIG.minDuration;
const ADMIN_MAX_VIDEO_DURATION_SEC = ADMIN_VIDEO_CONFIG.maxDuration;

function isValidTab(value: string | null): value is FeedPostTab {
  return value !== null && (VALID_TABS as ReadonlyArray<string>).includes(value);
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const rawTab = searchParams.get("tab");
  if (rawTab && !isValidTab(rawTab)) {
    return NextResponse.json(
      { error: "Parameter `tab` harus REKOMENDASI, PROMO, atau KOMUNITAS." },
      { status: 400 },
    );
  }
  const tab = rawTab ? (rawTab as FeedPostTab) : null;

  const cursor = searchParams.get("cursor") || null;
  // Shop the Look — filter feed ke posts yang tag produk tertentu.
  // Dipakai saat user buka /feed?product=<slug> dari product page.
  const productSlug = searchParams.get("product") || null;
  const session = await getSession().catch(() => null);

  const result = await listFeedPosts({
    tab,
    cursor,
    viewerUserId: session?.sub ?? null,
    productSlug,
  });

  return NextResponse.json(result);
}

type CreatePostBody = {
  kind?: string;
  title?: string;
  description?: string | null;
  videoUrl?: string | null;
  thumbnailUrl?: string | null;
  videoDurationSec?: number | null;
  videoWidth?: number | null;
  videoHeight?: number | null;
  videoMimeType?: string | null;
  videoSizeBytes?: number | null;
  productId?: string | null;
  productIds?: unknown;
  promoOriginalPrice?: number | null;
  promoDiscountPrice?: number | null;
  promoStartsAt?: string | null;
  promoEndsAt?: string | null;
  // Per-product promo pricing (admin-only kind=PROMO). Map productId →
  // discount price; null = no discount.
  productPromos?: Record<string, number | null>;
  // Admin-only: tentukan tab tujuan (REKOMENDASI vs PROMO). User auto-KOMUNITAS.
  tab?: string;
  // PHOTO_CAROUSEL kind: array of 1-8 image objects yang sudah ter-upload
  // ke UploadThing via /api/feed/upload-photo. Server stores sebagai
  // FeedMedia rows dengan sortOrder mengikuti urutan array.
  images?: Array<{
    url: string;
    key?: string | null;
    width?: number | null;
    height?: number | null;
  }>;
};

// PRODUCT_ONLY sengaja TIDAK termasuk — admin create sekarang video-first
// (lihat AdminFeedCreateClient header). Existing PRODUCT_ONLY post di DB
// tetap render di feed untuk backward compat, tapi tidak bisa create baru
// lewat API. Banner produk tanpa video → arahkan ke landing page produk
// atau banner homepage.
//
// PHOTO_CAROUSEL ditambahkan — admin bisa create photo post (1-8 foto)
// ke REKOMENDASI tab (sama seperti video admin post).
const ADMIN_KINDS: ReadonlyArray<FeedPostKind> = [
  "VIDEO_ONLY",
  "VIDEO_PRODUCT",
  "PROMO",
  "PHOTO_CAROUSEL",
];

/// Min/max foto per PHOTO_CAROUSEL post. Enforce di POST validation.
const PHOTO_CAROUSEL_MIN_IMAGES = 1;
const PHOTO_CAROUSEL_MAX_IMAGES = 8;

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  // Try ADMIN session first — kalau admin user juga punya member cookie,
  // default getSession() priority MEMBER bikin admin post masuk PENDING_REVIEW
  // (treated as customer). Lihat lib/auth.ts:66 untuk cookie priority order.
  const session =
    (await getSession("ADMIN")) ?? (await getSession("CUSTOMER"));
  if (!session) {
    return NextResponse.json({ error: "Login dulu untuk posting." }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as CreatePostBody;
  const title = String(body.title ?? "").trim();
  const description = body.description ? String(body.description).trim() : null;

  if (!title || title.length < 3) {
    return NextResponse.json(
      { error: "Judul minimal 3 karakter." },
      { status: 400 },
    );
  }
  if (title.length > 200) {
    return NextResponse.json({ error: "Judul terlalu panjang." }, { status: 400 });
  }
  if (description && description.length > 2000) {
    return NextResponse.json(
      { error: "Deskripsi terlalu panjang (max 2000 char)." },
      { status: 400 },
    );
  }

  const isAdmin = session.role === "ADMIN";

  // ── Determine kind + tab berdasarkan role ─────────────────────────
  let kind: FeedPostKind;
  let tab: FeedPostTab;

  if (isAdmin) {
    const rawKind = String(body.kind ?? "");
    const normalizedKind = rawKind === "COMMUNITY" ? "VIDEO_ONLY" : rawKind;
    if (!(ADMIN_KINDS as ReadonlyArray<string>).includes(normalizedKind)) {
      return NextResponse.json(
        { error: "Kind invalid untuk admin." },
        { status: 400 },
      );
    }
    kind = normalizedKind as FeedPostKind;
    // PROMO kind selalu masuk tab PROMO; lainnya admin pilih.
    if (kind === "PROMO") {
      tab = "PROMO";
    } else {
      const rawTab = String(body.tab ?? "REKOMENDASI");
      if (rawTab !== "REKOMENDASI" && rawTab !== "PROMO") {
        return NextResponse.json(
          { error: "Tab admin: REKOMENDASI atau PROMO." },
          { status: 400 },
        );
      }
      tab = rawTab as FeedPostTab;
    }
  } else {
    // Customer: default COMMUNITY (video), OR PHOTO_CAROUSEL kalau
    // body specify. Customer-side photo posts juga masuk KOMUNITAS tab.
    const rawKind = String(body.kind ?? "COMMUNITY");
    if (rawKind === "PHOTO_CAROUSEL") {
      kind = "PHOTO_CAROUSEL";
    } else {
      kind = "COMMUNITY";
    }
    tab = "KOMUNITAS";
  }

  // ── Field-level validation per kind ───────────────────────────────
  const videoUrl = body.videoUrl ? String(body.videoUrl).trim() : null;
  const thumbnailUrl = body.thumbnailUrl ? String(body.thumbnailUrl).trim() : null;
  const maxTaggedProducts = isAdmin ? 5 : 3;
  const productIdsFromBody = Array.isArray(body.productIds)
    ? body.productIds
        .map((value) => String(value ?? "").trim())
        .filter(Boolean)
    : [];
  const productIds = [...new Set(productIdsFromBody)];
  if (
    productIdsFromBody.length > maxTaggedProducts ||
    productIds.length > maxTaggedProducts
  ) {
    return NextResponse.json(
      { error: `Maksimal ${maxTaggedProducts} produk yang bisa di-pin.` },
      { status: 400 },
    );
  }
  const productIdFromBody = body.productId ? String(body.productId).trim() : null;
  const productId =
    productIds.length > 0 ? productIds[0] : productIdFromBody;
  const productIdsToVerify = [
    ...new Set([...productIds, ...(productId ? [productId] : [])]),
  ];
  if (productIdsToVerify.length > maxTaggedProducts) {
    return NextResponse.json(
      { error: `Maksimal ${maxTaggedProducts} produk yang bisa di-pin.` },
      { status: 400 },
    );
  }
  const productIdsToStore =
    productIds.length > 0 ? productIds : productId ? [productId] : [];

  // PHOTO_CAROUSEL kind validation — 1-8 image objects with valid URL.
  // Validate sebelum video kind branch supaya tidak hit "Video wajib"
  // false-positive untuk photo post.
  type PhotoInput = {
    url: string;
    key?: string | null;
    width?: number | null;
    height?: number | null;
  };
  let photoInputs: PhotoInput[] = [];
  if (kind === "PHOTO_CAROUSEL") {
    const rawImages = Array.isArray(body.images) ? body.images : [];
    photoInputs = rawImages
      .map((item): PhotoInput | null => {
        if (!item || typeof item !== "object") return null;
        const url = String((item as Record<string, unknown>).url ?? "").trim();
        if (!url) return null;
        const key = (item as Record<string, unknown>).key;
        const width = (item as Record<string, unknown>).width;
        const height = (item as Record<string, unknown>).height;
        return {
          url,
          key: typeof key === "string" ? key : null,
          width:
            typeof width === "number" && Number.isFinite(width)
              ? Math.floor(width)
              : null,
          height:
            typeof height === "number" && Number.isFinite(height)
              ? Math.floor(height)
              : null,
        };
      })
      .filter((item): item is PhotoInput => item !== null);
    if (photoInputs.length < PHOTO_CAROUSEL_MIN_IMAGES) {
      return NextResponse.json(
        { error: "Pilih minimal 1 foto untuk melanjutkan." },
        { status: 400 },
      );
    }
    if (photoInputs.length > PHOTO_CAROUSEL_MAX_IMAGES) {
      return NextResponse.json(
        { error: `Maksimal ${PHOTO_CAROUSEL_MAX_IMAGES} foto dalam 1 postingan.` },
        { status: 400 },
      );
    }
  }

  if (kind === "VIDEO_ONLY" || kind === "VIDEO_PRODUCT" || kind === "COMMUNITY") {
    if (!videoUrl || !thumbnailUrl) {
      return NextResponse.json(
        { error: "Video + thumbnail wajib." },
        { status: 400 },
      );
    }
    if (!isAdmin) {
      const durationSec = Number(body.videoDurationSec);
      if (
        !Number.isFinite(durationSec) ||
        durationSec < CUSTOMER_MIN_VIDEO_DURATION_SEC ||
        durationSec > CUSTOMER_MAX_VIDEO_DURATION_SEC
      ) {
        return NextResponse.json(
          { error: `Durasi video Feed harus ${CUSTOMER_MIN_VIDEO_DURATION_SEC}-${CUSTOMER_MAX_VIDEO_DURATION_SEC} detik.` },
          { status: 400 },
        );
      }
    }
    if (isAdmin && videoUrl) {
      const durationSec = Number(body.videoDurationSec);
      if (
        !Number.isFinite(durationSec) ||
        durationSec < ADMIN_MIN_VIDEO_DURATION_SEC ||
        durationSec > ADMIN_MAX_VIDEO_DURATION_SEC
      ) {
        return NextResponse.json(
          { error: `Durasi video admin harus ${ADMIN_MIN_VIDEO_DURATION_SEC}-${ADMIN_MAX_VIDEO_DURATION_SEC} detik.` },
          { status: 400 },
        );
      }
    }
    if ((videoUrl && !thumbnailUrl) || (!videoUrl && thumbnailUrl)) {
      return NextResponse.json(
        { error: "Video + thumbnail harus lengkap." },
        { status: 400 },
      );
    }
  }
  if (kind === "VIDEO_PRODUCT" || kind === "PROMO") {
    if (!productId) {
      return NextResponse.json(
        { error: "Produk wajib di-tag untuk kind ini." },
        { status: 400 },
      );
    }
  }
  // PRODUCT_ONLY (card produk tanpa video) sudah deprecated dari create
  // path — di-reject upfront via ADMIN_KINDS allow-list. Lihat header
  // comment di file ini.

  let promoOriginalPrice: number | null = null;
  let promoDiscountPrice: number | null = null;
  let promoStartsAt: Date | null = null;
  let promoEndsAt: Date | null = null;

  if (kind === "PROMO") {
    // Per-product pricing is the new default — single promoOriginal/
    // promoDiscount fields jadi opsional (legacy backward-compat). Kalau
    // admin submit productPromos map, skip required validation di sini.
    const hasPerProductPromo =
      body.productPromos &&
      typeof body.productPromos === "object" &&
      Object.values(body.productPromos).some(
        (v) => v !== null && v !== undefined && Number.isFinite(Number(v)),
      );

    const rawOrig = Number(body.promoOriginalPrice);
    const rawDisc = Number(body.promoDiscountPrice);
    const hasLegacyPromo =
      Number.isFinite(rawOrig) &&
      Number.isFinite(rawDisc) &&
      rawOrig > 0 &&
      rawDisc > 0;

    if (hasLegacyPromo) {
      if (rawDisc >= rawOrig) {
        return NextResponse.json(
          { error: "Harga promo harus lebih kecil dari harga normal." },
          { status: 400 },
        );
      }
      promoOriginalPrice = rawOrig;
      promoDiscountPrice = rawDisc;
    } else if (!hasPerProductPromo) {
      // Neither legacy nor per-product promo set — invalid PROMO post.
      return NextResponse.json(
        {
          error:
            "Set minimal 1 harga promo per-produk untuk video PROMO.",
        },
        { status: 400 },
      );
    }

    if (body.promoStartsAt) {
      const d = new Date(body.promoStartsAt);
      if (!Number.isNaN(d.getTime())) promoStartsAt = d;
    }
    if (body.promoEndsAt) {
      const d = new Date(body.promoEndsAt);
      if (!Number.isNaN(d.getTime())) promoEndsAt = d;
    }
  }

  // ── Verify FK produk kalau di-tag ─────────────────────────────────
  if (productIdsToVerify.length > 0) {
    const products = await prisma.product.findMany({
      where: { id: { in: productIdsToVerify } },
      select: { id: true, isActive: true },
    });
    if (products.length !== productIdsToVerify.length) {
      return NextResponse.json({ error: "Produk tidak ditemukan." }, { status: 404 });
    }
    if (products.some((product) => !product.isActive) && !isAdmin) {
      return NextResponse.json(
        { error: "Produk tidak aktif, tidak bisa di-tag." },
        { status: 400 },
      );
    }

    if (!isAdmin) {
      const verifiedPurchases = await prisma.orderItem.findMany({
        where: {
          productId: { in: productIdsToVerify },
          order: {
            userId: session.sub,
            paymentStatus: "PAID",
            status: "DELIVERED",
          },
        },
        select: { productId: true },
        distinct: ["productId"],
      });
      if (verifiedPurchases.length !== productIdsToVerify.length) {
        return NextResponse.json(
          {
            error:
              "Produk yang di-pin harus berasal dari riwayat pembelian yang sudah diterima.",
          },
          { status: 403 },
        );
      }
    }
  }

  // ── Status workflow ───────────────────────────────────────────────
  // Admin auto-ACTIVE; user COMMUNITY masuk PENDING_REVIEW.
  const status = isAdmin ? "ACTIVE" : "PENDING_REVIEW";
  const publishedAt = isAdmin ? new Date() : null;

  const post = await prisma.$transaction(async (tx) => {
    const created = await tx.feedPost.create({
      data: {
        authorId: session.sub,
        authorRole: isAdmin ? "ADMIN" : "CUSTOMER",
        kind,
        tab,
        status,
        title,
        description,
        videoUrl,
        thumbnailUrl,
        videoMimeType: body.videoMimeType ? String(body.videoMimeType) : null,
        videoSizeBytes:
          Number.isFinite(Number(body.videoSizeBytes)) && Number(body.videoSizeBytes) > 0
            ? Number(body.videoSizeBytes)
            : null,
        videoDurationSec:
          Number.isFinite(Number(body.videoDurationSec)) && Number(body.videoDurationSec) > 0
            ? Math.floor(Number(body.videoDurationSec))
            : null,
        videoWidth:
          Number.isFinite(Number(body.videoWidth)) && Number(body.videoWidth) > 0
            ? Math.floor(Number(body.videoWidth))
            : null,
        videoHeight:
          Number.isFinite(Number(body.videoHeight)) && Number(body.videoHeight) > 0
            ? Math.floor(Number(body.videoHeight))
            : null,
        productId,
        promoOriginalPrice,
        promoDiscountPrice,
        promoStartsAt,
        promoEndsAt,
        publishedAt,
      },
      select: {
        id: true,
        status: true,
        kind: true,
        tab: true,
      },
    });

    if (productIdsToStore.length > 0) {
      // Per-product promo pricing — admin kind=PROMO only.
      const promoMap =
        isAdmin && kind === "PROMO" && body.productPromos
          ? body.productPromos
          : null;
      await tx.feedPostProduct.createMany({
        data: productIdsToStore.map((taggedProductId, position) => {
          const rawPromo = promoMap ? promoMap[taggedProductId] : null;
          const promoPrice =
            rawPromo === null || rawPromo === undefined
              ? null
              : Number.isFinite(Number(rawPromo))
                ? Number(rawPromo)
                : null;
          return {
            feedPostId: created.id,
            productId: taggedProductId,
            position,
            promoPrice,
          };
        }),
        skipDuplicates: true,
      });
    }

    // PHOTO_CAROUSEL: create 1-8 FeedMedia rows dengan sortOrder
    // mengikuti urutan array dari client. sortOrder 0 = cover/thumbnail
    // utama yang dipakai di my-posts list + feed loading state.
    if (kind === "PHOTO_CAROUSEL" && photoInputs.length > 0) {
      await tx.feedMedia.createMany({
        data: photoInputs.map((photo, index) => ({
          postId: created.id,
          mediaType: "image",
          url: photo.url,
          uploadthingKey: photo.key,
          width: photo.width,
          height: photo.height,
          sortOrder: index,
        })),
      });
    }

    return created;
  });

  if (!isAdmin && post.status === "PENDING_REVIEW") {
    void sendFeedPendingReviewNotification({ postId: post.id });
  }

  // @mention notification — caption (title + description) di-parse,
  // user yang di-mention dapat notif "@actor menyebut kamu di
  // postingan". Fire kalau post ACTIVE (admin auto-publish) atau pending
  // tetap (defer notif sampai approved? Untuk simplicity fire sekarang —
  // user yang di-mention bisa lihat profile actor + post saat di-approve).
  void (async () => {
    try {
      const captionText = `${title} ${description}`.trim();
      const handles = extractMentionHandles(captionText);
      if (handles.size === 0) return;
      const mentioned = await resolveMentionedUsers(handles, session.sub);
      if (mentioned.length === 0) return;
      await sendMentionNotifications({
        actorUserId: session.sub,
        recipientUserIds: mentioned.map((u) => u.id),
        source: "post",
        postId: post.id,
        commentId: null,
        excerpt: captionText,
      });
    } catch (err) {
      console.warn("[posts] mention notif failed:", err);
    }
  })();

  return NextResponse.json({ ok: true, post });
}
