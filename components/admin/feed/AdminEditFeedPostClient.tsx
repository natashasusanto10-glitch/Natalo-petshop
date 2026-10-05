"use client";

import Image from "next/image";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { FiEye, FiPackage, FiX } from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { Button, SectionCard } from "@/components/admin/ui";

import { AdminFeedPreview } from "./AdminFeedPreview";
import { useAdminConfirm } from "@/components/admin/ui/useAdminConfirm";
import { AdminDialog } from "@/components/admin/ui/AdminDialog";

const MAX_TITLE_LENGTH = 200;
const MAX_DESC_LENGTH = 2000;
const MAX_PRODUCTS = 5;

const KIND_LABEL: Record<string, string> = {
  VIDEO_ONLY: "Video edukasi",
  VIDEO_PRODUCT: "Video + produk",
  PROMO: "Promo produk",
  PRODUCT_ONLY: "Produk (legacy)",
};

const TAB_LABEL: Record<string, string> = {
  FEED: "Feed",
  REKOMENDASI: "Rekomendasi",
  PROMO: "Promo",
  KOMUNITAS: "Komunitas",
};

type TaggedProduct = {
  productId: string;
  slug: string;
  name: string;
  price: number;
  imageUrl: string | null;
  // Per-product discount untuk video PROMO. Null = no discount (display
  // harga normal). Set per-produk supaya 1 video bisa diskon banyak
  // produk dengan harga discount masing-masing.
  promoPrice: number | null;
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
  videoUrl?: string | null;
  kind: string;
  tab: string;
};

