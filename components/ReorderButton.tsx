"use client";

import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import {
  addItemsToCart,
  showAddToCartErrorToast,
  showAddToCartSuccessToast,
} from "@/lib/cart-actions";
import { saveCart, type CartItem } from "@/lib/cart";

type ReorderResultItem =
  | { status: "added"; item: CartItem }
  | { status: "adjusted"; item: CartItem; requestedQuantity?: number; availableStock?: number };

type ReorderSkippedItem = { status: "skipped"; reason: string; name?: string };

type ReorderApiResult = {
  added?: ReorderResultItem[];
  adjusted?: ReorderResultItem[];
  skipped?: ReorderSkippedItem[];
};

type BuyAgainAddedItem = {
  product_id: string;
  variant_id: string | null;
  product_name: string;
  variant_name: string | null;
  requested_qty: number;
  added_qty: number;
  available_stock: number;
  current_price: number;
  weight_gram?: number;
  image_url?: string | null;
};

type BuyAgainApiResult = {
  status?: "success" | "failed";
  message?: string;
  added_items?: BuyAgainAddedItem[];
  unavailable_items?: { reason: string; product_name?: string }[];
  cart?: {
    total_items?: number;
    items?: CartItem[];
  };
};

type Props =
  {
    orderId?: string;
    orderNumber?: string;
    itemId?: string;
    variant?: "ghost" | "primary";
    className?: string;
    children?: ReactNode;
  };

function normalizeItem(item: CartItem): CartItem {
  return {
    productId: item.productId,
    variantId: item.variantId ?? null,
    variantLabel: item.variantLabel ?? null,
    name: item.name,
    price: item.price,
    quantity: item.quantity || 1,
    subtotal: item.price * (item.quantity || 1),
    weightGram: item.weightGram || 500,
    stock: item.stock ?? null,
    imageUrl: item.imageUrl ?? null,
  };
}

function normalizeBuyAgainItem(item: BuyAgainAddedItem): CartItem {
  return {
    productId: String(item.product_id),
    variantId: item.variant_id ? String(item.variant_id) : null,
    variantLabel: item.variant_name ?? null,
    name: item.product_name,
    price: item.current_price,
    quantity: item.added_qty,
    subtotal: item.current_price * item.added_qty,
    weightGram: item.weight_gram ?? 500,
    stock: item.available_stock,
    imageUrl: item.image_url ?? null,
  };
}

export function ReorderButton(props: Props) {
  const router = useRouter();
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleReorder() {
    if (isSubmitting) return;
    setIsSubmitting(true);

    try {
      const endpoint = props.orderId
        ? `/orders/${encodeURIComponent(props.orderId)}/buy-again`
        : props.orderNumber
          ? `/api/orders/${encodeURIComponent(props.orderNumber)}/reorder`
          : null;

      if (!endpoint) throw new Error("Order tidak valid untuk reorder.");

      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(props.itemId ? { itemId: props.itemId } : {}),
      });
      const data = (await res.json()) as (ReorderApiResult & BuyAgainApiResult & { error?: string });
      if (!res.ok) throw new Error(data.error || "Gagal memproses reorder.");

      if (Array.isArray(data.added_items)) {
        const items = data.added_items.map(normalizeBuyAgainItem);
        if (items.length === 0) {
          const skippedReason = data.unavailable_items?.[0]?.reason;
          showAddToCartErrorToast(
            skippedReason || data.message || "Tidak ada item yang tersedia untuk dibeli lagi.",
          );
          return;
        }

        if (Array.isArray(data.cart?.items)) {
          saveCart(data.cart.items.map(normalizeItem));
          showAddToCartSuccessToast(data.message || "Produk berhasil dimasukkan ke keranjang");
        } else {
          const result = addItemsToCart(items, {
            successMessage: data.message || "Produk berhasil dimasukkan ke keranjang",
            errorMessage: "Item sudah mencapai batas stok di keranjang",
          });
          if (!result.ok) {
            showAddToCartErrorToast("Item sudah mencapai batas stok di keranjang");
            return;
          }
        }

        router.push("/cart");
        return;
      }

      const items = [...(data.added ?? []), ...(data.adjusted ?? [])]
        .map((entry) => ("item" in entry ? normalizeItem(entry.item) : null))
        .filter((item): item is CartItem => Boolean(item));

      if (items.length === 0) {
        const skippedReason = data.skipped?.[0]?.reason;
        showAddToCartErrorToast(skippedReason || "Tidak ada item yang tersedia untuk dibeli lagi.");
        return;
      }

      const adjustedCount = data.adjusted?.length ?? 0;
      const skippedCount = data.skipped?.length ?? 0;
      const successMessage =
        adjustedCount > 0 || skippedCount > 0
          ? "Item tersedia sudah dimasukkan ke keranjang"
          : "Produk berhasil dimasukkan ke keranjang";

      const result = addItemsToCart(items, {
        successMessage,
        errorMessage: "Item sudah mencapai batas stok di keranjang",
      });

      if (!result.ok) {
        showAddToCartErrorToast("Item sudah mencapai batas stok di keranjang");
        return;
      }

      router.push("/cart");
    } catch (error) {
      showAddToCartErrorToast(
        error instanceof Error ? error.message : "Gagal memproses reorder.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  const isGhost = props.variant === "ghost";
  const baseClass = isGhost
    ? "rounded-full border border-blue-200 px-3 py-1.5 text-xs font-bold text-blue-600 hover:bg-blue-50"
    : "flex items-center gap-1.5 rounded-full border border-blue-300 px-4 py-2 text-xs font-bold text-blue-600 transition hover:bg-blue-50";

  return (
    <button
      type="button"
      onClick={handleReorder}
      disabled={isSubmitting}
      aria-busy={isSubmitting}
      className={[
        baseClass,
        isSubmitting ? "cursor-wait opacity-70" : "",
        props.className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {isSubmitting ? (
        "Memproses..."
      ) : (
        props.children ?? (
        <>
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            className="h-3.5 w-3.5"
            aria-hidden="true"
          >
            <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
            <path d="M3 3v5h5" />
          </svg>
          Beli Lagi
        </>
        )
      )}
    </button>
  );
}
