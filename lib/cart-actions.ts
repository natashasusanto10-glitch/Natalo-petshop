"use client";

import { cartSuccessToast, natToast } from "@/components/Toast";
import { loadCart, saveCart, type CartItem } from "@/lib/cart";

const SUCCESS_MESSAGE = "Produk berhasil dimasukkan ke keranjang";
const ERROR_MESSAGE = "Produk gagal dimasukkan ke keranjang, silakan coba lagi";

type AddCartOptions = {
  showToast?: boolean;
  successMessage?: string;
  errorMessage?: string;
};

type CartMergeIssue = {
  item: CartItem;
  reason: "invalid" | "out_of_stock" | "stock_limit";
};

type AddItemsToCartResult = {
  ok: boolean;
  addedCount: number;
  adjustedCount: number;
  skippedCount: number;
  issues: CartMergeIssue[];
};

function keyOf(item: Pick<CartItem, "productId" | "variantId">) {
  return `${item.productId}:${item.variantId ?? ""}`;
}

function withSubtotal(item: CartItem): CartItem {
  return {
    ...item,
    subtotal: item.price * item.quantity,
  };
}

export function showAddToCartSuccessToast(message = SUCCESS_MESSAGE) {
  cartSuccessToast(message);
}

export function showAddToCartErrorToast(message = ERROR_MESSAGE) {
  natToast(message, { kind: "err" });
}

export function addItemToCart(item: CartItem, options: AddCartOptions = {}) {
  const showToast = options.showToast ?? true;

  try {
    if (!item.productId || !item.name || item.quantity < 1 || item.price < 0) {
      throw new Error("Invalid cart item");
    }

    const cart = loadCart().map(withSubtotal);
    const key = keyOf(item);
    const existing = cart.find((cartItem) => keyOf(cartItem) === key);
    const stockCap = item.stock ?? existing?.stock ?? null;

    if (stockCap !== null && stockCap <= 0) {
      throw new Error("Out of stock");
    }

    if (existing) {
      const requestedQuantity = existing.quantity + item.quantity;
      const nextQuantity =
        stockCap !== null ? Math.min(stockCap, requestedQuantity) : requestedQuantity;

      if (nextQuantity <= existing.quantity) {
        throw new Error("Stock limit reached");
      }

      existing.quantity = nextQuantity;
      existing.subtotal = existing.price * existing.quantity;
      existing.stock = item.stock ?? existing.stock;
      existing.imageUrl = item.imageUrl ?? existing.imageUrl ?? null;
      existing.variantLabel = item.variantLabel ?? existing.variantLabel ?? null;
      existing.weightGram = item.weightGram || existing.weightGram;
      existing.name = item.name || existing.name;
      existing.price = item.price;
    } else {
      const nextItem = withSubtotal({
        ...item,
        variantId: item.variantId ?? null,
        variantLabel: item.variantLabel ?? null,
        imageUrl: item.imageUrl ?? null,
      });
      cart.push(nextItem);
    }

    saveCart(cart.map(withSubtotal));

    if (showToast) {
      showAddToCartSuccessToast(options.successMessage);
    }

    return { ok: true };
  } catch {
    if (showToast) {
      showAddToCartErrorToast(options.errorMessage);
    }
    return { ok: false };
  }
}

export function addItemsToCart(items: CartItem[], options: AddCartOptions = {}) {
  try {
    const cart = loadCart().map(withSubtotal);
    const issues: CartMergeIssue[] = [];
    let addedCount = 0;
    let adjustedCount = 0;

    for (const item of items) {
      if (!item.productId || !item.name || item.quantity < 1 || item.price < 0) {
        issues.push({ item, reason: "invalid" });
        continue;
      }

      const key = keyOf(item);
      const existing = cart.find((cartItem) => keyOf(cartItem) === key);
      const stockCap = item.stock ?? existing?.stock ?? null;

      if (stockCap !== null && stockCap <= 0) {
        issues.push({ item, reason: "out_of_stock" });
        continue;
      }

      if (existing) {
        const previousQuantity = existing.quantity;
        const requestedQuantity = existing.quantity + item.quantity;
        const nextQuantity =
          stockCap !== null ? Math.min(stockCap, requestedQuantity) : requestedQuantity;

        existing.stock = item.stock ?? existing.stock;
        existing.imageUrl = item.imageUrl ?? existing.imageUrl ?? null;
        existing.variantLabel = item.variantLabel ?? existing.variantLabel ?? null;
        existing.weightGram = item.weightGram || existing.weightGram;
        existing.name = item.name || existing.name;
        existing.price = item.price;

        if (nextQuantity <= previousQuantity) {
          existing.subtotal = existing.price * existing.quantity;
          issues.push({ item, reason: "stock_limit" });
          continue;
        }

        existing.quantity = nextQuantity;
        existing.subtotal = existing.price * existing.quantity;
        if (nextQuantity < requestedQuantity) adjustedCount += 1;
        else addedCount += 1;
        continue;
      }

      const nextQuantity =
        stockCap !== null ? Math.min(stockCap, item.quantity) : item.quantity;
      if (nextQuantity < item.quantity) adjustedCount += 1;
      else addedCount += 1;

      cart.push(
        withSubtotal({
          ...item,
          quantity: nextQuantity,
          variantId: item.variantId ?? null,
          variantLabel: item.variantLabel ?? null,
          imageUrl: item.imageUrl ?? null,
        }),
      );
    }

    if (addedCount === 0 && adjustedCount === 0) {
      throw new Error("No items added");
    }

    saveCart(cart.map(withSubtotal));

    if (options.showToast ?? true) {
      showAddToCartSuccessToast(options.successMessage);
    }

    return {
      ok: true,
      addedCount,
      adjustedCount,
      skippedCount: issues.length,
      issues,
    } satisfies AddItemsToCartResult;
  } catch {
    if (options.showToast ?? true) {
      showAddToCartErrorToast(options.errorMessage);
    }
    return {
      ok: false,
      addedCount: 0,
      adjustedCount: 0,
      skippedCount: items.length,
      issues: [],
    } satisfies AddItemsToCartResult;
  }
}
