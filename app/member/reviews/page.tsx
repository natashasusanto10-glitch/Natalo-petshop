import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { Stars } from "@/components/StarRating";
import { ReviewableItemCard } from "@/components/ReviewableItemCard";
import { requireCustomerSession } from "@/lib/session-guards";

export default async function MemberReviewsPage() {
  const session = await requireCustomerSession();

  const reviewableItems = await prisma.orderItem.findMany({
    where: {
      order: { userId: session.sub, status: "DELIVERED" },
      reviews: { none: { status: { not: "DELETED" } } },
    },
    include: {
      product: { select: { id: true, slug: true, imageUrl: true } },
      order: { select: { orderNumber: true, createdAt: true } },
    },
    orderBy: { order: { createdAt: "desc" } },
    take: 50,
  });

  const myReviews = await prisma.review.findMany({
    where: {
      userId: session.sub,
      status: { not: "DELETED" },
    },
    include: {
      product: { select: { name: true, slug: true, imageUrl: true } },
      images: { orderBy: { position: "asc" }, take: 4 },
      reply: true,
    },
    orderBy: { createdAt: "desc" },
    take: 50,
  });

  return (
    <div className="min-h-screen bg-gray-50">
      <main className="mx-auto max-w-4xl space-y-8 px-4 py-5 md:py-8">
        <div>
          <p className="text-xs font-black uppercase tracking-[0.18em] text-natalo-600">
            Rating Produk
          </p>
          <h1 className="mt-1 text-2xl font-black tracking-tight text-gray-950">
            Ulasan Produk
          </h1>
          <p className="mt-1 max-w-xl text-sm leading-6 text-gray-500">
            Selesaikan rating dan cerita pengalamanmu untuk produk yang sudah sampai.
          </p>
        </div>

        <section>
          <h2 className="text-xl font-black text-gray-900">
            Yang menunggu review ({reviewableItems.length})
          </h2>
          <p className="mt-1 text-sm text-gray-500">
            Bagikan pengalaman kamu untuk membantu pembeli lain memilih produk yang tepat.
          </p>

          {reviewableItems.length === 0 ? (
            <div className="mt-5 rounded-2xl border border-gray-100 bg-white p-8 text-center">
              <span className="text-4xl" aria-hidden="true">✨</span>
              <p className="mt-3 text-sm text-gray-500">
                Tidak ada produk yang menunggu review. Pesanan yang sudah selesai akan muncul di sini.
              </p>
            </div>
          ) : (
            <div className="mt-5 space-y-3">
              {reviewableItems.map((item) => (
                <ReviewableItemCard
                  key={item.id}
                  item={{
                    ...item,
                    order: {
                      orderNumber: item.order.orderNumber,
                      createdAt: item.order.createdAt.toISOString(),
                    },
                  }}
                />
              ))}
            </div>
          )}
        </section>

        <section>
          <h2 className="text-xl font-black text-gray-900">
            Review yang sudah saya buat ({myReviews.length})
          </h2>

          {myReviews.length === 0 ? (
            <div className="mt-5 rounded-2xl border border-gray-100 bg-white p-8 text-center">
              <span className="text-4xl" aria-hidden="true">📝</span>
              <p className="mt-3 text-sm text-gray-500">Belum ada review.</p>
            </div>
          ) : (
            <div className="mt-5 space-y-3">
              {myReviews.map((review) => (
                <div
                  key={review.id}
                  className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm"
                >
                  <div className="flex items-start gap-3">
                    <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gray-100">
                      {review.product.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={review.product.imageUrl}
                          alt={review.product.name}
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
                        href={`/products/${review.product.slug}`}
                        className="line-clamp-1 text-sm font-semibold text-gray-900 hover:text-natalo-700"
                      >
                        {review.product.name}
                      </Link>
                      {review.variantLabel && (
                        <p className="text-xs text-natalo-600">
                          {review.variantLabel}
                        </p>
                      )}
                      <div className="mt-1 flex items-center gap-2">
                        <Stars rating={review.rating} size="sm" />
                        <span className="text-xs text-gray-400">
                          {new Date(review.createdAt).toLocaleDateString("id-ID")}
                        </span>
                        {review.status === "HIDDEN" && (
                          <span className="rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-bold text-red-600">
                            Disembunyikan
                          </span>
                        )}
                      </div>
                    </div>
                  </div>

                  {review.title && (
                    <p className="mt-3 text-sm font-semibold text-gray-900">
                      {review.title}
                    </p>
                  )}
                  {review.content && (
                    <p className="mt-1 whitespace-pre-line text-sm text-gray-700">
                      {review.content}
                    </p>
                  )}

                  {review.images.length > 0 && (
                    <div className="mt-2 flex gap-2">
                      {review.images.map((image) => (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          key={image.id}
                          src={image.imageUrl}
                          alt=""
                          className="h-14 w-14 rounded-lg object-cover"
                        />
                      ))}
                    </div>
                  )}

                  {review.reply && (
                    <div className="mt-3 rounded-lg bg-natalo-50 p-3">
                      <p className="text-xs font-bold text-natalo-800">
                        Balasan Penjual
                      </p>
                      <p className="mt-0.5 whitespace-pre-line text-sm text-gray-700">
                        {review.reply.content}
                      </p>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
