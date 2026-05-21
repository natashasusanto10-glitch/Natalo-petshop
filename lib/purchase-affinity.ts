/**
 * Purchase Affinity scoring helpers — shared logic untuk re-rank produk
 * berdasarkan kebiasaan beli user.
 *
 * Dipakai di:
 *  - /api/recommendations/personalized (Home & Wishlist primary source)
 *  - /api/cart/recently-viewed (re-rank viewed history)
 *  - /api/products (opt-in via `personalized=true` flag, kalau ditambah nanti)
 *
 * Bobot scoring konsisten dengan endpoint personalized:
 *  - Purchase brand: × 3.0 (signal terkuat)
 *  - Purchase category: × 2.5
 *
 * Recency weight:
 *  weight = 1 - (index / total) → most recent purchase ≈ 1.0, oldest → ~0.
 */
import { prisma } from "@/lib/prisma";

export type PurchaseScoreMaps = {
  brandScores: Map<string, number>;
  categoryScores: Map<string, number>;
  /** Berapa item yang dipakai untuk scoring. 0 = no signal. */
  itemCount: number;
};

const PURCHASE_LOOKBACK_ITEMS = 60;
const PURCHASE_BRAND_WEIGHT = 3.0;
const PURCHASE_CATEGORY_WEIGHT = 2.5;

/**
 * Fetch order items dari user (last 60 yang statusnya revenue-eligible)
 * dan compute brand × 3.0, category × 2.5 dengan recency weight.
 *
 * Return empty maps kalau:
 *  - userId null (guest)
 *  - user belum punya order
 *  - error fetching (gracefully degrade)
 */
export async function getPurchaseAffinityScores(
  userId: string | null,
): Promise<PurchaseScoreMaps> {
  const empty: PurchaseScoreMaps = {
    brandScores: new Map(),
    categoryScores: new Map(),
    itemCount: 0,
  };
  if (!userId) return empty;

  try {
    const items = await prisma.orderItem.findMany({
      where: {
        order: {
          userId,
          status: { in: ["PAID", "PROCESSING", "SHIPPED", "DELIVERED"] },
        },
      },
      orderBy: { id: "desc" },
      take: PURCHASE_LOOKBACK_ITEMS,
      select: {
        product: { select: { brandId: true, categoryId: true } },
      },
    });

    const brandScores = new Map<string, number>();
    const categoryScores = new Map<string, number>();
    const total = Math.max(items.length, 1);

    items.forEach((item, idx) => {
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
    });

    return { brandScores, categoryScores, itemCount: items.length };
  } catch {
    return empty;
  }
}

/**
 * Re-rank list produk berdasarkan purchase affinity score.
 *
 * Algoritma:
 *  1. Untuk tiap produk, compute score = brandScore + categoryScore
 *     (default 0 kalau tidak match dengan top brands/categories user)
 *  2. Sort by score DESC
 *  3. Tiebreak: preserve original order index (stable sort)
 *
 * No-op (return input as-is) kalau scores kosong — guest user / no
 * purchase history.
 *
 * Generic T memungkinkan dipakai untuk berbagai shape produk asal punya
 * `brandId` + `categoryId` field.
 */
export function rankByPurchaseAffinity<
  T extends { brandId?: string | null; categoryId?: string | null },
>(products: T[], scores: PurchaseScoreMaps): T[] {
  if (scores.itemCount === 0) return products;
  if (products.length <= 1) return products;

  const scored = products.map((product, originalIdx) => {
    let score = 0;
    if (product.brandId) {
      score += scores.brandScores.get(product.brandId) ?? 0;
    }
    if (product.categoryId) {
      score += scores.categoryScores.get(product.categoryId) ?? 0;
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
