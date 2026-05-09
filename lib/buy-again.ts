import type {
  ReorderAdjustedResult,
  ReorderCartItem,
  ReorderResult,
  ReorderSkippedResult,
} from "@/lib/reorder";
import type { CartItem } from "@/lib/cart";

export type BuyAgainCandidate = {
  item: ReorderCartItem;
  requestedQty: number;
  availableStock: number;
};

export type BuyAgainAddedItem = {
  product_id: string;
  variant_id: string | null;
  product_name: string;
  variant_name: string | null;
  requested_qty: number;
  added_qty: number;
  available_stock: number;
  current_price: number;
  weight_gram: number;
  image_url: string | null;
};

export type BuyAgainUnavailableItem = {
  product_id: string;
  variant_id: string | null;
  product_name: string;
  variant_name: string | null;
  reason: string;
  available_stock?: number;
};

export type BuyAgainResponse = {
  status: "success" | "failed";
  message: string;
  added_items: BuyAgainAddedItem[];
  unavailable_items: BuyAgainUnavailableItem[];
  cart?: {
    total_items: number;
    items?: CartItem[];
  };
};

function cleanReason(reason: string) {
  return reason.replace(/\.+$/, "");
}

export function getBuyAgainCandidates(result: ReorderResult): BuyAgainCandidate[] {
  return [
    ...result.added.map((entry) => ({
      item: entry.item,
      requestedQty: entry.item.quantity,
      availableStock: entry.item.stock,
    })),
    ...result.adjusted.map((entry: ReorderAdjustedResult) => ({
      item: entry.item,
      requestedQty: entry.requestedQuantity,
      availableStock: entry.availableStock,
    })),
  ];
}

export function toBuyAgainAddedItem(
  candidate: BuyAgainCandidate,
  addedQty: number,
): BuyAgainAddedItem {
  return {
    product_id: candidate.item.productId,
    variant_id: candidate.item.variantId,
    product_name: candidate.item.name,
    variant_name: candidate.item.variantLabel,
    requested_qty: candidate.requestedQty,
    added_qty: addedQty,
    available_stock: candidate.availableStock,
    current_price: candidate.item.price,
    weight_gram: candidate.item.weightGram,
    image_url: candidate.item.imageUrl,
  };
}

export function skippedToUnavailable(
  skipped: ReorderSkippedResult,
): BuyAgainUnavailableItem {
  return {
    product_id: skipped.productId,
    variant_id: skipped.variantId,
    product_name: skipped.name,
    variant_name: skipped.variantLabel,
    reason: cleanReason(skipped.reason),
    available_stock: skipped.availableStock,
  };
}

export function candidateToUnavailable(
  candidate: BuyAgainCandidate,
  reason: string,
): BuyAgainUnavailableItem {
  return {
    product_id: candidate.item.productId,
    variant_id: candidate.item.variantId,
    product_name: candidate.item.name,
    variant_name: candidate.item.variantLabel,
    reason: cleanReason(reason),
    available_stock: candidate.availableStock,
  };
}

export function buildBuyAgainResponse(
  addedItems: BuyAgainAddedItem[],
  unavailableItems: BuyAgainUnavailableItem[],
  totalItems: number,
  cartItems?: CartItem[],
): BuyAgainResponse {
  const hasAdded = addedItems.length > 0;
  const hasUnavailable = unavailableItems.length > 0;
  const message = hasAdded
    ? hasUnavailable
      ? "Beberapa produk berhasil ditambahkan ke keranjang."
      : "Produk berhasil ditambahkan ke keranjang."
    : "Tidak ada produk yang tersedia untuk dibeli lagi.";

  return {
    status: hasAdded ? "success" : "failed",
    message,
    added_items: addedItems,
    unavailable_items: unavailableItems,
    ...(hasAdded
      ? {
          cart: {
            total_items: totalItems,
            ...(cartItems ? { items: cartItems } : {}),
          },
        }
      : {}),
  };
}