export function AdminEditFeedPostClient({
  postId,
  initialTitle,
  initialDescription,
  initialProducts,
  thumbnailUrl,
  videoDurationSec,
  videoUrl,
  kind,
  tab,
}: Props) {
  const router = useRouter();
  const { confirm, confirmation } = useAdminConfirm();
  const [previewOpen, setPreviewOpen] = useState(false);
  const [title, setTitle] = useState(initialTitle);
  const [description, setDescription] = useState(initialDescription);
  // Per-product promo price (string supaya bisa edit input + null state).
  // Key = productId. Empty string = no discount (null saat submit).
  const [productPromos, setProductPromos] = useState<Record<string, string>>(
    () =>
      Object.fromEntries(
        initialProducts.map((p) => [
          p.productId,
          p.promoPrice != null ? String(p.promoPrice) : "",
        ])
      )
  );
  const [selectedProducts, setSelectedProducts] =
    useState<TaggedProduct[]>(initialProducts);
  // Pencarian produk INLINE — hasil muncul langsung di bawah kotak cari di
  // halaman yang sama (pola sama dgn AdminFeedCreateClient), bukan panel
  // yang meluncur dari bawah layar. Sama endpoint (/api/admin/products)
  // yang sudah pakai productSearchWhere (multi-kata + cari by brand).
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<AdminProduct[]>([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const q = searchQuery.trim();
    setSearchError(null);
    setSearchResults([]);
    if (q.length < 2) {
      setSearchResults([]);
      setSearchLoading(false);
      return;
    }
    setSearchLoading(true);
    let cancelled = false;
    const t = setTimeout(() => {
      fetch(`/api/admin/products?q=${encodeURIComponent(q)}&limit=10`)
        .then((r) => {
          if (!r.ok)
            throw new Error(
              "Gagal mencari produk. Ubah kata kunci untuk mencoba kembali."
            );
          return r.json();
        })
        .then((data: { products?: AdminProduct[] }) => {
          if (!cancelled) setSearchResults(data.products ?? []);
        })
        .catch((err) => {
          if (!cancelled)
            setSearchError(
              err instanceof Error ? err.message : "Gagal mencari produk."
            );
        })
        .finally(() => {
          if (!cancelled) setSearchLoading(false);
        });
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [searchQuery]);

  const selectedProductIdSet = new Set(
    selectedProducts.map((p) => p.productId)
  );

  function toggleProduct(product: AdminProduct) {
    const selected = selectedProductIdSet.has(product.id);
    setSelectedProducts((cur) => {
      if (selected) return cur.filter((p) => p.productId !== product.id);
      if (cur.length >= MAX_PRODUCTS) return cur;
      return [
        ...cur,
        {
          productId: product.id,
          slug: product.slug,
          name: product.name,
          price: product.price,
          imageUrl: product.imageUrl,
          promoPrice: null,
        },
      ];
    });
    setProductPromos((prev) => {
      if (selected) {
        const next = { ...prev };
        delete next[product.id];
        return next;
      }
      return { ...prev, [product.id]: prev[product.id] ?? "" };
    });
  }

  function removeSelectedProduct(productId: string) {
    setSelectedProducts((cur) => cur.filter((p) => p.productId !== productId));
    setProductPromos((prev) => {
      const next = { ...prev };
      delete next[productId];
      return next;
    });
  }

  async function handleSave() {
    if (busy) return;
    setError(null);
    if (kind === "PROMO") {
      for (const product of selectedProducts) {
        const raw = (productPromos[product.productId] ?? "").trim();
        if (!raw) continue;
        const amount = Number(raw);
        if (
          !Number.isFinite(amount) ||
          amount <= 0 ||
          amount >= product.price
        ) {
          setError(
            `Harga promo "${
              product.name
            }" harus lebih dari 0 dan di bawah ${product.price.toLocaleString(
              "id-ID"
            )}.`
          );
          return;
        }
      }
    }
    setBusy(true);
    try {
      // Build productPromos map — only include products yang masih terpilih
      // (skip orphan entry kalau admin remove produk). Empty string → null.
      const productPromosPayload: Record<string, number | null> = {};
      if (kind === "PROMO") {
        for (const p of selectedProducts) {
          const raw = (productPromos[p.productId] ?? "").trim();
          if (raw === "") {
            productPromosPayload[p.productId] = null;
          } else {
            const n = Number(raw);
            productPromosPayload[p.productId] = Number.isFinite(n) ? n : null;
          }
        }
      }

      const res = await fetch(`/api/feed/posts/${postId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: title.trim() || "Postingan baru",
          description: description.trim() || null,
          productIds: selectedProducts.map((p) => p.productId),
          ...(kind === "PROMO" ? { productPromos: productPromosPayload } : {}),
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

  async function leaveForm() {
    if (busy) return;
    const initialPromos = Object.fromEntries(
      initialProducts.map((p) => [
        p.productId,
        p.promoPrice == null ? "" : String(p.promoPrice),
      ])
    );
    const dirty =
      title !== initialTitle ||
      description !== initialDescription ||
      JSON.stringify(selectedProducts.map((p) => p.productId)) !==
        JSON.stringify(initialProducts.map((p) => p.productId)) ||
      JSON.stringify(productPromos) !== JSON.stringify(initialPromos);
    if (
      dirty &&
      !(await confirm(
        "Tinggalkan form? Perubahan yang belum disimpan akan hilang."
      ))
    )
      return;
    router.push("/admin/feed");
  }
  const previewContent = (
    <AdminFeedPreview
      title={title}
      description={description}
      thumbnailUrl={thumbnailUrl}
      videoUrl={videoUrl}
      products={selectedProducts.map((p) => ({
        id: p.productId,
        name: p.name,
        imageUrl: p.imageUrl,
        price: p.price,
        promoPrice:
          kind === "PROMO" && productPromos[p.productId]
            ? Number(productPromos[p.productId])
            : null,
      }))}
    />
  );
  const kindTabLabel = `${KIND_LABEL[kind] ?? kind} · ${TAB_LABEL[tab] ?? tab}`;

  return (
    <div className="af af-edit-form">
      {confirmation}
      <div className="flex flex-col items-start justify-between gap-3 md:flex-row md:items-center">
        <div className="min-w-0">
          <button
            type="button"
            onClick={() => void leaveForm()}
            className="text-xs font-semibold text-natalo-600 hover:text-natalo-700"
          >
            ← Feed
          </button>
          <h1 className="mt-0.5 text-xl font-semibold text-zinc-950 md:text-2xl">
            Edit postingan
          </h1>
          <p className="mt-0.5 text-xs text-zinc-500">{kindTabLabel}</p>
        </div>
        <Button
          type="button"
          variant="secondary"
          onClick={() => setPreviewOpen(true)}
        >
          <FiEye aria-hidden />
          Pratinjau
        </Button>
      </div>
      <div className="af-editor">
        <div className="af-form">
          <SectionCard title="Media & konten">
            <div className="flex gap-3">
              <div className="relative h-24 w-20 shrink-0 overflow-hidden rounded-xl bg-zinc-100">
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
                  <span className="absolute bottom-1 left-1 rounded bg-black/70 px-1.5 py-0.5 text-xs font-semibold text-white">
                    {Math.floor(videoDurationSec / 60)}:
                    {String(videoDurationSec % 60).padStart(2, "0")}
                  </span>
                ) : null}
              </div>
              <div className="flex flex-1 flex-col gap-2">
                <label className="block">
                  <span className="text-xs font-bold text-zinc-600">Judul</span>
                  <input
                    type="text"
                    value={title}
                    onChange={(e) =>
                      setTitle(e.target.value.slice(0, MAX_TITLE_LENGTH))
                    }
                    disabled={busy}
                    className="mt-0.5 w-full rounded-xl border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
                  />
                  <p className="mt-1 text-right text-xs font-bold text-zinc-400">
                    {title.length}/{MAX_TITLE_LENGTH}
                  </p>
                </label>
              </div>
            </div>

            <label className="mt-3 block">
              <span className="text-xs font-bold text-zinc-600">Caption</span>
              <textarea
                value={description}
                onChange={(e) =>
                  setDescription(e.target.value.slice(0, MAX_DESC_LENGTH))
                }
                disabled={busy}
                rows={4}
                placeholder="Deskripsi (opsional)"
                className="mt-0.5 w-full resize-none rounded-xl border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
              />
              <p className="mt-1 text-right text-xs font-bold text-zinc-400">
                {description.length}/{MAX_DESC_LENGTH}
              </p>
            </label>
          </SectionCard>

          <SectionCard
            title="Produk terkait"
            subtitle={
              kind === "PROMO"
                ? "Set harga promo per-produk di bawah"
                : undefined
            }
          >
            <div className="mb-3 flex items-center justify-end">
              <span className="text-xs font-semibold text-zinc-400">
                {selectedProducts.length}/{MAX_PRODUCTS}
              </span>
            </div>

            {selectedProducts.length > 0 && (
              <ul className="mb-3 space-y-2">
                {selectedProducts.map((p) => {
                  const promoRaw = productPromos[p.productId] ?? "";
                  const promoNum = Number(promoRaw);
                  const hasValidPromo =
                    promoRaw.trim() !== "" &&
                    Number.isFinite(promoNum) &&
                    promoNum > 0 &&
                    promoNum < p.price;
                  const discountPct = hasValidPromo
                    ? Math.round(((p.price - promoNum) / p.price) * 100)
                    : 0;
                  return (
                    <li
                      key={p.productId}
                      className="rounded-xl bg-zinc-50 p-2.5"
                    >
                      <div className="flex items-center gap-3">
                        <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-natalo-600/10 text-natalo-600">
                          {p.imageUrl ? (
                            <Image
                              src={p.imageUrl}
                              alt=""
                              width={48}
                              height={48}
                              className="h-12 w-12 rounded-lg object-cover"
                            />
                          ) : (
                            <FiPackage className="h-5 w-5" />
                          )}
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="line-clamp-2 text-[13px] font-semibold text-zinc-900">
                            {p.name}
                          </p>
                          <p className="text-xs font-semibold text-zinc-500">
                            Harga normal {formatRupiah(p.price)}
                          </p>
                        </div>
                        <button
                          type="button"
                          onClick={() => removeSelectedProduct(p.productId)}
                          disabled={busy}
                          aria-label={`Hapus ${p.name}`}
                          className="grid h-8 w-8 shrink-0 place-items-center rounded-full text-zinc-400"
                        >
                          <FiX className="h-4 w-4" />
                        </button>
                      </div>
                      {kind === "PROMO" && (
                        <div className="mt-2 rounded-lg border border-rose-200 bg-rose-50/60 p-2.5">
                          <label className="block">
                            <span className="text-xs font-bold text-rose-800">
                              Harga promo — kosongkan tanpa diskon
                            </span>
                            <input
                              type="text"
                              inputMode="numeric"
                              maxLength={19}
                              value={
                                promoRaw
                                  ? Number(promoRaw).toLocaleString("id-ID")
                                  : ""
                              }
                              onChange={(e) =>
                                setProductPromos((prev) => ({
                                  ...prev,
                                  [p.productId]: e.target.value.replace(
                                    /\D/g,
                                    ""
                                  ),
                                }))
                              }
                              disabled={busy}
                              placeholder={`Di bawah ${p.price.toLocaleString(
                                "id-ID"
                              )}`}
                              className="mt-0.5 w-full rounded-lg border border-rose-200 bg-white px-3 py-2 text-sm focus:border-rose-500 focus:outline-none disabled:opacity-50"
                            />
                          </label>
                          {hasValidPromo ? (
                            <p className="mt-1.5 text-xs font-bold text-rose-800">
                              Hemat {formatRupiah(p.price - promoNum)} ·{" "}
                              {discountPct}% off
                            </p>
                          ) : promoRaw.trim() !== "" &&
                            Number.isFinite(promoNum) &&
                            promoNum >= p.price ? (
                            <p className="mt-1.5 text-xs font-bold text-amber-700">
                              Harga promo harus lebih kecil dari harga normal.
                            </p>
                          ) : null}
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}

            {selectedProducts.length >= MAX_PRODUCTS ? (
              <p className="rounded-xl bg-zinc-50 px-3 py-2 text-xs font-bold text-zinc-500">
                Maksimal {MAX_PRODUCTS} produk terkait sudah dipilih.
              </p>
            ) : (
              <>
                <input
                  type="text"
                  aria-label="Cari produk terkait"
                  placeholder={
                    selectedProducts.length > 0
                      ? "Cari produk tambahan..."
                      : "Cari produk (min 2 huruf)..."
                  }
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  disabled={busy}
                  className="w-full rounded-xl border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
                />
                {searchLoading && (
                  <p className="mt-2 text-center text-xs font-bold text-zinc-400">
                    Mencari...
                  </p>
                )}
                {!searchLoading &&
                  searchResults.length === 0 &&
                  searchQuery.trim().length >= 2 && (
                    <p className="mt-2 rounded-xl bg-zinc-50 px-3 py-2 text-center text-xs font-bold text-zinc-500">
                      Tidak ada produk match
                    </p>
                  )}
                {searchResults.length > 0 && (
                  <ul className="mt-2 max-h-60 overflow-y-auto rounded-xl border border-zinc-100">
                    {searchResults.map((product) => {
                      const selected = selectedProductIdSet.has(product.id);
                      const atMax = selectedProducts.length >= MAX_PRODUCTS;
                      const disabled = atMax && !selected;
                      return (
                        <li key={product.id}>
                          <button
                            type="button"
                            onClick={() => toggleProduct(product)}
                            disabled={disabled}
                            className="flex w-full items-center gap-2 border-b border-zinc-50 px-2 py-2 text-left text-xs transition last:border-0 hover:bg-zinc-50 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:opacity-60"
                          >
                            {product.imageUrl && (
                              <Image
                                src={product.imageUrl}
                                alt=""
                                width={32}
                                height={32}
                                className="h-8 w-8 rounded-lg object-cover"
                              />
                            )}
                            <span className="min-w-0 flex-1 truncate font-bold">
                              {product.name}
                            </span>
                            <span className="shrink-0 text-natalo-600">
                              {selected
                                ? "Dipilih"
                                : formatRupiah(product.price)}
                            </span>
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </>
            )}
          </SectionCard>

          {error && (
            <p
              role="alert"
              className="rounded-2xl border border-red-200 bg-red-50 p-3 text-center text-xs font-bold text-red-700"
            >
              {error}
            </p>
          )}
          <div className="af-savebar">
            <Button
              type="button"
              onClick={() => void leaveForm()}
              variant="secondary"
              disabled={busy}
            >
              Batal
            </Button>
            <Button
              type="button"
              onClick={() => void handleSave()}
              disabled={busy}
            >
              {busy ? "Menyimpan…" : "Simpan perubahan"}
            </Button>
          </div>
        </div>
        <aside className="af-preview-aside">
          <div className="af-preview-heading">
            <strong>Pratinjau Feed</strong>
            <span>Tampilan pelanggan</span>
          </div>
          {previewContent}
        </aside>
      </div>
      <AdminDialog
        open={previewOpen}
        title="Pratinjau Feed"
        onClose={() => setPreviewOpen(false)}
        className="af-preview-dialog"
      >
        {previewOpen && previewContent}
      </AdminDialog>
    </div>
  );
}
