"use client";

import { FavoriteButton } from "@/components/FavoriteButton";
import { useProductDetailState } from "./ProductDetailState";

type Props = {
  productId: string;
  price: number;
  originalPrice?: number | null;
  discountPercent?: number | null;
  initialFavorited: boolean;
  showFavorite?: boolean;
};

function formatNumberId(n: number) {
  return new Intl.NumberFormat("id-ID").format(n);
}

export function PriceBlock({
  productId,
  price,
  originalPrice,
  discountPercent,
  initialFavorited,
  showFavorite = true,
}: Props) {
  const variant = useProductDetailState()?.variant;
  if (variant) {
    price = variant.price;
    originalPrice = null;
    discountPercent = null;
  }
  const hasDiscount =
    typeof originalPrice === "number" && originalPrice > price;

  return (
    <div className="flex items-start justify-between gap-3">
      <div className="min-w-0">
        <div className="flex flex-wrap items-baseline gap-x-2 gap-y-2">
          <span className={"text-2xl font-extrabold tracking-tight md:text-3xl " + (hasDiscount ? "text-rose-600" : "text-gray-900")}>
            Rp{formatNumberId(price)}
          </span>
          {hasDiscount && <>
            {typeof discountPercent === "number" && discountPercent > 0 && <span className="rounded bg-red-50 px-1.5 py-0.5 text-xs font-bold text-red-500">-{discountPercent}%</span>}
            <span className="text-xs text-gray-400 line-through">Rp{formatNumberId(originalPrice!)}</span>
          </>}
        </div>
      </div>
      {showFavorite && (
        <FavoriteButton
          productId={productId}
          initialFavorited={initialFavorited}
          size="md"
        />
      )}
    </div>
  );
}
