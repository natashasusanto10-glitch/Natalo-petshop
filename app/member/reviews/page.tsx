import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { LogoutButton } from "@/components/LogoutButton";
import { MemberNav } from "@/components/MemberNav";
import { Stars } from "@/components/StarRating";
import { ReviewableItemCard } from "@/components/ReviewableItemCard";
import Link from "next/link";

export default async function MemberReviewsPage() {
  const session = await getSession();
  if (!session) {
    return (
      <div className="p-8 text-center">
        <p>Silakan login dulu.</p>
        <Link href="/member/login" className="text-natalo-600 underline">Login</Link>
      </div>
    );
  }

  // Item yang BELUM direview (status order = DELIVERED, no aktif review)
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

  // Review yang sudah dibuat user (VISIBLE/HIDDEN)
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
      {/* Header */}
      <div className="bg-natalo-600 px-4 pb-0 pt-8">
        <div className="mx-auto max-w-4xl">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-white/20 text-2xl">
                🐾
              </div>
              <div>
                <p className="text-xs text-natalo-100">Member resmi</p>
                <p className="text-lg font-black text-white">Halo, {session.name}!</p>
              </div>
            </div>
            <LogoutButton redirectTo="/member/login" className="border-white/30 text-white hover:border-white/60" />
          </div>
          <MemberNav />
        </div>
      </div>

      <main className="mx-auto max-w-4xl px-4 py-8 space-y-10">
        {/* Yang menunggu review */}
        <section>
          <h2 className="text-xl font-black text-gray-900">
            Yang menunggu review ({reviewableItems.length})
          </h2>
          <p className="mt-1 text-sm text-gray-500">
            Bagikan pengalaman kamu — bantu pembeli lain memilih produk yang tepat.
          </p>

          {reviewableItems.length === 0 ? (
            <div className="mt-5 rounded-2xl border border-gray-100 bg-white p-8 text-center">
              <span className="text-4xl">✨</span>
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

        {/* Review saya */}
        <section>
          <h2 className="text-xl font-black text-gray-900">
            Review yang sudah saya buat ({myReviews.length})
          </h2>

          {myReviews.length === 0 ? (
            <div className="mt-5 rounded-2xl border border-gray-100 bg-white p-8 text-center">
              <span className="text-4xl">📝</span>
              <p className="mt-3 text-sm text-gray-500">Belum ada review.</p>
            </div>
          ) : (
            <div className="mt-5 space-y-3">
              {myReviews.map((r) => (
                <div
                  key={r.id}
                  className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm"
                >
                  <div className="flex items-start gap-3">
                    <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gray-100">
                      {r.product.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={r.product.imageUrl} alt={r.product.name} className="h-full w-full object-cover" />
                      ) : (
                        <div className="flex h-full items-center justify-center text-2xl">🐾</div>
                      )}
                    </div>
                    <div className="min-w-0 flex-1">
                      <Link
                        href={`/products/${r.product.slug}`}
                        className="line-clamp-1 text-sm font-semibold text-gray-900 hover:text-natalo-700"
                      >
                        {r.product.name}
                      </Link>
                      {r.variantLabel && (
                        <p className="text-xs text-natalo-600">{r.variantLabel}</p>
                      )}
                      <div className="mt-1 flex items-center gap-2">
                        <Stars rating={r.rating} size="sm" />
                        <span className="text-xs text-gray-400">
                          {new Date(r.createdAt).toLocaleDateString("id-ID")}
                        </span>
                        {r.status === "HIDDEN" && (
                          <span className="rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-bold text-red-600">
                            Disembunyikan
                          </span>
                        )}
                      </div>
                    </div>
                  </div>

                  {r.title && <p className="mt-3 text-sm font-semibold text-gray-900">{r.title}</p>}
                  {r.content && (
                    <p className="mt-1 text-sm text-gray-700 whitespace-pre-line">{r.content}</p>
                  )}

                  {r.images.length > 0 && (
                    <div className="mt-2 flex gap-2">
                      {r.images.map((img) => (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          key={img.id}
                          src={img.imageUrl}
                          alt=""
                          className="h-14 w-14 rounded-lg object-cover"
                        />
                      ))}
                    </div>
                  )}

                  {r.reply && (
                    <div className="mt-3 rounded-lg bg-natalo-50 p-3">
                      <p className="text-xs font-bold text-natalo-800">💬 Balasan Penjual</p>
                      <p className="mt-0.5 text-sm text-gray-700 whitespace-pre-line">{r.reply.content}</p>
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
