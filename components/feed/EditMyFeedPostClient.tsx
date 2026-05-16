"use client";

import Image from "next/image";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { FiArrowLeft, FiPackage, FiX } from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { formatRupiah } from "@/lib/format";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import type { FeedPostStatus } from "@prisma/client";

const MAX_CAPTION_LENGTH = 500;
const MAX_PRODUCTS = 3;

type PetType = "cat" | "dog" | "other" | null;

type TaggedProduct = {
  productId: string;
  slug: string;
  name: string;
  price: number;
  imageUrl: string | null;
};

type PinnableProduct = {
  productId: string;
  slug: string;
  name: string;
  price: number;
  imageUrl: string | null;
  purchasedAt: string;
  orderNumber: string;
};

type Props = {
  postId: string;
  initialCaption: string;
  initialPetType: PetType;
  initialProducts: TaggedProduct[];
  thumbnailUrl: string | null;
  videoDurationSec: number | null;
  status: FeedPostStatus;
};

export function EditMyFeedPostClient({
  postId,
  initialCaption,
  initialPetType,
  initialProducts,
  thumbnailUrl,
  videoDurationSec,
  status,
}: Props) {
  const router = useRouter();
  const [caption, setCaption] = useState(initialCaption);
  const [petType, setPetType] = useState<PetType>(initialPetType);
  const [selectedProducts, setSelectedProducts] =
    useState<TaggedProduct[]>(initialProducts);
  const [pinnable, setPinnable] = useState<PinnableProduct[]>([]);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/feed/pinnable-products")
      .then((r) => r.json())
      .then((data: { products?: PinnableProduct[] }) => {
        if (!cancelled) setPinnable(data.products ?? []);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  async function handleSave() {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/feed/posts/${postId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: caption.trim().slice(0, 200) || "Postingan baru",
          description: caption.trim() || null,
          petType: petType,
          productIds: selectedProducts.map((p) => p.productId),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal menyimpan");
      router.push(`/akun/postingan-saya/${postId}`);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      {/* Header */}
      <header className="mb-4 flex items-center justify-between">
        <button
          type="button"
          onClick={() => router.back()}
          aria-label="Kembali"
          className="grid h-10 w-10 place-items-center rounded-full bg-white shadow-sm"
        >
          <FiArrowLeft className="h-5 w-5 text-gray-700" />
        </button>
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

      {status === "ACTIVE" && (
        <div className="mb-4 rounded-2xl border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800">
          <p className="font-bold">⚠️ Setelah edit, postingan akan masuk review admin lagi.</p>
          <p className="mt-1">Akan tampil di Feed setelah disetujui.</p>
        </div>
      )}

      {/* Caption */}
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
          <div className="flex flex-1 flex-col">
            <textarea
              value={caption}
              onChange={(e) =>
                setCaption(e.target.value.slice(0, MAX_CAPTION_LENGTH))
              }
              placeholder="Tulis caption..."
              rows={4}
              disabled={busy}
              className="flex-1 resize-none rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
            />
            <p className="mt-1 text-right text-[11px] font-bold text-gray-400">
              {caption.length}/{MAX_CAPTION_LENGTH}
            </p>
          </div>
        </div>
      </section>

      {/* Tag Produk */}
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
        {selectedProducts.length > 0 ? (
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
                    Tag #{idx + 1}
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
        ) : (
          <p className="mt-2 text-[12px] leading-relaxed text-gray-500">
            Opsional. Tag sampai 3 produk dari pesanan kamu.
          </p>
        )}
      </section>

      {/* Info Pet */}
      <section className="mt-4 rounded-2xl border border-gray-100 bg-white p-4">
        <h2 className="text-sm font-black text-gray-900">Info Pet</h2>
        <div className="mt-3 flex flex-wrap gap-2">
          {(
            [
              { v: "cat", l: "Kucing", e: "🐱" },
              { v: "dog", l: "Anjing", e: "🐶" },
              { v: "other", l: "Lainnya", e: "•••" },
            ] as const
          ).map((opt) => (
            <button
              key={opt.v}
              type="button"
              onClick={() => setPetType((cur) => (cur === opt.v ? null : opt.v))}
              disabled={busy}
              className={`flex items-center gap-1.5 rounded-full px-3.5 py-2 text-[12px] font-black transition active:scale-[0.97] ${
                petType === opt.v
                  ? "bg-natalo-600 text-white shadow-sm"
                  : "bg-gray-100 text-gray-700"
              }`}
            >
              <span aria-hidden>{opt.e}</span>
              {opt.l}
            </button>
          ))}
        </div>
      </section>

      {error && (
        <p className="mt-4 rounded-2xl border border-red-200 bg-red-50 p-3 text-center text-xs font-bold text-red-700">
          {error}
        </p>
      )}

      {/* Product picker bottom sheet */}
      <BottomSheet
        open={pickerOpen}
        onClose={() => setPickerOpen(false)}
        title={`Tag Produk (${selectedProducts.length}/${MAX_PRODUCTS})`}
      >
        <div className="space-y-3">
          {pinnable.length === 0 && (
            <div className="rounded-2xl bg-gray-50 p-4 text-center">
              <p className="text-sm font-extrabold text-gray-700">
                Belum ada produk yang bisa di-tag
              </p>
              <p className="mt-1 text-xs text-gray-500">
                Produk muncul setelah pesanan selesai + diterima.
              </p>
            </div>
          )}
          {pinnable.map((product) => {
            const selected = selectedProducts.some(
              (p) => p.productId === product.productId,
            );
            const atMax = selectedProducts.length >= MAX_PRODUCTS;
            const disabled = atMax && !selected;
            return (
              <button
                key={`${product.productId}-${product.orderNumber}`}
                type="button"
                disabled={disabled}
                onClick={() => {
                  setSelectedProducts((cur) => {
                    if (selected) {
                      return cur.filter((p) => p.productId !== product.productId);
                    }
                    if (cur.length >= MAX_PRODUCTS) return cur;
                    return [
                      ...cur,
                      {
                        productId: product.productId,
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
