"use client";

import { cartSuccessToast, natToast } from "@/components/Toast";
import { loadCart, saveCart, type CartItem } from "@/lib/cart";

const SUCCESS_MESSAGE = "Dimasukkan ke Keranjang";
const ERROR_MESSAGE = "Produk gagal dimasukkan ke keranjang, silakan coba lagi";

type AddCartOptions = {
  showToast?: boolean;
  successMessage?: string;
  errorMessage?: string;
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
  let changed = false;

  try {
    for (const item of items) {
      const result = addItemToCart(item, { ...options, showToast: false });
      if (result.ok) changed = true;
    }

    if (!changed) {
      throw new Error("No items added");
    }

    if (options.showToast ?? true) {
      showAddToCartSuccessToast(options.successMessage);
    }

    return { ok: true };
  } catch {
    if (options.showToast ?? true) {
      showAddToCartErrorToast(options.errorMessage);
    }
    return { ok: false };
  }
}
