/**
 * Purchase Affinity + Consumable Repurchase scoring engine.
 *
 * Dipakai di:
 *  - /api/recommendations/personalized (Home & Wishlist primary source)
 *  - /api/cart/recently-viewed (re-rank viewed history)
 *
 * ─── Konsep ────────────────────────────────────────────────────────
 *
 * Sebelumnya semua produk yang user pernah beli di-EXCLUDE dari
 * rekomendasi (assumption: durable goods). Ini bug untuk pet shop
 * yang consumable-heavy:
 *  - Royal Canin 7kg habis ~30 hari → user butuh refill → tapi
 *    di-exclude → user harus search manual → friction tinggi.
 *
 * Solusi: per-category flag `isConsumable` + `typicalRefillDays`:
 *  - Consumable (food, pasir, vitamin): BOLEH muncul lagi, boost
 *    score saat siklus refill terdekat.
 *  - Durable (kandang, mainan, aksesoris): TETAP exclude — user
 *    sudah punya, tidak butuh repurchase.
 *
 * ─── Bobot scoring ─────────────────────────────────────────────────
 *
 * Brand affinity:    × 3.0 (recency weighted)
 * Category affinity: × 2.5 (recency weighted)
 *
 * Repurchase boost (consumable produk yang waktunya refill):
 *  - "refill_due"      (~refillDays terkecil ~70-150% dari cycle): + 5.0
 *  - "refill_overdue"  (> 150% cycle): + 2.5 — overdue, may switched brand
 *  - "refill_too_soon" (< 70% cycle): exclude (user masih punya stok)
 *  - Durable purchased: exclude (already owned)
 *
 * Recency weight (untuk brand/category): 1 - (idx / total).
 */
import { prisma } from "@/lib/prisma";

export type PurchaseScoreMaps = {
  brandScores: Map<string, number>;
  categoryScores: Map<string, number>;
  /** Berapa item yang dipakai untuk scoring. 0 = no signal. */
  itemCount: number;
};

export type RepurchaseReason = "refill_due" | "refill_overdue";

export type RepurchaseSignal = {
  productId: string;
  reason: RepurchaseReason;
  /** Score boost yang di-add ke total score saat re-rank. */
  scoreBoost: number;
  /** Hari sejak terakhir beli. */
  daysSincePurchase: number;
  /** Expected refill cycle (untuk display di UI). */
  typicalRefillDays: number;
};

export type PurchaseSignals = {
  scores: PurchaseScoreMaps;
  /** Produk yang HARUS di-exclude (durable yang sudah dibeli atau
   *  consumable yang baru dibeli — masih punya stok). */
  excludeProductIds: Set<string>;
  /** Produk consumable yang sudah waktunya refill — bisa muncul lagi
   *  di rekomendasi dengan badge "Saatnya beli ulang". */
  repurchaseSignals: Map<string, RepurchaseSignal>;
};

const PURCHASE_LOOKBACK_ITEMS = 60;
const PURCHASE_BRAND_WEIGHT = 3.0;
const PURCHASE_CATEGORY_WEIGHT = 2.5;
const REPURCHASE_DUE_BOOST = 5.0;
const REPURCHASE_OVERDUE_BOOST = 2.5;
/** Threshold "terlalu cepat" — kalau hari sejak beli < cycle × 0.7,
 *  user masih punya stok, jangan rekomen ulang. */
const REPURCHASE_TOO_SOON_RATIO = 0.7;
/** Threshold "overdue" — kalau hari sejak beli > cycle × 1.5,
 *  user mungkin sudah ganti brand atau lupa beli. */
const REPURCHASE_OVERDUE_RATIO = 1.5;

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Backward-compat: simple brand/category scoring tanpa consumable
 * detection. Dipakai oleh endpoint yang tidak butuh repurchase signal.
 *
 * Untuk rekomendasi penuh (Home/Wishlist), pakai
 * `getPurchaseSignals()` instead.
 */
export async function getPurchaseAffinityScores(
  userId: string | null,
): Promise<PurchaseScoreMaps> {
  if (!userId) {
    return { brandScores: new Map(), categoryScores: new Map(), itemCount: 0 };
  }
  const signals = await getPurchaseSignals(userId);
  return signals.scores;
}

/**
 * Full purchase signal computation — brand/category scores + exclude
 * list + repurchase candidates.
 */
