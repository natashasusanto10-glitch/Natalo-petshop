"use client";

import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import { loadCart, saveCart, type CartItem } from "@/lib/cart";

type OrderItem = { name: string; quantity: number; price: number; productId?: string };

type Props =
  // Bulk: re-add semua item dari sebuah order
  | {
      items: OrderItem[];
      orderNumber?: undefined;
      itemId?: undefined;
      variant?: undefined;
      children?: ReactNode;
      className?: string;
    }
  // Per-item: tombol kecil di kartu reorder
  | {
      orderNumber: string;
      itemId: string;
      items?: undefined;
      variant?: "ghost" | "primary";
      className?: string;
      children?: ReactNode;
    };

export function ReorderButton(props: Props) {
  const router = useRouter();

  async function handleReorder() {
    if ("items" in props && props.items) {
      const cart = loadCart();
      for (const item of props.items) {
        if (!item.productId) continue;
        const existing = cart.find((c) => c.productId === item.productId);
        if (existing) {
          existing.quantity += item.quantity;
        } else {
          cart.push({
            productId: item.productId,
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            weightGram: 500,
          });
        }
      }
      saveCart(cart);
      router.push("/cart");
      return;
    }

    // Per-item: ambil detail order item dari API
    if (props.orderNumber && props.itemId) {
      try {
        const res = await fetch(
          `/api/member/orders/${encodeURIComponent(props.orderNumber)}/items/${props.itemId}`
        );
        if (res.ok) {
          const item = (await res.json()) as CartItem;
          const cart = loadCart();
          const existing = cart.find(
            (c) => c.productId === item.productId && (c.variantId ?? null) === (item.variantId ?? null)
          );
          if (existing) {
            existing.quantity += item.quantity || 1;
          } else {
            cart.push({
              productId: item.productId,
              name: item.name,
              price: item.price,
              quantity: item.quantity || 1,
              weightGram: item.weightGram || 500,
              variantId: item.variantId ?? null,
              variantLabel: item.variantLabel ?? null,
            });
          }
          saveCart(cart);
        }
      } catch {
        /* ignore — endpoint optional */
      }
      router.push("/cart");
    }
  }

  const isGhost = "variant" in props && props.variant === "ghost";
  const baseClass = isGhost
    ? "rounded-full border border-blue-200 px-3 py-1.5 text-xs font-bold text-blue-600 hover:bg-blue-50"
    : "flex items-center gap-1.5 rounded-full border border-blue-300 px-4 py-2 text-xs font-bold text-blue-600 transition hover:bg-blue-50";

  return (
    <button
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
