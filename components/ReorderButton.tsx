"use client";

import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import { addItemsToCart, showAddToCartErrorToast } from "@/lib/cart-actions";
import type { CartItem } from "@/lib/cart";

type OrderItem = {
  name: string;
  quantity: number;
  price: number;
  productId?: string;
  variantId?: string | null;
  variantLabel?: string | null;
  imageUrl?: string | null;
  weightGram?: number | null;
};

type ReorderResultItem =
  | { status: "added"; item: CartItem }
  | { status: "adjusted"; item: CartItem }
  | { status: "skipped"; reason: string };

type ReorderApiResult = {
  added?: ReorderResultItem[];
  adjusted?: ReorderResultItem[];
  skipped?: ReorderResultItem[];
};

type Props =
  | {
      orderNumber: string;
      itemId?: string;
      items?: undefined;
      variant?: "ghost" | "primary";
      className?: string;
      children?: ReactNode;
    }
  | {
      items: OrderItem[];
      orderNumber?: undefined;
      itemId?: undefined;
      variant?: undefined;
      children?: ReactNode;
      className?: string;
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

export function ReorderButton(props: Props) {
  const router = useRouter();

  async function handleReorder() {
    if (props.orderNumber) {
      try {
        const res = await fetch(`/api/orders/${encodeURIComponent(props.orderNumber)}/reorder`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(props.itemId ? { itemId: props.itemId } : {}),
        });
        const data = (await res.json()) as ReorderApiResult & { error?: string };
        if (!res.ok) throw new Error(data.error || "Gagal memproses reorder.");

        const items = [...(data.added ?? []), ...(data.adjusted ?? [])]
          .map((entry) => ("item" in entry ? normalizeItem(entry.item) : null))
          .filter((item): item is CartItem => Boolean(item));

        const result = addItemsToCart(items, {
          successMessage: "Produk berhasil dimasukkan ke keranjang",
        });
        if (result.ok) router.push("/cart");
        return;
      } catch {
        showAddToCartErrorToast();
        return;
      }
    }

    if (props.items) {
      const items = props.items
        .filter((item) => item.productId)
        .map((item) =>
          normalizeItem({
            productId: item.productId!,
            variantId: item.variantId ?? null,
            variantLabel: item.variantLabel ?? null,
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            subtotal: item.price * item.quantity,
            weightGram: item.weightGram ?? 500,
            imageUrl: item.imageUrl ?? null,
          }),
        );
      const result = addItemsToCart(items);
      if (result.ok) router.push("/cart");
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
      className={[baseClass, props.className].filter(Boolean).join(" ")}
    >
      {props.children ?? (
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
      )}
    </button>
  );
}
