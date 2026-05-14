type Props = {
  avgRating: number;
  reviewCount: number;
  photoReviewCount?: number;
  soldCount?: number;
};

function formatSold(n: number) {
  return `Terjual ${n}`;
}

export function SocialProofRow({
  avgRating,
  reviewCount,
  photoReviewCount,
  soldCount,
}: Props) {
  const showRating = avgRating > 0 && reviewCount > 0;
  const showPhotoReview =
    typeof photoReviewCount === "number" && photoReviewCount > 0;
  const showSold = typeof soldCount === "number" && soldCount > 0;

  // Tidak tampilkan apa pun bila belum ada data sama sekali.
  if (!showRating && !showPhotoReview && !showSold) return null;

  return (
    <div className="mt-3 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-xs font-bold text-gray-500">
      {showRating && (
        <span className="inline-flex items-center gap-1 text-gray-700">
          <svg
            viewBox="0 0 24 24"
            className="h-3.5 w-3.5 fill-amber-400"
            aria-hidden="true"
          >
            <path d="M12 2.5l2.92 6.31 6.93.66-5.25 4.79 1.6 6.78L12 17.6l-6.2 3.44 1.6-6.78L2.15 9.47l6.93-.66L12 2.5z" />
          </svg>
          <span className="font-extrabold text-gray-900">
            {avgRating.toFixed(1)}
          </span>
          <span className="text-gray-400">({reviewCount})</span>
        </span>
      )}
      {showPhotoReview && (
        <>
          {showRating && (
            <span aria-hidden className="text-gray-300">
              •
            </span>
          )}
          <span className="font-extrabold text-natalo-600">
            {photoReviewCount} Foto ulasan
          </span>
        </>
      )}
      {showSold && (
        <>
          {(showRating || showPhotoReview) && (
            <span aria-hidden className="text-gray-300">
              •
            </span>
          )}
          <span>{formatSold(soldCount)}</span>
        </>
      )}
    </div>
  );
}
