/**
 * GET /api/feed/posts?tab=...&cursor=...  — list (public, viewerLiked-aware)
 * POST /api/feed/posts  — create post (auth required)
 *
 * Create routing:
 * - Admin session: bisa create kind VIDEO_ONLY / PRODUCT_ONLY / VIDEO_PRODUCT / PROMO
 *   ke tab REKOMENDASI atau PROMO. status auto-ACTIVE + publishedAt=now.
 * - Customer session: hanya bisa create kind COMMUNITY ke tab KOMUNITAS.
 *   status auto-PENDING_REVIEW (admin moderasi sebelum tampil).
 *
 * Validasi per kind (lihat schema spec section 4 + 5):
 * - VIDEO_ONLY / COMMUNITY: wajib videoUrl + thumbnailUrl, optional productId
 * - PRODUCT_ONLY: wajib productId, NO video fields
 * - VIDEO_PRODUCT: wajib videoUrl + thumbnailUrl + productId
 * - PROMO: wajib productId + promoOriginalPrice + promoDiscountPrice; video opsional
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedPostKind, FeedPostTab } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { sendFeedPendingReviewNotification } from "@/lib/feed/notifications";
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
  // Admin-only: tentukan tab tujuan (REKOMENDASI vs PROMO). User auto-KOMUNITAS.
  tab?: string;
};

const ADMIN_KINDS: ReadonlyArray<FeedPostKind> = [
  "VIDEO_ONLY",
  "PRODUCT_ONLY",
  "VIDEO_PRODUCT",
  "PROMO",
];

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
    if (!(ADMIN_KINDS as ReadonlyArray<string>).includes(rawKind)) {
      return NextResponse.json(
        { error: "Kind invalid untuk admin." },
        { status: 400 },
      );
    }
    kind = rawKind as FeedPostKind;
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
    // Customer hanya bisa COMMUNITY ke KOMUNITAS.
    kind = "COMMUNITY";
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
  if (kind === "PRODUCT_ONLY" || kind === "VIDEO_PRODUCT" || kind === "PROMO") {
    if (!productId) {
      return NextResponse.json(
        { error: "Produk wajib di-tag untuk kind ini." },
        { status: 400 },
      );
    }
  }
  if (kind === "PRODUCT_ONLY" && videoUrl) {
    return NextResponse.json(
      { error: "PRODUCT_ONLY tidak boleh ada video." },
      { status: 400 },
    );
  }

  let promoOriginalPrice: number | null = null;
  let promoDiscountPrice: number | null = null;
  let promoStartsAt: Date | null = null;
  let promoEndsAt: Date | null = null;

  if (kind === "PROMO") {
    promoOriginalPrice = Number(body.promoOriginalPrice);
    promoDiscountPrice = Number(body.promoDiscountPrice);
    if (
      !Number.isFinite(promoOriginalPrice) ||
      !Number.isFinite(promoDiscountPrice) ||
      promoOriginalPrice <= 0 ||
      promoDiscountPrice <= 0
    ) {
      return NextResponse.json(
        { error: "Harga promo tidak valid." },
        { status: 400 },
      );
    }
    if (promoDiscountPrice >= promoOriginalPrice) {
      return NextResponse.json(
        { error: "Harga promo harus lebih kecil dari harga normal." },
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
      await tx.feedPostProduct.createMany({
        data: productIdsToStore.map((taggedProductId, position) => ({
          feedPostId: created.id,
          productId: taggedProductId,
          position,
        })),
        skipDuplicates: true,
      });
    }

    return created;
  });

  if (!isAdmin && post.status === "PENDING_REVIEW") {
    void sendFeedPendingReviewNotification({ postId: post.id });
  }

  return NextResponse.json({ ok: true, post });
}
