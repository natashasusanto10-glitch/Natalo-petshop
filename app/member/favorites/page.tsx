import { ProductCard } from "@/components/ProductCard";
import { ProductGrid } from "@/components/product/ProductGrid";
import { getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { LogoutButton } from "@/components/LogoutButton";
import { MemberNav } from "@/components/MemberNav";
import { FavoriteButton } from "@/components/FavoriteButton";
import { EmptyWishlist } from "@/components/LoadingEmptyStates";
import { requireCustomerSession } from "@/lib/session-guards";

export default async function MemberFavoritesPage() {
  const session = await requireCustomerSession("/member/favorites");

  const favorites = await prisma.favorite.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "desc" },
    include: {
      product: {
        include: { category: true },
      },
    },
  });

  const products = favorites.length ? await getProducts({ includeIds: favorites.map(({product}) => product.id), take: favorites.length, viewerId: session.sub }) : [];

  const byId = new Map(products.map(product => [product.id, product]));
  const orderedProducts = favorites.map(({ product }) => byId.get(product.id) ?? { ...product, brand: null, stock: 0, flashSaleEndsAt: product.flashSaleEndsAt?.toISOString() ?? null });

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-blue-500 px-4 pb-0 pt-4 md:pt-8">
        <div className="mx-auto max-w-4xl">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white/20 text-xl md:h-12 md:w-12 md:text-2xl">
                🐾
              </div>
              <div>
                <p className="text-xs text-blue-100">Member resmi</p>
                <p className="text-base font-black text-white md:text-lg">
                  Halo, {session?.name}!
                </p>
              </div>
            </div>
            <LogoutButton
              redirectTo="/member/login"
              className="border-white/30 text-white hover:border-white/60"
            />
          </div>
          <MemberNav />
        </div>
      </div>

      <main className="mx-auto max-w-4xl px-4 py-8">
        <h2 className="text-xl font-black text-gray-900">Produk Favorit</h2>
        <p className="mt-1 text-sm text-gray-500">
          {favorites.length} produk tersimpan
        </p>

        {favorites.length === 0 ? (
          <div className="mt-6 rounded-2xl border border-gray-100 bg-white">
            <EmptyWishlist />
          </div>
        ) : (
          <ProductGrid className="mt-5">
            {orderedProducts.map((product) => <ProductCard key={product.id} product={product} showCta={false} showRating
              imageAction={<div className="absolute right-3 top-3 z-20"><FavoriteButton productId={product.id} initialFavorited size="sm" /></div>}
            />)}
          </ProductGrid>
        )}
      </main>
    </div>
  );
}
