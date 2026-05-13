import type { Metadata } from "next";
import Link from "next/link";
import { IoPlayCircleOutline } from "react-icons/io5";

export const metadata: Metadata = {
  title: "Feed",
  description:
    "Feed Natalo Petshop untuk konten komunitas, promo, edukasi pet care, dan video produk.",
};

export default function FeedPage() {
  return (
    <div className="mx-auto flex min-h-[calc(100dvh-8rem)] max-w-3xl flex-col items-center justify-center px-4 pb-[calc(6rem+env(safe-area-inset-bottom))] pt-10 text-center md:py-16">
      <div className="flex h-20 w-20 items-center justify-center rounded-full bg-blue-50 text-blue-600">
        <IoPlayCircleOutline className="h-11 w-11" aria-hidden="true" />
      </div>

      <h1 className="mt-6 text-2xl font-black text-slate-900 md:text-3xl">
        Feed Natalo
      </h1>
      <p className="mt-3 max-w-md text-sm leading-6 text-slate-500">
        Ruang feed sedang disiapkan untuk video, promo, konten komunitas, dan
        edukasi pet care. Untuk sekarang, katalog produk tetap jadi fokus utama.
      </p>

      <Link
        href="/products"
        className="mt-6 inline-flex rounded-full bg-blue-600 px-6 py-3 text-sm font-bold text-white shadow-sm transition active:scale-95"
      >
        Lihat Produk
      </Link>
    </div>
  );
}
