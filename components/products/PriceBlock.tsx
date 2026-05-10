import { FavoriteButton } from "@/components/FavoriteButton";

type Props = {
  productId: string;
  price: number;
  originalPrice?: number | null;
  discountPercent?: number | null;
  initialFavorited: boolean;
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
}: Props) {
  const hasDiscount =
    typeof originalPrice === "number" && originalPrice > price;

  return (
    <div className="flex items-start justify-between gap-3">
      <div className="min-w-0">
        <div className="flex items-baseline gap-1.5 leading-none text-gray-900">
          <span className="text-base font-bold md:text-lg">Rp</span>
          <span className="text-3xl font-black tracking-tight md:text-4xl">
            {formatNumberId(price)}
          </span>
        </div>
        {hasDiscount && (
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <span className="text-sm font-semibold text-gray-400 line-through">
              Rp{formatNumberId(originalPrice!)}
            </span>
            {typeof discountPercent === "number" && discountPercent > 0 && (
              <span className="rounded bg-red-50 px-1.5 py-0.5 text-xs font-black text-red-500">
                -{discountPercent}%
              </span>
            )}
          </div>
        )}
      </div>
      <FavoriteButton
        productId={productId}
        initialFavorited={initialFavorited}
        size="md"
      />
    </div>
  );
}
