import type { CartItem } from "@/lib/cart";

export type CartStockInput = Pick<
  CartItem,
  "productId" | "variantId" | "variantLabel" | "name" | "quantity"
>;

export type CartStockSnapshot = {
  key: string;
  productId: string;
  variantId: string | null;
  variantLabel: string | null;
  name: string;
  requestedQuantity: number;
  availableStock: number;
  isAvailable: boolean;
  source: "product" | "variant";
  message?: string;
};

export type CartStockIssue = {
  key: string;
  productId: string;
  variantId: string | null;
  variantLabel: string | null;
  name: string;
  requestedQuantity: number;
  availableStock: number;
  action: "removed" | "reduced";
  message: string;
};

export type CartStockReconcileResult = {
  items: CartItem[];
  snapshots: CartStockSnapshot[];
  issues: CartStockIssue[];
  changed: boolean;
  ok: boolean;
};

export function cartStockKey(item: Pick<CartStockInput, "productId" | "variantId">) {
  return `${item.productId}:${item.variantId ?? ""}`;
}

export function reconcileCartItemsWithStock(
  items: CartItem[],
  snapshots: CartStockSnapshot[],
): CartStockReconcileResult {
  const snapshotMap = new Map(snapshots.map((snapshot) => [snapshot.key, snapshot]));
  const issues: CartStockIssue[] = [];
  let changed = false;

  const nextItems = items
    .map((item) => {
      const key = cartStockKey(item);
      const snapshot = snapshotMap.get(key);
      if (!snapshot) return item;

      const availableStock = Math.max(0, snapshot.availableStock);
      const baseItem = {
        ...item,
        stock: availableStock,
        subtotal: item.price * item.quantity,
      };

      if (!snapshot.isAvailable || availableStock <= 0) {
        changed = true;
        issues.push({
          key,
          productId: item.productId,
          variantId: item.variantId ?? null,
          variantLabel: item.variantLabel ?? null,
          name: item.name,
          requestedQuantity: item.quantity,
          availableStock,
          action: "removed",
          message:
            snapshot.message ||
            `${item.name}${item.variantLabel ? ` (${item.variantLabel})` : ""} sedang tidak tersedia.`,
        });
        return null;
      }

      if (item.quantity > availableStock) {
        changed = true;
        issues.push({
          key,
          productId: item.productId,
          variantId: item.variantId ?? null,
          variantLabel: item.variantLabel ?? null,
          name: item.name,
          requestedQuantity: item.quantity,
          availableStock,
          action: "reduced",
          message: `${item.name}${item.variantLabel ? ` (${item.variantLabel})` : ""} hanya tersedia ${availableStock} unit. Jumlah di keranjang disesuaikan dari ${item.quantity} ke ${availableStock}.`,
        });
        return {
          ...baseItem,
          quantity: availableStock,
          subtotal: item.price * availableStock,
        };
      }

      if (item.stock !== availableStock) {
        changed = true;
      }

      return baseItem;
    })
    .filter((item): item is CartItem => Boolean(item));

  return {
    items: nextItems,
    snapshots,
    issues,
    changed,
    ok: issues.length === 0,
  };
}
