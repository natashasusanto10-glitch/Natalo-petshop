/**
 * Personalized Recommendations API — server-side scoring engine.
 *
 * Sumber signal:
 *  1. Client-side `viewed` query param (recently_viewed_store, last 20)
 *  2. Server-side user_product_views table (last 30, kalau user login)
 *  3. Server-side orderItem table (last 60, kalau user login) — VIA
 *     `lib/purchase-affinity.ts` yang juga handle consumable detection.
 *
 * Scoring (lihat juga lib/purchase-affinity.ts):
 *  - Purchase brand × 3.0 (recency weighted)
 *  - Purchase category × 2.5
 *  - View brand × 1.2
 *  - View category × 1.8
 *  - Repurchase due (consumable refill window) × +5.0 (paling tinggi!)
 *  - Repurchase overdue × +2.5
 *  - hasDiscount boost +0.8
 *  - rating boost × 0.18 (max +0.9)
 *  - reviewCount boost /500 (max +1.0)
 *
 * Exclusion (sudah handled di getPurchaseSignals):
 *  - Produk yang sudah viewed
 *  - Produk DURABLE yang sudah dibeli (kandang, mainan, dst)
 *  - Produk CONSUMABLE yang baru dibeli (< 70% siklus refill — masih
 *    punya stok)
 *  - Caller exclude IDs (mis. wishlist favorites)
 *
 * Produk consumable yang sudah waktunya refill (70% ~ 150% cycle) atau
 * overdue (> 150% cycle) BUKAN di-exclude — mereka muncul dengan
 * `repurchaseReason` metadata supaya Flutter bisa render badge
 * "Saatnya beli ulang".
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
import { getPurchaseSignals } from "@/lib/purchase-affinity";

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
  const callerExcludeIds = parseIds(searchParams.get("exclude"));
  const session = await getSession("CUSTOMER").catch(() => null);
  const userId = session?.sub ?? null;

  // ─── 1. Server-side view tracking ─────────────────────────────────────
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

  // ─── 2. Purchase signals (brand/category scores + repurchase) ─────────
  const purchaseSignals = await getPurchaseSignals(userId);

  // Merge view IDs (client + server, dedup, keep client order priority).
  const seenViewSet = new Set<string>();
  const viewIds: string[] = [];
  for (const id of [...clientViewIds, ...serverViewIds]) {
    if (seenViewSet.has(id)) continue;
    seenViewSet.add(id);
    viewIds.push(id);
  }

  // Exclude: viewed + durable purchased (dari purchaseSignals) + caller list.
  // Consumable yang waktunya refill TIDAK di-exclude — muncul di repurchase
  // candidates dengan boost.
  const excludeSet = new Set<string>([
    ...viewIds,
    ...purchaseSignals.excludeProductIds,
    ...callerExcludeIds,
  ]);

  // ─── 3. Fetch detail (brand + category) untuk viewed products ─────────
  let viewedDetails: { id: string; brandId: string | null; categoryId: string | null }[] = [];
  if (viewIds.length > 0) {
    viewedDetails = await prisma.product.findMany({
      where: { id: { in: viewIds } },
      select: { id: true, brandId: true, categoryId: true },
    });
  }

  const viewIndexMap = new Map(viewIds.map((id, idx) => [id, idx]));

  // ─── 4. Build combined brand & category score maps ────────────────────
  // Purchase scores sudah pre-computed di getPurchaseSignals.
  // Tambah view signals di atasnya.
  const brandScores: ScoreMap = new Map(purchaseSignals.scores.brandScores);
  const categoryScores: ScoreMap = new Map(purchaseSignals.scores.categoryScores);

  const viewN = viewIds.length;
  viewedDetails.forEach((row) => {
    const idx = viewIndexMap.get(row.id) ?? viewN;
    const recency = 1 - idx / Math.max(viewN, 1);
    addScore(brandScores, row.brandId, recency * 1.2);
    addScore(categoryScores, row.categoryId, recency * 1.8);
  });

  const topBrandIds = topNKeys(brandScores, 5);
  const topCategoryIds = topNKeys(categoryScores, 5);
  const hasPersonalSignal =
    topBrandIds.length > 0 ||
    topCategoryIds.length > 0 ||
    purchaseSignals.repurchaseSignals.size > 0;

  // ─── 5. Fetch candidate pool ─────────────────────────────────────────
  const excludeArr = [...excludeSet];
  const candidateMap = new Map<string, CartRecommendationProductRow>();

  // 5a. Repurchase candidates (consumable produk yang sudah waktunya refill).
  //     Fetched EXPLICITLY by ID supaya pasti masuk pool walaupun brand/cat
  //     mereka bukan top affinity.
  if (purchaseSignals.repurchaseSignals.size > 0) {
    const repurchaseIds = [...purchaseSignals.repurchaseSignals.keys()];
    const repurchaseProducts = await prisma.product.findMany({
      where: {
        AND: [
          { id: { in: repurchaseIds } },
          // Bypass excludeArr — repurchase candidates explicitly allowed.
          // Tapi tetap pakai cartRecommendationWhere base filter.
          cartRecommendationWhere([
            ...viewIds,
            ...callerExcludeIds,
          ]),
        ],
      },
      include: cartRecommendationProductInclude(),
    });
    for (const product of repurchaseProducts) {
      candidateMap.set(product.id, product);
    }
  }

  // 5b. Brand/category affinity candidates.
  if (hasPersonalSignal && (topBrandIds.length > 0 || topCategoryIds.length > 0)) {
    const affinityCandidates = await prisma.product.findMany({
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
    for (const product of affinityCandidates) {
      if (!candidateMap.has(product.id)) {
        candidateMap.set(product.id, product);
      }
    }
  }

  // ─── 6. Re-rank candidates by combined signal score ──────────────────
  const candidates = [...candidateMap.values()];
  const scored = candidates.map((product) => {
    let score = 0;
    score += brandScores.get(product.brandId ?? "") ?? 0;
    score += categoryScores.get(product.categoryId ?? "") ?? 0;
    // Repurchase boost (paling tinggi untuk consumable yang due).
    const repurchase = purchaseSignals.repurchaseSignals.get(product.id);
    if (repurchase) {
      score += repurchase.scoreBoost;
    }
    // Boost diskon (Promo Toko / Flash Sale aktif).
    const hasActiveDiscount =
      product.discountItems.length > 0 ||
      (product.flashSaleEndsAt && product.flashSaleEndsAt > new Date());
    if (hasActiveDiscount) score += 0.8;
    score += Math.min(product.avgRating, 5) * 0.18;
    score += Math.min(product.reviewCount, 500) / 500;
    return { product, score };
  });
  scored.sort((a, b) => b.score - a.score);

  const ranked: CartRecommendationProductRow[] = scored
    .slice(0, limit)
    .map((s) => s.product);

  // ─── 7. Cold-start / top-up fallback (popular by reviewCount) ────────
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

  // ─── 8. Serialize + attach repurchase metadata per produk ────────────
  const serialized = ranked.slice(0, limit).map((product) => {
    const base = serializeCartRecommendationProduct(product);
    const repurchase = purchaseSignals.repurchaseSignals.get(product.id);
    if (repurchase) {
      return {
        ...base,
        repurchase_reason: repurchase.reason,
        days_since_last_purchase: repurchase.daysSincePurchase,
        typical_refill_days: repurchase.typicalRefillDays,
      };
    }
    return base;
  });

  const data = await attachPublicProductVoucherPreviews(serialized, { userId });

  return NextResponse.json({
    data,
    meta: {
      personalized: hasPersonalSignal,
      signal_breakdown: {
        purchased_brands: topBrandIds.length,
        viewed: viewIds.length,
        purchased_items: purchaseSignals.scores.itemCount,
        repurchase_candidates: purchaseSignals.repurchaseSignals.size,
      },
    },
  });
}
