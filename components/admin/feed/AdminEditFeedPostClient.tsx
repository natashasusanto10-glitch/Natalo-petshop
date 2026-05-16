"use client";

import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { FiArrowLeft, FiPackage, FiX } from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { formatRupiah } from "@/lib/format";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";

const MAX_TITLE_LENGTH = 200;
const MAX_DESC_LENGTH = 2000;
const MAX_PRODUCTS = 5;

type TaggedProduct = {
  productId: string;
  slug: string;
  name: string;
  price: number;
  imageUrl: string | null;
};

type AdminProduct = {
  id: string;
  slug: string;
  name: string;
  price: number;
  imageUrl: string | null;
};

type Props = {
  postId: string;
  initialTitle: string;
  initialDescription: string;
  initialProducts: TaggedProduct[];
  thumbnailUrl: string | null;
  videoDurationSec: number | null;
  kind: string;
  tab: string;
  initialPromoOriginalPrice: number | null;
  initialPromoDiscountPrice: number | null;
};

export function AdminEditFeedPostClient({
  postId,
  initialTitle,
  initialDescription,
  initialProducts,
  thumbnailUrl,
  videoDurationSec,
  kind,
  tab,
  initialPromoOriginalPrice,
  initialPromoDiscountPrice,
}: Props) {
  const router = useRouter();
  const [title, setTitle] = useState(initialTitle);
  const [description, setDescription] = useState(initialDescription);
  const [promoOriginalPrice, setPromoOriginalPrice] = useState(
    initialPromoOriginalPrice?.toString() ?? "",
  );
  const [promoDiscountPrice, setPromoDiscountPrice] = useState(
    initialPromoDiscountPrice?.toString() ?? "",
  );
  const [selectedProducts, setSelectedProducts] =
    useState<TaggedProduct[]>(initialProducts);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<AdminProduct[]>([]);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!pickerOpen) return;
    const q = searchQuery.trim();
    if (q.length < 2) {
      setSearchResults([]);
      return;
    }
    let cancelled = false;
    const t = setTimeout(() => {
      fetch(`/api/admin/products?q=${encodeURIComponent(q)}`)
        .then((r) => r.json())
        .then((data: { products?: AdminProduct[] }) => {
          if (!cancelled) setSearchResults(data.products ?? []);
        })
        .catch(() => {});
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [searchQuery, pickerOpen]);

  async function handleSave() {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/feed/posts/${postId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: title.trim() || "Postingan baru",
          description: description.trim() || null,
          productIds: selectedProducts.map((p) => p.productId),
          ...(kind === "PROMO"
            ? {
                promoOriginalPrice: Number(promoOriginalPrice) || null,
                promoDiscountPrice: Number(promoDiscountPrice) || null,
              }
            : {}),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal menyimpan");
      router.push("/admin/feed");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <header className="mb-4 flex items-center justify-between">
        <Link
          href="/admin/feed"
          aria-label="Kembali"
          className="grid h-10 w-10 place-items-center rounded-full bg-white shadow-sm"
        >
          <FiArrowLeft className="h-5 w-5 text-gray-700" />
        </Link>
        <h1 className="text-lg font-black text-gray-900">Edit Postingan</h1>
        <button
          type="button"
          onClick={handleSave}
          disabled={busy}
          className="rounded-full bg-natalo-600 px-4 py-2 text-sm font-black text-white shadow-sm transition active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-gray-300"
        >
          {busy ? "Menyimpan..." : "Simpan"}
        </button>
      </header>

      <div className="mb-4 grid grid-cols-2 gap-3">
        <div className="rounded-2xl border border-gray-100 bg-white p-3 text-center">
          <p className="text-[10px] font-bold text-gray-500">Kind</p>
          <p className="mt-1 text-sm font-black text-gray-900">{kind}</p>
        </div>
        <div className="rounded-2xl border border-gray-100 bg-white p-3 text-center">
          <p className="text-[10px] font-bold text-gray-500">Tab</p>
          <p className="mt-1 text-sm font-black text-gray-900">{tab}</p>
        </div>
      </div>

      <section className="rounded-2xl border border-gray-100 bg-white p-4">
        <div className="flex gap-3">
          <div className="relative h-24 w-20 shrink-0 overflow-hidden rounded-xl bg-gray-100">
            {thumbnailUrl ? (
              <Image
                src={thumbnailUrl}
                alt=""
                fill
                sizes="80px"
                placeholder="blur"
                blurDataURL={IMAGE_BLUR_GRAY}
                className="object-cover"
              />
            ) : null}
            {videoDurationSec ? (
              <span className="absolute bottom-1 left-1 rounded bg-black/70 px-1.5 py-0.5 text-[10px] font-black text-white">
                {Math.floor(videoDurationSec / 60)}:
                {String(videoDurationSec % 60).padStart(2, "0")}
              </span>
            ) : null}
          </div>
          <div className="flex flex-1 flex-col gap-2">
            <label className="block">
              <span className="text-[11px] font-bold text-gray-600">Judul</span>
              <input
                type="text"
                value={title}
                onChange={(e) =>
                  setTitle(e.target.value.slice(0, MAX_TITLE_LENGTH))
                }
                disabled={busy}
                className="mt-0.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
              />
              <p className="mt-1 text-right text-[10px] font-bold text-gray-400">
                {title.length}/{MAX_TITLE_LENGTH}
              </p>
            </label>
          </div>
        </div>

        <label className="mt-3 block">
          <span className="text-[11px] font-bold text-gray-600">Deskripsi</span>
          <textarea
            value={description}
            onChange={(e) =>
              setDescription(e.target.value.slice(0, MAX_DESC_LENGTH))
            }
            disabled={busy}
            rows={4}
            placeholder="Deskripsi (opsional)"
            className="mt-0.5 w-full resize-none rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
          />
          <p className="mt-1 text-right text-[10px] font-bold text-gray-400">
            {description.length}/{MAX_DESC_LENGTH}
          </p>
        </label>
      </section>

      {kind === "PROMO" && (
        <section className="mt-4 rounded-2xl border border-rose-200 bg-rose-50/40 p-4">
          <h2 className="text-sm font-black text-rose-900">
            Harga Promo
            <span className="ml-2 rounded-full bg-rose-200 px-2 py-0.5 text-[10px] uppercase text-rose-700">
              kind=PROMO
            </span>
          </h2>
          <p className="mt-1 text-[11px] text-rose-700">
            Harga ini muncul di Feed sebagai discount badge.
          </p>
          <div className="mt-3 grid grid-cols-2 gap-3">
            <label className="block">
              <span className="text-[11px] font-bold text-gray-600">
                Harga Asli (Rp)
              </span>
              <input
                type="number"
                inputMode="numeric"
                value={promoOriginalPrice}
                onChange={(e) => setPromoOriginalPrice(e.target.value)}
                disabled={busy}
                placeholder="100000"
                className="mt-0.5 w-full rounded-xl border border-gray-200 bg-white px-3 py-2 text-sm focus:border-natalo-500 focus:outline-none disabled:opacity-50"
              />
            </label>
            <label className="block">
              <span className="text-[11px] font-bold text-gray-600">
                Harga Discount (Rp)
              </span>
              <input
                type="number"
                inputMode="numeric"
                value={promoDiscountPrice}
                onChange={(e) => setPromoDiscountPrice(e.target.value)}
                disabled={busy}
                placeholder="75000"
                className="mt-0.5 w-full rounded-xl border border-gray-200 bg-white px-3 py-2 text-sm focus:border-natalo-500 focus:outline-none disabled:opacity-50"
              />
            </label>
          </div>
          {promoOriginalPrice && promoDiscountPrice && Number(promoDiscountPrice) < Number(promoOriginalPrice) && (
            <p className="mt-2 text-[11px] font-bold text-rose-800">
              Discount{" "}
              {Math.round(
                ((Number(promoOriginalPrice) - Number(promoDiscountPrice)) /
                  Number(promoOriginalPrice)) *
                  100,
              )}
              % off — akan muncul sebagai badge di Feed
            </p>
          )}
        </section>
      )}

      <section className="mt-4 rounded-2xl border border-gray-100 bg-white p-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm font-black text-gray-900">Tag Produk</h2>
            <p className="text-[11px] font-semibold text-gray-500">
              {selectedProducts.length}/{MAX_PRODUCTS} produk
            </p>
          </div>
          <button
            type="button"
            onClick={() => setPickerOpen(true)}
            disabled={busy}
            className="text-[12px] font-black text-natalo-600"
          >
            {selectedProducts.length > 0 ? "Ubah ›" : "Pilih ›"}
          </button>
        </div>
        {selectedProducts.length > 0 && (
          <ul className="mt-3 space-y-2">
            {selectedProducts.map((p, idx) => (
              <li
                key={p.productId}
                className="flex items-center gap-3 rounded-xl bg-gray-50 p-2.5"
              >
                <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-natalo-600/10 text-natalo-600">
                  <FiPackage className="h-5 w-5" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-2 text-[13px] font-extrabold text-gray-900">
                    {p.name}
                  </p>
                  <p className="text-[11px] font-semibold text-gray-500">
                    Tag #{idx + 1} · {formatRupiah(p.price)}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() =>
                    setSelectedProducts((prev) =>
                      prev.filter((x) => x.productId !== p.productId),
                    )
                  }
                  disabled={busy}
                  aria-label={`Hapus ${p.name}`}
                  className="grid h-8 w-8 shrink-0 place-items-center rounded-full text-gray-400"
                >
                  <FiX className="h-4 w-4" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      {error && (
        <p className="mt-4 rounded-2xl border border-red-200 bg-red-50 p-3 text-center text-xs font-bold text-red-700">
          {error}
        </p>
      )}

      <BottomSheet
        open={pickerOpen}
        onClose={() => setPickerOpen(false)}
        title={`Tag Produk (${selectedProducts.length}/${MAX_PRODUCTS})`}
      >
        <div className="space-y-3">
          <input
            type="search"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Cari nama produk..."
            className="w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none"
          />
          {searchResults.length === 0 && searchQuery.trim().length >= 2 && (
            <p className="rounded-2xl bg-gray-50 p-4 text-center text-xs font-bold text-gray-500">
              Tidak ada produk match
            </p>
          )}
          {searchResults.map((product) => {
            const selected = selectedProducts.some(
              (p) => p.productId === product.id,
            );
            const atMax = selectedProducts.length >= MAX_PRODUCTS;
            const disabled = atMax && !selected;
            return (
              <button
                key={product.id}
                type="button"
                disabled={disabled}
                onClick={() => {
                  setSelectedProducts((cur) => {
                    if (selected) {
                      return cur.filter((p) => p.productId !== product.id);
                    }
                    if (cur.length >= MAX_PRODUCTS) return cur;
                    return [
                      ...cur,
                      {
                        productId: product.id,
                        slug: product.slug,
                        name: product.name,
                        price: product.price,
                        imageUrl: product.imageUrl,
                      },
                    ];
                  });
                }}
                className={`flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition active:bg-gray-50 ${
                  selected
                    ? "border-natalo-500 bg-natalo-50"
                    : disabled
                      ? "border-gray-100 bg-gray-50 opacity-50"
                      : "border-gray-100 bg-white"
                }`}
              >
                <div className="grid h-14 w-14 shrink-0 place-items-center rounded-xl bg-gray-100 text-natalo-600">
                  <FiPackage className="h-5 w-5" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-2 text-sm font-extrabold text-gray-900">
                    {product.name}
                  </p>
                  <p className="mt-0.5 text-xs font-black text-natalo-600">
                    {formatRupiah(product.price)}
                  </p>
                </div>
                {selected && (
                  <span className="text-[11px] font-black text-natalo-600">
                    Terpilih
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </BottomSheet>
    </div>
  );
}
