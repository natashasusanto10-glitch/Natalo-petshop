import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { LogoutButton } from "@/components/LogoutButton";
import { MemberNav } from "@/components/MemberNav";
import { FavoriteButton } from "@/components/FavoriteButton";
import { QuickAddToCart } from "@/components/QuickAddToCart";
import { EmptyWishlist } from "@/components/LoadingEmptyStates";
import Link from "next/link";

export default async function MemberFavoritesPage() {
  const session = await getSession("CUSTOMER");

  const favorites = session
    ? await prisma.favorite.findMany({
        where: { userId: session.sub },
        orderBy: { createdAt: "desc" },
        include: {
          product: {
            include: { category: true },
          },
        },
      })
    : [];

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-orange-500 px-4 pb-0 pt-4 md:pt-8">
        <div className="mx-auto max-w-4xl">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white/20 text-xl md:h-12 md:w-12 md:text-2xl">
                🐾
              </div>
              <div>
                <p className="text-xs text-orange-100">Member resmi</p>
                <p className="text-base font-black text-white md:text-lg">Halo, {session?.name}!</p>
              </div>
            </div>
            <LogoutButton redirectTo="/member/login" className="border-white/30 text-white hover:border-white/60" />
          </div>
          <MemberNav />
        </div>
      </div>

      <main className="mx-auto max-w-4xl px-4 py-8">
        <h2 className="text-xl font-black text-gray-900">Produk Favorit</h2>
        <p className="mt-1 text-sm text-gray-500">{favorites.length} produk tersimpan</p>

        {favorites.length === 0 ? (
          <div className="mt-6 rounded-2xl border border-gray-100 bg-white">
            <EmptyWishlist />
          </div>
        ) : (
          <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {favorites.map(({ product }) => {
              const hasDiscount =
                product.discountPrice !== null && product.discountPrice < product.price;
              const displayPrice = hasDiscount ? product.discountPrice! : product.price;
              const isUnavailable = !product.isActive;

              return (
                <div
                  key={product.id}
                  className={`group overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm transition hover:shadow ${
                    isUnavailable ? "opacity-70" : ""
                  }`}
                >
                  <Link href={`/products/${product.slug}`} className="block">
                    <div className="relative aspect-square bg-gray-50">
                      {product.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={product.imageUrl}
                          alt={product.name}
                          className={`h-full w-full object-cover transition ${
                            isUnavailable ? "grayscale" : "group-hover:scale-105"
                          }`}
                        />
                      ) : (
                        <div className="flex h-full items-center justify-center text-5xl text-gray-200">
                          🐾
                        </div>
                      )}
                      {/* Badge */}
                      {isUnavailable ? (
                        <span className="absolute left-3 top-3 rounded-full bg-gray-700 px-2 py-0.5 text-xs font-bold text-white">
                          Tidak tersedia
                        </span>
                      ) : hasDiscount ? (
                        <span className="absolute left-3 top-3 rounded-full bg-red-500 px-2 py-0.5 text-xs font-bold text-white">
                          Diskon
                        </span>
                      ) : null}
                    </div>
                  </Link>

                  <div className="p-4">
                    {product.category && (
                      <p className="text-xs font-semibold text-natalo-600">
                        {product.category.name}
                      </p>
                    )}
                    <Link href={`/products/${product.slug}`}>
                      <p className="mt-1 font-semibold text-gray-900 leading-snug line-clamp-2 hover:text-natalo-700">
                        {product.name}
                      </p>
                    </Link>

                    <div className="mt-3 flex items-center justify-between gap-2">
                      <div>
                        <p className="font-bold text-gray-900">
                          {product.hasVariants
                            ? `Mulai ${formatRupiah(displayPrice)}`
                            : formatRupiah(displayPrice)}
                        </p>
                        {hasDiscount && !product.hasVariants && (
                          <p className="text-xs text-gray-400 line-through">
                            {formatRupiah(product.price)}
                          </p>
                        )}
                      </div>
                      <FavoriteButton productId={product.id} initialFavorited={true} size="sm" />
                    </div>

                    <div className="mt-3">
                      <QuickAddToCart product={product} />
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}
