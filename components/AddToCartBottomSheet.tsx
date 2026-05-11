"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { BottomSheet } from "@/components/BottomSheet";
import { cartSuccessToast } from "@/components/Toast";
import { addItemToCart, showAddToCartErrorToast } from "@/lib/cart-actions";
import type { CartItem } from "@/lib/cart";
import { formatRupiah } from "@/lib/format";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { hapticError, hapticSuccess, hapticTap } from "@/lib/native/haptics";

type AddToCartSheetItem = Omit<CartItem, "quantity" | "subtotal"> & {
  minimumQuantity?: number | null;
};

type Props = {
  open: boolean;
  item: AddToCartSheetItem | null;
  onClose: () => void;
  onAdded?: () => void;
};

export function AddToCartBottomSheet({ open, item, onClose, onAdded }: Props) {
  const minimumQuantity = Math.max(1, Number(item?.minimumQuantity ?? 1) || 1);
  const stock = item?.stock ?? null;
  const maxQuantity = stock !== null ? Math.max(0, stock) : null;
  const initialQuantity = Math.max(
    1,
    maxQuantity !== null ? Math.min(maxQuantity || 1, minimumQuantity) : minimumQuantity,
  );
  const [quantity, setQuantity] = useState(initialQuantity);

  useEffect(() => {
    if (!open) return;
    setQuantity(initialQuantity);
  }, [initialQuantity, open]);

  const subtotal = useMemo(() => (item ? item.price * quantity : 0), [item, quantity]);
  const belowMinimum = quantity < minimumQuantity;
  const outOfStock = maxQuantity !== null && maxQuantity <= 0;
  const canIncrease = maxQuantity === null || quantity < maxQuantity;
  const canSubmit = !!item && !outOfStock && !belowMinimum;

  function decrease() {
    setQuantity((value) => {
      if (value <= 1) return value;
      hapticTap();
      return value - 1;
    });
  }

  function increase() {
    setQuantity((value) => {
      const next = value + 1;
      const capped = maxQuantity !== null ? Math.min(maxQuantity, next) : next;
      if (capped !== value) hapticTap();
      return capped;
    });
  }

  function submit() {
    if (!item || !canSubmit) return;

    const result = addItemToCart(
      {
        ...item,
        quantity,
        subtotal,
      },
      { showToast: false },
    );

    if (!result.ok) {
      hapticError();
      showAddToCartErrorToast();
      return;
    }

    hapticSuccess();
    onClose();
    onAdded?.();
    cartSuccessToast();
  }

  return (
    <BottomSheet
      open={open}
      onClose={onClose}
      title="Tambah ke Keranjang"
      footer={
        <button
          type="button"
          onClick={submit}
          disabled={!canSubmit}
          className="w-full rounded-full bg-natalo-600 py-3 text-sm font-black text-white transition-all duration-100 hover:bg-natalo-700 active:scale-95 disabled:cursor-not-allowed disabled:bg-gray-300 disabled:active:scale-100"
        >
          Tambah ke Keranjang
        </button>
      }
    >
      {item && (
        <div className="space-y-5">
          <div className="flex gap-4">
            <div className="relative h-24 w-24 shrink-0 overflow-hidden rounded-2xl bg-gray-100">
              {item.imageUrl ? (
                <Image
                  src={item.imageUrl}
                  alt={item.name}
                  fill
                  sizes="96px"
                  placeholder="blur"
                  blurDataURL={IMAGE_BLUR_GRAY}
                  className="object-cover"
                />
              ) : (
                <div className="flex h-full items-center justify-center text-xs font-bold text-gray-300">
                  No image
                </div>
              )}
            </div>
            <div className="min-w-0 flex-1">
              <h3 className="line-clamp-2 text-sm font-extrabold leading-snug text-gray-900">
                {item.name}
              </h3>
              {item.variantLabel && (
                <p className="mt-1 text-xs font-semibold text-gray-500">{item.variantLabel}</p>
              )}
              <p className="mt-2 text-xl font-black text-natalo-600">
                {formatRupiah(item.price)}
              </p>
              <p className="mt-1 text-xs font-bold text-gray-400">
                {outOfStock
                  ? "Stok habis"
                  : stock !== null
                    ? `Stok ${stock}`
                    : "Stok tersedia"}
              </p>
            </div>
          </div>

          <div className="flex items-center justify-between gap-4 rounded-2xl border border-gray-100 bg-gray-50 p-4">
            <div>
              <p className="text-sm font-black text-gray-900">Jumlah</p>
              <p className="mt-0.5 text-xs font-semibold text-gray-400">
                Subtotal {formatRupiah(subtotal)}
              </p>
            </div>
            <div className="flex h-11 items-center overflow-hidden rounded-full border border-gray-200 bg-white">
              <button
                type="button"
                onClick={decrease}
                disabled={quantity <= 1}
                aria-label="Kurangi jumlah"
                className="grid h-11 w-11 place-items-center text-lg font-black text-natalo-600 transition-transform duration-75 active:scale-90 disabled:text-gray-300 disabled:active:scale-100"
              >
                -
              </button>
              <span className="min-w-10 px-2 text-center text-sm font-black text-gray-900">
                {quantity}
              </span>
              <button
                type="button"
                onClick={increase}
                disabled={!canIncrease}
                aria-label="Tambah jumlah"
                className="grid h-11 w-11 place-items-center text-lg font-black text-natalo-600 transition-transform duration-75 active:scale-90 disabled:text-gray-300 disabled:active:scale-100"
              >
                +
              </button>
            </div>
          </div>

          {minimumQuantity > 1 && belowMinimum && (
            <p className="rounded-2xl bg-red-50 p-3 text-xs font-bold leading-relaxed text-red-600">
              Produk ini memiliki minimum jumlah pembelian sebesar {minimumQuantity}. Mohon
              penuhi syarat jumlah minimum sebelum checkout
            </p>
          )}
        </div>
      )}
    </BottomSheet>
  );
}
