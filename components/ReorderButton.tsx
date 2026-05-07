"use client";

import { useRouter } from "next/navigation";

type OrderItem = { name: string; quantity: number; price: number; productId?: string };

function getCart() {
  try { return JSON.parse(localStorage.getItem("cart") ?? "[]"); } catch { return []; }
}

export function ReorderButton({ items }: { items: OrderItem[] }) {
  const router = useRouter();

  function handleReorder() {
    const cart = getCart();
    for (const item of items) {
      if (!item.productId) continue;
      const existing = cart.find((c: { productId: string }) => c.productId === item.productId);
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
    localStorage.setItem("cart", JSON.stringify(cart));
    window.dispatchEvent(new Event("cart-updated"));
    router.push("/cart");
  }

  return (
    <button
      onClick={handleReorder}
      className="flex items-center gap-1.5 rounded-full border border-orange-300 px-4 py-2 text-xs font-bold text-orange-600 transition hover:bg-orange-50"
    >
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-3.5 w-3.5">
        <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
        <path d="M3 3v5h5" />
      </svg>
      Beli Lagi
    </button>
  );
}
