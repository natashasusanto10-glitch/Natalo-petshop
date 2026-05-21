/**
 * Personalized Recommendations API — server-side scoring engine untuk
 * home screen "Rekomendasi Untuk Kamu".
 *
 * BEDA dengan /api/cart/recommendations:
 *  - cart-recommendations: multi-pass priority push (manual rules → cat/brand
 *    from viewed → purchased → popular). Tidak ada intra-pass scoring.
 *  - personalized: SINGLE weighted scoring pass. Purchase = signal primer
 *    (×3.0/2.5), view = signal sekunder (×1.2/1.8). Scan candidate pool
 *    lebih luas (top brands+categories × 50 candidates) → re-rank.
 *
 * BEDA dengan client-side scoring di home_screen.dart sebelumnya:
 *  - Pool 48 produk (limited by home fetch) → sekarang scan SELURUH
 *    catalog via DB query dengan WHERE brand IN top OR category IN top.
 *  - Tidak ada purchase signal (cuma view + search) → sekarang purchase
 *    jadi signal utama (×3.0 brand, ×2.5 category).
 *  - O(N) loop di mobile RAM untuk 2134 product → SQL index-backed query.
 *
 * Signal sources:
 *  1. Client-side `viewed` query param (recently_viewed_store, last 20)
 *  2. Server-side user_product_views table (last 30, kalau user login)
 *  3. Server-side orderItem table (last 60, kalau user login)
 *
 * Scoring rules:
 *  - Purchase brand:    score += recency × 3.0
 *  - Purchase category: score += recency × 2.5
 *  - View brand:        score += recency × 1.2
 *  - View category:     score += recency × 1.8
 *  - hasDiscount boost: +0.8
 *  - rating boost:      ×0.18 (cap 5)
 *  - reviewCount boost: /500 (cap 1.0)
 *
 *  Recency: weight = 1 - (index / total) → most recent = 1.0, oldest → 0.0+ε.
 *
 * Cold-start fallback (user guest atau zero history):
 *  Sort by reviewCount desc + avgRating desc + hasDiscount boost.
 *
 * Exclusion:
 *  - Produk yang sudah di-viewed di-EXCLUDE (no point recommend ulang)
 *  - Produk yang sudah dibeli di-EXCLUDE (assumption: durable goods.
 *    Future improvement: per-category consumable detection untuk pet food
 *    repurchase prediction.)
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import {
  cartRecommendationProductInclude,
  cartRecommendationWhere,
  serializeCartRecommendationProduct,
  type CartRecommendationProductRow,
} from "@/lib/cart-recommendation-products";
import { attachPublicProductVoucherPreviews } from "@/lib/product-vouchers";

function parseIds(value: string | null) {
  return (value ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean)
    .slice(0, 100);
}

type ScoreMap = Map<string, number>;

function addScore(map: ScoreMap, key: string | null | undefined, value: number) {
  if (!key) return;
  map.set(key, (map.get(key) ?? 0) + value);
}

function topNKeys(map: ScoreMap, n: number) {
  return [...map.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, n)
    .map(([key]) => key);
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const limit = Math.min(
    Math.max(Number(searchParams.get("limit") ?? 10) || 10, 1),
    20,
  );
  const clientViewIds = parseIds(searchParams.get("viewed"));
  // Caller bisa kirim list ID yang HARUS di-exclude dari hasil. Dipakai
  // wishlist supaya produk yang sudah di-favorite tidak muncul lagi di
  // section "Ayo Dilihat Kembali".
  const callerExcludeIds = parseIds(searchParams.get("exclude"));
  const session = await getSession("CUSTOMER").catch(() => null);
  const userId = session?.sub ?? null;

  // ─── 1. Gather signals ────────────────────────────────────────────────
  // Server-side view tracking (kalau login).
  let serverViewIds: string[] = [];
  if (userId) {
    try {
      const rows = await prisma.$queryRaw<{ product_id: string }[]>`
        SELECT "product_id"
        FROM "user_product_views"
        WHERE "user_id" = ${userId}
        ORDER BY "viewed_at" DESC
        LIMIT 30
      `;
      serverViewIds = rows.map((row) => row.product_id);
    } catch {
      serverViewIds = [];
    }
  }

  // Order item history (kalau login). Order by id desc = paling baru pertama
  // (id auto-increment by creation time).
  type PurchasedRow = {
    productId: string;
    product: { categoryId: string | null; brandId: string | null };
  };
  let purchasedItems: PurchasedRow[] = [];
  if (userId) {
    try {
      purchasedItems = await prisma.orderItem.findMany({
        where: {
          order: {
            userId,
            // Hanya order yang sudah commited (bayar / kirim / selesai).
            status: { in: ["PAID", "PROCESSING", "SHIPPED", "DELIVERED"] },
          },
        },
        orderBy: { id: "desc" },
        take: 60,
        select: {
          productId: true,
          product: { select: { categoryId: true, brandId: true } },
        },
      });
    } catch {
      purchasedItems = [];
    }
  }

  // Merge view IDs (client + server, dedup, keep client order priority).
  const seenViewSet = new Set<string>();
  const viewIds: string[] = [];
  for (const id of [...clientViewIds, ...serverViewIds]) {
    if (seenViewSet.has(id)) continue;
    seenViewSet.add(id);
    viewIds.push(id);
  }

  // Exclude list: produk yang sudah view + sudah dibeli (assumption: durable)
  // + IDs yang dikirim caller (mis. wishlist user — supaya tidak duplikat
  // dengan list favorit).
  const purchasedIds = purchasedItems.map((it) => it.productId);
  const excludeSet = new Set<string>([
    ...viewIds,
    ...purchasedIds,
    ...callerExcludeIds,
  ]);

  // ─── 2. Fetch detail (brand + category) untuk viewed products ─────────
  // Purchase sudah include brand+category via Prisma include.
  let viewedDetails: { id: string; brandId: string | null; categoryId: string | null }[] = [];
  if (viewIds.length > 0) {
    viewedDetails = await prisma.product.findMany({
      where: { id: { in: viewIds } },
      select: { id: true, brandId: true, categoryId: true },
    });
  }

  // Map viewIds order → recency weight (1.0 = newest, ~0 = oldest).
  const viewIndexMap = new Map(viewIds.map((id, idx) => [id, idx]));

  // ─── 3. Build brand & category score maps ─────────────────────────────
  const brandScores: ScoreMap = new Map();
  const categoryScores: ScoreMap = new Map();

  // Purchase signals (×3.0 / ×2.5). Strongest.
  const purchaseN = purchasedItems.length;
  purchasedItems.forEach((item, idx) => {
    const recency = 1 - idx / Math.max(purchaseN, 1);
    addScore(brandScores, item.product.brandId, recency * 3.0);
    addScore(categoryScores, item.product.categoryId, recency * 2.5);
  });

  // View signals (×1.2 / ×1.8). Lebih lemah dari purchase.
  const viewN = viewIds.length;
  viewedDetails.forEach((row) => {
    const idx = viewIndexMap.get(row.id) ?? viewN;
    const recency = 1 - idx / Math.max(viewN, 1);
    addScore(brandScores, row.brandId, recency * 1.2);
    addScore(categoryScores, row.categoryId, recency * 1.8);
  });

  const topBrandIds = topNKeys(brandScores, 5);
  const topCategoryIds = topNKeys(categoryScores, 5);
  const hasPersonalSignal = topBrandIds.length > 0 || topCategoryIds.length > 0;

  // ─── 4. Fetch candidate pool ─────────────────────────────────────────
  const excludeArr = [...excludeSet];
  let candidates: CartRecommendationProductRow[] = [];

  if (hasPersonalSignal) {
    // Scan candidates matching top brands ATAU top categories. limit × 5
    // supaya re-ranking punya cukup variation untuk pick best.
    candidates = await prisma.product.findMany({
      where: {
        AND: [
          cartRecommendationWhere(excludeArr),
          {
            OR: [
              ...(topBrandIds.length > 0 ? [{ brandId: { in: topBrandIds } }] : []),
              ...(topCategoryIds.length > 0
                ? [{ categoryId: { in: topCategoryIds } }]
                : []),
            ],
          },
        ],
      },
      orderBy: [
        { reviewCount: "desc" },
        { avgRating: "desc" },
        { createdAt: "desc" },
      ],
      take: limit * 5,
      include: cartRecommendationProductInclude(),
    });
  }

  // ─── 5. Re-rank candidates by combined signal score ──────────────────
  const scored = candidates.map((product) => {
    let score = 0;
    score += brandScores.get(product.brandId ?? "") ?? 0;
    score += categoryScores.get(product.categoryId ?? "") ?? 0;
    // Boost diskon (Promo Toko / Flash Sale aktif).
    const hasActiveDiscount =
      product.discountItems.length > 0 ||
      (product.flashSaleEndsAt && product.flashSaleEndsAt > new Date());
    if (hasActiveDiscount) score += 0.8;
    // Rating boost (max +0.9).
    score += Math.min(product.avgRating, 5) * 0.18;
    // Review count boost (max +1.0).
    score += Math.min(product.reviewCount, 500) / 500;
    return { product, score };
  });
  scored.sort((a, b) => b.score - a.score);

  const ranked: CartRecommendationProductRow[] = scored
    .slice(0, limit)
    .map((s) => s.product);

  // ─── 6. Cold-start / top-up fallback (popular by reviewCount) ────────
  if (ranked.length < limit) {
    const usedIds = new Set([...excludeArr, ...ranked.map((p) => p.id)]);
    const fallback = await prisma.product.findMany({
      where: cartRecommendationWhere([...usedIds]),
      orderBy: [
        { reviewCount: "desc" },
        { avgRating: "desc" },
        { createdAt: "desc" },
      ],
      take: limit - ranked.length,
      include: cartRecommendationProductInclude(),
    });
    ranked.push(...fallback);
  }

  const data = await attachPublicProductVoucherPreviews(
    ranked.slice(0, limit).map(serializeCartRecommendationProduct),
    { userId },
  );

  return NextResponse.json({
    data,
    meta: {
      personalized: hasPersonalSignal,
      signal_breakdown: {
        purchased_brands: topBrandIds.length,
        viewed: viewIds.length,
        purchased_items: purchasedItems.length,
      },
    },
  });
}
