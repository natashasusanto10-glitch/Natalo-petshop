import { prisma } from "@/lib/prisma";

export async function ReviewList({ productId }: { productId: string }) {
  const reviews = await prisma.review.findMany({
    where: { productId, isApproved: true },
    orderBy: { createdAt: "desc" },
    take: 20,
  }).catch(() => []);

  const avg = reviews.length
    ? (reviews.reduce((s, r) => s + r.rating, 0) / reviews.length).toFixed(1)
    : null;

  return (
    <div>
      {/* Summary */}
      <div className="flex items-center gap-4">
        <div className="text-center">
          <p className="text-4xl font-black text-gray-900">{avg ?? "–"}</p>
          <div className="mt-1 flex justify-center gap-0.5">
            {[1, 2, 3, 4, 5].map((s) => (
              <span key={s} className={parseFloat(avg ?? "0") >= s ? "text-orange-400" : "text-gray-200"}>★</span>
            ))}
          </div>
          <p className="mt-1 text-xs text-gray-400">{reviews.length} ulasan</p>
        </div>
      </div>

      {reviews.length === 0 ? (
        <p className="mt-6 text-sm text-gray-400">Belum ada ulasan untuk produk ini. Jadilah yang pertama!</p>
      ) : (
        <div className="mt-6 space-y-4">
          {reviews.map((review) => (
            <div key={review.id} className="rounded-2xl border border-gray-100 bg-gray-50 p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-semibold text-gray-900">{review.name}</p>
                  <div className="mt-0.5 flex gap-0.5 text-sm">
                    {[1, 2, 3, 4, 5].map((s) => (
                      <span key={s} className={review.rating >= s ? "text-orange-400" : "text-gray-200"}>★</span>
                    ))}
                  </div>
                </div>
                <span className="text-xs text-gray-400">
                  {new Date(review.createdAt).toLocaleDateString("id-ID", {
                    day: "numeric",
                    month: "short",
                    year: "numeric",
                  })}
                </span>
              </div>
              <p className="mt-2 text-sm leading-relaxed text-gray-700">{review.comment}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