export async function getPurchaseSignals(
  userId: string | null,
): Promise<PurchaseSignals> {
  const empty: PurchaseSignals = {
    scores: {
      brandScores: new Map(),
      categoryScores: new Map(),
      itemCount: 0,
    },
    excludeProductIds: new Set(),
    repurchaseSignals: new Map(),
  };
  if (!userId) return empty;

  try {
    const items = await prisma.orderItem.findMany({
      where: {
        order: {
          userId,
          status: {
            in: ["PAID", "PROCESSING", "READY_FOR_PICKUP", "SHIPPED", "DELIVERED"],
          },
        },
      },
      orderBy: { id: "desc" },
      take: PURCHASE_LOOKBACK_ITEMS,
      select: {
        productId: true,
        order: { select: { createdAt: true } },
        product: {
          select: {
            brandId: true,
            categoryId: true,
            category: {
              select: { isConsumable: true, typicalRefillDays: true },
            },
          },
        },
      },
    });

    const brandScores = new Map<string, number>();
    const categoryScores = new Map<string, number>();
    const excludeProductIds = new Set<string>();
    const repurchaseSignals = new Map<string, RepurchaseSignal>();
    const total = Math.max(items.length, 1);
    const now = Date.now();

    items.forEach((item, idx) => {
      // ─── 1. Brand & category affinity ─────────────────────────────
      const recency = 1 - idx / total;
      if (item.product.brandId) {
        brandScores.set(
          item.product.brandId,
          (brandScores.get(item.product.brandId) ?? 0) +
            recency * PURCHASE_BRAND_WEIGHT,
        );
      }
      if (item.product.categoryId) {
        categoryScores.set(
          item.product.categoryId,
          (categoryScores.get(item.product.categoryId) ?? 0) +
            recency * PURCHASE_CATEGORY_WEIGHT,
        );
      }

      // ─── 2. Consumable repurchase detection ──────────────────────
      const cat = item.product.category;
      const isConsumable = cat?.isConsumable ?? false;
      const refillDays = cat?.typicalRefillDays ?? null;

      if (!isConsumable || !refillDays) {
        // Durable atau category tidak punya refill cycle — exclude.
        // User sudah punya, tidak butuh beli lagi.
        excludeProductIds.add(item.productId);
        return;
      }

      const daysSincePurchase =
        (now - item.order.createdAt.getTime()) / DAY_MS;

      // Kalau ada multiple purchases of same product, pakai yang
      // PALING BARU (loop iterates desc, jadi yang pertama match = newest).
      if (
        repurchaseSignals.has(item.productId) ||
        excludeProductIds.has(item.productId)
      ) {
        return;
      }

      if (daysSincePurchase < refillDays * REPURCHASE_TOO_SOON_RATIO) {
        // Terlalu cepat — user masih punya stok, exclude.
        excludeProductIds.add(item.productId);
        return;
      }

      if (daysSincePurchase <= refillDays * REPURCHASE_OVERDUE_RATIO) {
        // Sweet spot — saatnya refill.
        repurchaseSignals.set(item.productId, {
          productId: item.productId,
          reason: "refill_due",
          scoreBoost: REPURCHASE_DUE_BOOST,
          daysSincePurchase: Math.round(daysSincePurchase),
          typicalRefillDays: refillDays,
        });
      } else {
        // Overdue — user mungkin ganti brand atau lupa.
        repurchaseSignals.set(item.productId, {
          productId: item.productId,
          reason: "refill_overdue",
          scoreBoost: REPURCHASE_OVERDUE_BOOST,
          daysSincePurchase: Math.round(daysSincePurchase),
          typicalRefillDays: refillDays,
        });
      }
    });

    return {
      scores: { brandScores, categoryScores, itemCount: items.length },
      excludeProductIds,
      repurchaseSignals,
    };
  } catch {
    return empty;
  }
}

/**
 * Re-rank list produk berdasarkan purchase affinity score.
 *
 * Algoritma:
 *  1. Score = brandScore + categoryScore + repurchaseBoost (kalau ada).
 *  2. Sort by score DESC, tiebreak stable (preserve original order).
 *
 * No-op (return input) kalau no signal.
 */
export function rankByPurchaseAffinity<
  T extends { id?: string; brandId?: string | null; categoryId?: string | null },
>(
  products: T[],
  scores: PurchaseScoreMaps,
  repurchaseSignals?: Map<string, RepurchaseSignal>,
): T[] {
  if (scores.itemCount === 0 && (!repurchaseSignals || repurchaseSignals.size === 0)) {
    return products;
  }
  if (products.length <= 1) return products;

  const scored = products.map((product, originalIdx) => {
    let score = 0;
    if (product.brandId) {
      score += scores.brandScores.get(product.brandId) ?? 0;
    }
    if (product.categoryId) {
      score += scores.categoryScores.get(product.categoryId) ?? 0;
    }
    if (product.id && repurchaseSignals?.has(product.id)) {
      score += repurchaseSignals.get(product.id)!.scoreBoost;
    }
    return { product, score, originalIdx };
  });

  scored.sort((a, b) => {
    const diff = b.score - a.score;
    if (diff !== 0) return diff;
    return a.originalIdx - b.originalIdx;
  });

  return scored.map((s) => s.product);
}
