import { cartStockKey, type CartStockSnapshot } from "@/lib/cart-stock";

/**
 * Guardrail 1: buang item cart yang produk/variannya sudah tidak bisa
 * dibeli (nonaktif, dihapus, atau stok habis) sebelum masuk pertimbangan
 * notifikasi abandoned-cart.
 */
export function filterAvailableAbandonedCartItems<
  T extends { productId: string; variantId: string | null },
>(items: T[], snapshots: CartStockSnapshot[]): T[] {
  const availableKeys = new Set(
    snapshots
      .filter((snapshot) => snapshot.isAvailable && snapshot.availableStock > 0)
      .map((snapshot) => cartStockKey(snapshot)),
  );
  return items.filter((item) => availableKeys.has(cartStockKey(item)));
}

export type AbandonedCartCandidateSplit<T> = {
  toMark: T[];
  toNotify: T[];
};

/**
 * Guardrail 2: item yang baru pertama kali terlihat eligible (belum ada
 * abandonedCandidateAt) ditandai sebagai kandidat dulu, belum
 * dinotifikasi. Item yang sudah jadi kandidat sejak run sebelumnya (dan
 * masih ada/eligible) baru masuk batch notifikasi.
 */
export function splitAbandonedCartCandidates<
  T extends { abandonedCandidateAt: Date | null },
>(items: T[]): AbandonedCartCandidateSplit<T> {
  const toMark: T[] = [];
  const toNotify: T[] = [];
  for (const item of items) {
    if (item.abandonedCandidateAt == null) {
      toMark.push(item);
    } else {
      toNotify.push(item);
    }
  }
  return { toMark, toNotify };
}
