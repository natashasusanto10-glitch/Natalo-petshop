type Props = {
  soldCount?: number;
  avgRating: number;
  reviewCount: number;
  showRating: boolean;
};

export function ProductSalesMeta({ soldCount = 0, avgRating, reviewCount, showRating }: Props) {
  const hasSold = Number.isFinite(soldCount) && soldCount > 0;
  const hasRating = showRating && (avgRating > 0 || reviewCount > 0);
  if (!hasSold && !hasRating) return null;
  return (
    <div className="mt-1.5 flex flex-wrap items-center justify-between gap-x-2 gap-y-1 text-[11px] font-medium text-zinc-500">
      {hasRating && <span className="inline-flex items-center gap-1 whitespace-nowrap">
        <span className="text-[#FACC15]" aria-hidden="true">★</span>
        {avgRating > 0 ? avgRating.toFixed(1) : "Baru"}
        {reviewCount > 0 ? ` · ${reviewCount} ulasan` : ""}
      </span>}
      {hasSold && <span className="whitespace-nowrap" data-product-sold>{new Intl.NumberFormat("id-ID").format(Math.floor(soldCount))} terjual</span>}
    </div>
  );
}
