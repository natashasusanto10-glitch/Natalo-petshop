import Image from "next/image";
import Link from "next/link";
import { StoreProduct } from "@/lib/products";
import { formatRupiah } from "@/lib/format";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { ProductCardCta } from "./ProductCardCta";

type Props = {
  product: StoreProduct;
  priority?: boolean;
  isFavorited?: boolean;
  variant?: "default" | "compact";
};

export function ProductCard({
  product,
  priority = false,
  isFavorited: _isFavorited,
  variant = "default",
}: Props) {
  const memberPrice = product.memberPrice ?? null;
  const discountPrice = product.discountPrice ?? null;
  const displayPrice = memberPrice ?? discountPrice ?? product.price;
  const hasMarkdown =
    (memberPrice !== null && memberPrice < product.price) ||
    (discountPrice !== null && discountPrice < product.price);
  const isCompact = variant === "compact";
  const outOfStock = product.stock <= 0;
  const productHref = `/products/${product.slug}`;
  const discountPercent = hasMarkdown
    ? Math.max(1, Math.round(((product.price - displayPrice) / product.price) * 100))
    : 0;

  if (isCompact) {
    return (
      <div className="group relative flex min-w-0 flex-col overflow-hidden rounded-2xl border border-[#f0f0f0] bg-white p-3 transition active:opacity-90 sm:hover:shadow-lg">
        <Link href={productHref} className="flex min-w-0 flex-1 flex-col">
          <div
            className="relative aspect-square max-h-[160px] w-full overflow-hidden rounded-t-xl bg-gray-100"
            style={{ viewTransitionName: `nat-prod-${product.slug}` }}
          >
            {product.imageUrl ? (
              <Image
                src={product.imageUrl}
                alt={product.name}
                fill
                priority={priority}
                placeholder="blur"
                blurDataURL={IMAGE_BLUR_GRAY}
                sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 16vw"
                className="object-cover transition group-hover:scale-105"
              />
            ) : (
              <div className="flex h-full items-center justify-center text-4xl text-gray-300">🐾</div>
            )}

            <span
              className={`absolute left-2 top-2 rounded-full px-2 py-0.5 text-[10px] font-bold ${
                outOfStock
                  ? "bg-gray-900/75 text-white"
                  : "bg-emerald-500 text-white"
              }`}
            >
              {outOfStock ? "Habis" : "Tersedia"}
            </span>
          </div>

          <div className="flex min-w-0 flex-1 flex-col pt-3">
            {/* Nama produk — max 2 baris, deskripsi panjang TIDAK ada di card
                (lihat detail produk). */}
            <h3 className="line-clamp-2 min-h-[2.5rem] text-sm font-semibold leading-snug text-[#222]">
              {product.name}
            </h3>

            <div className="mt-1.5 flex items-center gap-0.5 text-[11px] text-gray-500">
              <span className="text-amber-400">★</span>
              <span className="font-semibold text-gray-700">
                {product.avgRating > 0 ? product.avgRating.toFixed(1) : "Baru"}
              </span>
            </div>

            <div className="mt-2">
              <p className="text-base font-black leading-tight text-[#1E5FBF]">
                {formatRupiah(displayPrice)}
              </p>
              {hasMarkdown && (
                <div className="mt-1 flex flex-wrap items-center gap-1.5">
                  <span className="text-xs text-gray-400 line-through">
                    {formatRupiah(product.price)}
                  </span>
                  <span className="rounded-md bg-[#FEE2E2] px-1.5 py-0.5 text-[11px] font-bold text-red-600">
                    {discountPercent}%
                  </span>
                </div>
              )}
            </div>
          </div>
        </Link>

        {/* CTA kecil — di luar Link untuk hindari nested-interactive.
            + Keranjang untuk produk single-variant, Pilih Varian untuk multi-
            variant (link ke detail), Habis disabled saat stok kosong. */}
        <div className="mt-2">
          <ProductCardCta
            productId={product.id}
            slug={product.slug}
            name={product.name}
            price={displayPrice}
            imageUrl={product.imageUrl}
            weightGram={product.weightGram}
            stock={product.stock}
            hasVariants={product.hasVariants}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="group relative flex flex-col overflow-hidden rounded-2xl bg-gray-50 transition hover:shadow-md">
      <Link href={`/products/${product.slug}`} className="flex flex-1 flex-col">
        {/* Image area */}
        <div
          className="relative aspect-square bg-gray-100"
          style={{ viewTransitionName: `nat-prod-${product.slug}` }}
        >
          {product.imageUrl ? (
            <Image
              src={product.imageUrl}
              alt={product.name}
              fill
              priority={priority}
              placeholder="blur"
              blurDataURL={IMAGE_BLUR_GRAY}
              sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw"
              className="object-cover transition group-hover:scale-105"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-5xl text-gray-300">🐾</div>
          )}
          {memberPrice !== null && (
            <span className="absolute left-3 top-3 rounded-full bg-blue-500 px-2 py-0.5 text-xs font-bold text-white">
              Member
            </span>
          )}
        </div>

        {/* Info — TANPA deskripsi panjang. Deskripsi lengkap di halaman detail
            produk. Card cuma: gambar, nama (max 2 baris), harga, CTA. */}
        <div className="flex flex-1 flex-col p-4">
          <h3 className="line-clamp-2 font-semibold leading-snug text-gray-900">
            {product.name}
          </h3>

          <div className="mt-3">
            <p className="font-bold text-gray-900">{formatRupiah(displayPrice)}</p>
            {hasMarkdown && (
              <p className="text-xs text-gray-400 line-through">{formatRupiah(product.price)}</p>
            )}
          </div>
        </div>
      </Link>

      {/* CTA kecil — outside Link untuk hindari nested-interactive. */}
      <div className="px-4 pb-4">
        <ProductCardCta
          productId={product.id}
          slug={product.slug}
          name={product.name}
          price={displayPrice}
          imageUrl={product.imageUrl}
          weightGram={product.weightGram}
          stock={product.stock}
          hasVariants={product.hasVariants}
        />
      </div>
    </div>
  );
}
