"use client";

import { useState } from "react";
import Link from "next/link";
import { ReviewFlow } from "@/components/review/ReviewFlow";
import { formatRupiah } from "@/lib/format";

type Item = {
  id: string;
  name: string;
  price: number;
  quantity: number;
  variantLabel: string | null;
  product: { id: string; slug: string; imageUrl: string | null };
  order: { orderNumber: string; createdAt: string };
};

export function ReviewableItemCard({ item }: { item: Item }) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <div className="flex flex-wrap items-center gap-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
        <div className="h-16 w-16 shrink-0 overflow-hidden rounded-lg bg-gray-100">
          {item.product.imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={item.product.imageUrl}
              alt={item.name}
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-2xl">
              🐾
            </div>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <Link
            href={`/products/${item.product.slug}`}
            className="line-clamp-2 text-sm font-semibold text-gray-900 hover:text-natalo-700"
          >
            {item.name}
          </Link>
          {item.variantLabel && (
            <p className="text-xs text-natalo-600">{item.variantLabel}</p>
          )}
          <p className="text-xs text-gray-400">
            {formatRupiah(item.price)} × {item.quantity} · Order{" "}
            {item.order.orderNumber}
          </p>
        </div>
        <button
          onClick={() => setOpen(true)}
          className="shrink-0 whitespace-nowrap rounded-full bg-natalo-600 px-5 py-2 text-sm font-bold text-white hover:bg-natalo-700"
        >
          ★ Beri Review
        </button>
      </div>

      {open && (
        <ReviewFlow
          orderNumber={item.order.orderNumber}
          preselectedItem={{
            orderItemId: item.id,
            productId: item.product.id,
            productName: item.name,
            productImage: item.product.imageUrl,
            variantLabel: item.variantLabel,
            quantity: item.quantity,
            reviewed: false,
          }}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}
