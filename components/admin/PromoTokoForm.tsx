"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { formatRupiah } from "@/lib/format";

// ── Types ───────────────────────────────────────────────────────

interface ProductSummary {
  id: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
}

interface VariantSummary {
  id: string;
  label: string;
  sku: string | null;
  price: number;
  stock: number;
  imageUrl: string | null;
}

/** 1 item dalam promo — bisa produk single (variant=null) atau 1 varian. */
interface PromoItem {
  productId: string;
  variantId: string | null;
  discountedPrice: number;
  isItemActive: boolean;
  product: ProductSummary;
  variant: VariantSummary | null;
}

interface InitialData {
  id?: string;
  name: string;
  startsAt: string; // datetime-local format
  endsAt: string;
  items: PromoItem[];
  isActive: boolean;
}

interface Props {
  initial?: InitialData;
  /** Saat edit, kirim id supaya endpoint eligible-products exclude. */
  excludeId?: string;
}

// Eligible product (dari API eligible-products endpoint) — bisa
// punya nested variants.
interface EligibleProduct {
  id: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
  hasVariants: boolean;
  category: { name: string } | null;
  variants: Array<{
    id: string;
    label: string;
    sku: string | null;
    price: number;
    stock: number;
    imageUrl: string | null;
    isBlocked: boolean;
  }>;
}

const emptyInitial: InitialData = {
  name: "",
  startsAt: "",
  endsAt: "",
  items: [],
  isActive: true,
};

/**
 * Form Promo Toko — create + edit shared component.
 *
 * Layout 2 section ala Shopee Seller:
 *  1. Informasi Dasar (Nama Promo + Periode)
 *  2. Produk dalam Promo Toko (tabel editable per-item)
 *     - Empty state: [+ Tambah Produk] button → buka modal product picker
 *     - With items: tabel dengan kolom: Foto + Nama | Harga Awal |
 *       Harga Diskon (Rp) | %Diskon | Stok | Toggle Aktif | Hapus
 *     - Produk berVarian: parent row collapsed, sub-rows per varian
 *     - 2-way binding antara Harga Diskon dan %Diskon
 */
export function PromoTokoForm({ initial, excludeId }: Props) {
  const router = useRouter();
  const isEdit = !!initial?.id;
  const data = initial ?? emptyInitial;

  // ── Form state ──────────────────────────────────────────────
  const [name, setName] = useState(data.name);
  const [startsAt, setStartsAt] = useState(data.startsAt);
  const [endsAt, setEndsAt] = useState(data.endsAt);
  const [items, setItems] = useState<PromoItem[]>(data.items);

  // Product picker modal state
  const [pickerOpen, setPickerOpen] = useState(false);

  // Submit state
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [showFieldErrors, setShowFieldErrors] = useState(false);

  // ── Validasi ────────────────────────────────────────────────
  const errors: { [k: string]: string } = {};
  if (!name.trim()) errors.name = "Nama promo wajib diisi";
  if (!startsAt) errors.startsAt = "Waktu mulai wajib diisi";
  if (!endsAt) errors.endsAt = "Waktu berakhir wajib diisi";
  if (startsAt && endsAt && new Date(endsAt) <= new Date(startsAt)) {
    errors.endsAt = "Waktu berakhir harus setelah waktu mulai";
  }
  if (items.length === 0) {
    errors.items = "Tambah minimal 1 produk";
  }
  // Validasi tiap item — harga diskon harus > 0 dan <= harga awal.
  for (const item of items) {
    const basePrice = item.variant?.price ?? item.product.price;
    if (item.isItemActive && item.discountedPrice <= 0) {
      errors.itemPrice = "Semua produk aktif harus punya harga diskon > 0";
      break;
    }
    if (item.discountedPrice > basePrice) {
      errors.itemPrice = "Harga diskon tidak boleh melebihi harga awal";
      break;
    }
  }
  const canSubmit = Object.keys(errors).length === 0;

  // ── Item handlers ───────────────────────────────────────────
  function addItems(newItems: PromoItem[]) {
    // Dedupe by productId+variantId
    setItems((prev) => {
      const existing = new Set(
        prev.map((i) => `${i.productId}::${i.variantId ?? ""}`),
      );
      const filtered = newItems.filter(
        (i) => !existing.has(`${i.productId}::${i.variantId ?? ""}`),
      );
      return [...prev, ...filtered];
    });
  }

  function updateItem(
    productId: string,
    variantId: string | null,
    patch: Partial<Pick<PromoItem, "discountedPrice" | "isItemActive">>,
  ) {
    setItems((prev) =>
      prev.map((i) =>
        i.productId === productId && i.variantId === variantId
          ? { ...i, ...patch }
          : i,
      ),
    );
  }

  function removeItem(productId: string, variantId: string | null) {
    setItems((prev) =>
      prev.filter(
        (i) => !(i.productId === productId && i.variantId === variantId),
      ),
    );
  }

  /** Hapus seluruh produk (semua variannya juga). Dipakai untuk
   *  parent row Hapus action. */
  function removeProduct(productId: string) {
    setItems((prev) => prev.filter((i) => i.productId !== productId));
  }

  // ── Group items by productId for display ────────────────────
  // Kalau produk berVarian: parent row + sub-rows.
  // Kalau produk tanpa varian: 1 row saja.
  const groupedItems: Array<{
    product: ProductSummary;
    items: PromoItem[];
  }> = [];
  for (const item of items) {
    const existing = groupedItems.find(
      (g) => g.product.id === item.productId,
    );
    if (existing) {
      existing.items.push(item);
    } else {
      groupedItems.push({ product: item.product, items: [item] });
    }
  }

  async function handleSubmit() {
    setShowFieldErrors(true);
    setError("");
    if (!canSubmit) {
      setError(
        "Gagal menyimpan karena terdapat kesalahan, edit dahulu dan coba lagi.",
      );
      return;
    }
    setSubmitting(true);
    try {
      const payload = {
        name: name.trim(),
        startsAt: new Date(startsAt).toISOString(),
        endsAt: new Date(endsAt).toISOString(),
        items: items.map((it) => ({
          productId: it.productId,
          variantId: it.variantId,
          discountedPrice: Math.max(0, Math.round(it.discountedPrice)),
          isItemActive: it.isItemActive,
        })),
      };
      const url = isEdit
        ? `/api/admin/discounts/promo-toko/${initial!.id}`
        : "/api/admin/discounts/promo-toko";
      const method = isEdit ? "PUT" : "POST";
      const res = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const json = await res.json();
      if (!res.ok) {
        if (json.conflictingPromoNames) {
          throw new Error(
            `Produk sudah masuk Promo Toko lain: ${json.conflictingPromoNames.join(", ")}. Hapus produk yang konflik dulu.`,
          );
        }
        throw new Error(json.error ?? "Gagal menyimpan");
      }
      router.push("/admin/diskon/promo-toko");
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan");
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-7xl px-4 py-5 md:px-8 md:py-10">
      {/* Breadcrumb */}
      <nav className="flex items-center gap-1 text-xs text-zinc-500">
        <Link href="/admin/diskon" className="hover:text-zinc-900">
          Buat Diskon
        </Link>
        <span>›</span>
        <Link href="/admin/diskon/promo-toko" className="hover:text-zinc-900">
          Promo Toko
        </Link>
        <span>›</span>
        <span className="text-zinc-900">
          {isEdit ? "Edit Promo Toko" : "Buat Promo Toko"}
        </span>
      </nav>

      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
        {isEdit ? "Edit Promo Toko" : "Buat Promo Toko"}
      </h1>

      {/* ─── Section 1: Informasi Dasar ──────────────────────────── */}
      <div className="mt-6 rounded-2xl border border-zinc-200 bg-white p-4 md:p-6">
        <h2 className="text-base font-bold text-zinc-900">Informasi Dasar</h2>

        <div className="mt-4 space-y-4">
          {/* Nama Promo */}
          <div className="flex flex-col gap-2 sm:flex-row sm:items-start">
            <label className="w-full text-sm font-semibold text-zinc-700 sm:w-48 sm:pt-3">
              Nama Promo Toko
            </label>
            <div className="flex-1">
              <div className="relative">
                <input
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Cth. Promo Hari Pet Nasional"
                  maxLength={150}
                  className={`block w-full rounded-xl border bg-white px-4 py-3 pr-16 text-sm outline-none focus:border-natalo-600 ${
                    showFieldErrors && errors.name
                      ? "border-red-400"
                      : "border-zinc-300"
                  }`}
                />
                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
                  {name.length}/150
                </span>
              </div>
              <p className="mt-1 text-xs text-amber-600">
                Nama Promo Toko tidak diperlihatkan ke Pembeli.
              </p>
              {showFieldErrors && errors.name && (
                <p className="mt-1 text-xs text-red-500">{errors.name}</p>
              )}
            </div>
          </div>

          {/* Periode */}
          <div className="flex flex-col gap-2 sm:flex-row sm:items-start">
            <label className="w-full text-sm font-semibold text-zinc-700 sm:w-48 sm:pt-3">
              Periode Promo Toko
            </label>
            <div className="flex-1">
              <div className="flex items-center gap-2">
                <input
                  type="datetime-local"
                  value={startsAt}
                  onChange={(e) => setStartsAt(e.target.value)}
                  className={`flex-1 rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
                    showFieldErrors && errors.startsAt
                      ? "border-red-400"
                      : "border-zinc-300"
                  }`}
                />
                <span className="text-zinc-400">—</span>
                <input
                  type="datetime-local"
                  value={endsAt}
                  onChange={(e) => setEndsAt(e.target.value)}
                  className={`flex-1 rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
                    showFieldErrors && errors.endsAt
                      ? "border-red-400"
                      : "border-zinc-300"
                  }`}
                />
              </div>
              <p className="mt-1 text-xs text-amber-600">
                Periode Promo harus kurang dari 90 hari.
              </p>
              {showFieldErrors && (errors.startsAt || errors.endsAt) && (
                <p className="mt-1 text-xs text-red-500">
                  {errors.startsAt || errors.endsAt}
                </p>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* ─── Section 2: Produk dalam Promo Toko ──────────────────── */}
      <div className="mt-6 rounded-2xl border border-zinc-200 bg-white p-4 md:p-6">
        <div className="flex items-baseline justify-between">
          <div>
            <h2 className="text-base font-bold text-zinc-900">
              Produk dalam Promo Toko
            </h2>
            {items.length === 0 && (
              <p className="mt-0.5 text-xs text-zinc-500">
                Tambahkan produk ke dalam Promo Toko dan atur harga diskon
              </p>
            )}
            {items.length > 0 && (
              <p className="mt-0.5 text-xs text-zinc-500">
                {items.length} total produk/varian dipromosikan
              </p>
            )}
          </div>
          <button
            type="button"
            onClick={() => setPickerOpen(true)}
            className="rounded-lg border border-natalo-600 px-4 py-2 text-sm font-bold text-natalo-700 hover:bg-natalo-50"
          >
            + Tambah Produk
          </button>
        </div>

        {/* Table */}
        {groupedItems.length > 0 && (
          <div className="mt-4 overflow-x-auto rounded-xl border border-zinc-200">
            <table className="w-full text-sm">
              <thead className="bg-zinc-50 text-xs font-bold uppercase tracking-wide text-zinc-500">
                <tr>
                  <th className="px-3 py-3 text-left">Nama Produk</th>
                  <th className="px-3 py-3 text-left">Harga Awal</th>
                  <th className="px-3 py-3 text-left">Harga Diskon</th>
                  <th className="px-3 py-3 text-left">Diskon</th>
                  <th className="px-3 py-3 text-left">Stok</th>
                  <th className="px-3 py-3 text-center">Aktif</th>
                  <th className="px-3 py-3 text-right">Aksi</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100">
                {groupedItems.map((group) => {
                  const hasVariants =
                    group.items.length > 1 || group.items[0].variantId !== null;
                  return (
                    <ProductGroupRow
                      key={group.product.id}
                      product={group.product}
                      items={group.items}
                      hasVariants={hasVariants}
                      onUpdate={updateItem}
                      onRemoveProduct={removeProduct}
                      onRemoveItem={removeItem}
                    />
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {showFieldErrors && errors.items && (
          <p className="mt-2 text-xs text-red-500">{errors.items}</p>
        )}
        {showFieldErrors && errors.itemPrice && (
          <p className="mt-2 text-xs text-red-500">{errors.itemPrice}</p>
        )}
      </div>

      {/* ─── Error banner ──────────────────────────────────────────── */}
      {error && (
        <div className="mt-6 flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-4">
          <span className="text-red-500">⚠</span>
          <p className="flex-1 text-sm font-semibold text-red-700">{error}</p>
        </div>
      )}

      {/* ─── Submit ────────────────────────────────────────────────── */}
      <div className="mt-6 flex justify-end gap-3">
        <Link
          href="/admin/diskon/promo-toko"
          className="rounded-lg border border-zinc-300 bg-white px-6 py-2.5 text-center text-sm font-bold text-zinc-700"
        >
          Batal
        </Link>
        <button
          type="button"
          onClick={handleSubmit}
          disabled={submitting}
          className="rounded-lg bg-natalo-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {submitting ? "Menyimpan..." : "Konfirmasi"}
        </button>
      </div>

      {/* ─── Product Picker Modal ──────────────────────────────────── */}
      {pickerOpen && (
        <ProductPickerModal
          excludeId={excludeId}
          existingItems={items}
          onClose={() => setPickerOpen(false)}
          onAdd={(newItems) => {
            addItems(newItems);
            setPickerOpen(false);
          }}
        />
      )}
    </div>
  );
}

// ── Product group row — handle produk single + berVarian ─────────

function ProductGroupRow({
  product,
  items,
  hasVariants,
  onUpdate,
  onRemoveProduct,
  onRemoveItem,
}: {
  product: ProductSummary;
  items: PromoItem[];
  hasVariants: boolean;
  onUpdate: (
    productId: string,
    variantId: string | null,
    patch: Partial<Pick<PromoItem, "discountedPrice" | "isItemActive">>,
  ) => void;
  onRemoveProduct: (productId: string) => void;
  onRemoveItem: (productId: string, variantId: string | null) => void;
}) {
  // Single product (no variants) — render 1 row.
  if (!hasVariants) {
    const item = items[0];
    return (
      <ItemRow
        productThumbnail={product}
        item={item}
        basePrice={product.price}
        baseStock={product.stock}
        onUpdate={onUpdate}
        onRemove={() => onRemoveItem(product.id, null)}
      />
    );
  }

  // Variant product — parent header row + sub-rows per varian.
  return (
    <>
      <tr className="bg-zinc-50/40">
        <td colSpan={7} className="px-3 py-2">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              {product.imageUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={product.imageUrl}
                  alt=""
                  className="h-10 w-10 rounded border border-zinc-200 object-cover"
                />
              ) : (
                <div className="h-10 w-10 rounded border border-zinc-200 bg-zinc-100" />
              )}
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-zinc-900">
                  {product.name}
                </p>
                <p className="text-[10px] text-zinc-500">
                  {items.length} varian dipromosikan
                </p>
              </div>
            </div>
            <button
              type="button"
              onClick={() => onRemoveProduct(product.id)}
              className="text-xs font-semibold text-natalo-600 hover:text-natalo-700"
            >
              Hapus
            </button>
          </div>
        </td>
      </tr>
      {items.map((item) => (
        <ItemRow
          key={item.variantId ?? "default"}
          productThumbnail={null} // variant rows tidak show product image
          item={item}
          basePrice={item.variant?.price ?? product.price}
          baseStock={item.variant?.stock ?? product.stock}
          onUpdate={onUpdate}
          onRemove={() => onRemoveItem(product.id, item.variantId)}
          variantLabel={item.variant?.label}
          isSubRow
        />
      ))}
    </>
  );
}

// ── Single item row dengan editable fields ──────────────────────

function ItemRow({
  productThumbnail,
  item,
  basePrice,
  baseStock,
  variantLabel,
  isSubRow,
  onUpdate,
  onRemove,
}: {
  productThumbnail: ProductSummary | null;
  item: PromoItem;
  basePrice: number;
  baseStock: number;
  variantLabel?: string;
  isSubRow?: boolean;
  onUpdate: (
    productId: string,
    variantId: string | null,
    patch: Partial<Pick<PromoItem, "discountedPrice" | "isItemActive">>,
  ) => void;
  onRemove: () => void;
}) {
  const discountPercent =
    basePrice > 0
      ? Math.round(((basePrice - item.discountedPrice) / basePrice) * 100)
      : 0;

  return (
    <tr className={item.isItemActive ? "" : "opacity-50"}>
      <td className="px-3 py-3 align-top">
        <div className="flex items-center gap-2">
          {productThumbnail?.imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={productThumbnail.imageUrl}
              alt=""
              className="h-10 w-10 rounded border border-zinc-200 object-cover"
            />
          ) : productThumbnail ? (
            <div className="h-10 w-10 rounded border border-zinc-200 bg-zinc-100" />
          ) : null}
          <div className={`min-w-0 ${isSubRow ? "pl-12" : ""}`}>
            {productThumbnail && (
              <p className="truncate text-sm font-semibold text-zinc-900">
                {productThumbnail.name}
              </p>
            )}
            {variantLabel && (
              <p className="text-xs font-semibold text-zinc-700">
                {variantLabel}
              </p>
            )}
          </div>
        </div>
      </td>
      <td className="px-3 py-3 align-top text-sm text-zinc-700">
        {formatRupiah(basePrice)}
      </td>
      {/* Harga Diskon (Rp) */}
      <td className="px-3 py-3 align-top">
        <div className="relative">
          <span className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
            Rp
          </span>
          <input
            type="number"
            value={item.discountedPrice || ""}
            onChange={(e) => {
              const v = parseInt(e.target.value || "0", 10);
              onUpdate(item.productId, item.variantId, {
                discountedPrice: Math.max(0, v),
              });
            }}
            placeholder="Input"
            min={0}
            max={basePrice}
            className="w-32 rounded-lg border border-zinc-300 bg-white pl-8 pr-2 py-1.5 text-sm outline-none focus:border-natalo-600"
          />
        </div>
      </td>
      {/* %Diskon — 2-way bound dengan Harga Diskon */}
      <td className="px-3 py-3 align-top">
        <span className="text-xs text-zinc-400">OR</span>
        <div className="relative mt-1">
          <input
            type="number"
            value={discountPercent || ""}
            onChange={(e) => {
              const pct = parseInt(e.target.value || "0", 10);
              const clamped = Math.max(0, Math.min(95, pct));
              const newPrice = Math.round((basePrice * (100 - clamped)) / 100);
              onUpdate(item.productId, item.variantId, {
                discountedPrice: newPrice,
              });
            }}
            placeholder="0"
            min={0}
            max={95}
            className="w-20 rounded-lg border border-zinc-300 bg-white pl-2 pr-7 py-1.5 text-sm outline-none focus:border-natalo-600"
          />
          <span className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
            %
          </span>
        </div>
      </td>
      <td className="px-3 py-3 align-top text-sm text-zinc-700">{baseStock}</td>
      <td className="px-3 py-3 align-top text-center">
        <button
          type="button"
          onClick={() =>
            onUpdate(item.productId, item.variantId, {
              isItemActive: !item.isItemActive,
            })
          }
          className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
            item.isItemActive ? "bg-green-500" : "bg-zinc-300"
          }`}
        >
          <span
            className={`absolute h-3.5 w-3.5 rounded-full bg-white shadow transition-transform ${
              item.isItemActive ? "translate-x-4" : "translate-x-1"
            }`}
          />
        </button>
      </td>
      <td className="px-3 py-3 align-top text-right">
        {!isSubRow && (
          <button
            type="button"
            onClick={onRemove}
            className="text-xs font-semibold text-natalo-600 hover:text-natalo-700"
          >
            Hapus
          </button>
        )}
      </td>
    </tr>
  );
}

// ── Product Picker Modal ─────────────────────────────────────────

function ProductPickerModal({
  excludeId,
  existingItems,
  onClose,
  onAdd,
}: {
  excludeId?: string;
  existingItems: PromoItem[];
  onClose: () => void;
  onAdd: (items: PromoItem[]) => void;
}) {
  const [products, setProducts] = useState<EligibleProduct[]>([]);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState("");
  // Selected: key = "productId::variantId|nullForNoVariant"
  const [selected, setSelected] = useState<Set<string>>(new Set());

  // Existing items keys — sudah ditambah ke promo, di-grey-out di picker.
  const existingKeys = new Set(
    existingItems.map((i) => `${i.productId}::${i.variantId ?? ""}`),
  );

  useEffect(() => {
    let cancelled = false;
    const fetchProducts = async () => {
      setLoading(true);
      try {
        const params = new URLSearchParams();
        if (search.trim()) params.set("q", search.trim());
        if (excludeId) params.set("excludeId", excludeId);
        const res = await fetch(
          `/api/admin/discounts/promo-toko/eligible-products?${params.toString()}`,
        );
        if (!res.ok) throw new Error("Gagal load produk");
        const json = await res.json();
        if (!cancelled) setProducts(json.products ?? []);
      } catch {
        // silent
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    const debounce = setTimeout(fetchProducts, search ? 300 : 0);
    return () => {
      cancelled = true;
      clearTimeout(debounce);
    };
  }, [search, excludeId]);

  function toggle(key: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  function confirm() {
    const itemsToAdd: PromoItem[] = [];
    for (const product of products) {
      if (product.hasVariants && product.variants.length > 0) {
        // Variant product — add per varian terpilih
        for (const v of product.variants) {
          const key = `${product.id}::${v.id}`;
          if (selected.has(key) && !v.isBlocked) {
            itemsToAdd.push({
              productId: product.id,
              variantId: v.id,
              discountedPrice: v.price, // default: full price (admin akan adjust)
              isItemActive: true,
              product: {
                id: product.id,
                name: product.name,
                imageUrl: product.imageUrl,
                price: product.price,
                stock: product.stock,
              },
              variant: {
                id: v.id,
                label: v.label,
                sku: v.sku,
                price: v.price,
                stock: v.stock,
                imageUrl: v.imageUrl,
              },
            });
          }
        }
      } else {
        // Single product — variantId null
        const key = `${product.id}::`;
        if (selected.has(key)) {
          itemsToAdd.push({
            productId: product.id,
            variantId: null,
            discountedPrice: product.price,
            isItemActive: true,
            product: {
              id: product.id,
              name: product.name,
              imageUrl: product.imageUrl,
              price: product.price,
              stock: product.stock,
            },
            variant: null,
          });
        }
      }
    }
    onAdd(itemsToAdd);
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        className="flex h-[80vh] w-full max-w-3xl flex-col rounded-2xl bg-white p-6 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-baseline justify-between">
          <h2 className="text-lg font-black text-zinc-900">Pilih Produk</h2>
          <button
            type="button"
            onClick={onClose}
            className="text-zinc-500 hover:text-zinc-900"
          >
            ✕
          </button>
        </div>

        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="🔍 Cari nama produk..."
          className="mt-3 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
        />

        <div className="mt-3 flex-1 overflow-y-auto rounded-xl border border-zinc-200">
          {loading ? (
            <p className="px-4 py-8 text-center text-sm text-zinc-400">
              Memuat produk...
            </p>
          ) : products.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-zinc-400">
              {search
                ? "Tidak ada produk cocok."
                : "Semua produk sedang di Promo Toko lain."}
            </p>
          ) : (
            <div className="divide-y divide-zinc-100">
              {products.map((p) => {
                if (p.hasVariants && p.variants.length > 0) {
                  // Variant product — show parent + nested variants
                  return (
                    <div key={p.id} className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        {p.imageUrl ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            src={p.imageUrl}
                            alt=""
                            className="h-10 w-10 rounded border border-zinc-200 object-cover"
                          />
                        ) : (
                          <div className="h-10 w-10 rounded border border-zinc-200 bg-zinc-100" />
                        )}
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-semibold">
                            {p.name}
                          </p>
                          <p className="text-xs text-zinc-500">
                            {p.variants.length} varian
                            {p.category?.name && ` • ${p.category.name}`}
                          </p>
                        </div>
                      </div>
                      <div className="ml-12 mt-2 space-y-1">
                        {p.variants.map((v) => {
                          const key = `${p.id}::${v.id}`;
                          const isExisting = existingKeys.has(key);
                          const isDisabled = v.isBlocked || isExisting;
                          return (
                            <label
                              key={v.id}
                              className={`flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 hover:bg-zinc-50 ${
                                isDisabled
                                  ? "cursor-not-allowed opacity-50"
                                  : ""
                              }`}
                            >
                              <input
                                type="checkbox"
                                checked={selected.has(key)}
                                disabled={isDisabled}
                                onChange={() => toggle(key)}
                                className="h-4 w-4 rounded border-zinc-300"
                              />
                              <p className="flex-1 text-sm">
                                <span className="font-semibold">{v.label}</span>
                                {" — "}
                                <span className="text-zinc-500">
                                  {formatRupiah(v.price)}
                                </span>
                                {isExisting && (
                                  <span className="ml-1 text-[10px] font-bold text-amber-600">
                                    (sudah ditambah)
                                  </span>
                                )}
                                {v.isBlocked && !isExisting && (
                                  <span className="ml-1 text-[10px] font-bold text-red-600">
                                    (di promo lain)
                                  </span>
                                )}
                              </p>
                            </label>
                          );
                        })}
                      </div>
                    </div>
                  );
                }
                // Single product
                const key = `${p.id}::`;
                const isExisting = existingKeys.has(key);
                return (
                  <label
                    key={p.id}
                    className={`flex cursor-pointer items-center gap-3 px-4 py-3 hover:bg-zinc-50 ${
                      isExisting ? "cursor-not-allowed opacity-50" : ""
                    }`}
                  >
                    <input
                      type="checkbox"
                      checked={selected.has(key)}
                      disabled={isExisting}
                      onChange={() => toggle(key)}
                      className="h-4 w-4 rounded border-zinc-300"
                    />
                    {p.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={p.imageUrl}
                        alt=""
                        className="h-10 w-10 rounded border border-zinc-200 object-cover"
                      />
                    ) : (
                      <div className="h-10 w-10 rounded border border-zinc-200 bg-zinc-100" />
                    )}
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold">{p.name}</p>
                      <p className="text-xs text-zinc-500">
                        {formatRupiah(p.price)}
                        {p.category?.name && ` • ${p.category.name}`}
                        {isExisting && (
                          <span className="ml-1 font-bold text-amber-600">
                            (sudah ditambah)
                          </span>
                        )}
                      </p>
                    </div>
                  </label>
                );
              })}
            </div>
          )}
        </div>

        <div className="mt-4 flex items-center justify-between">
          <span className="text-sm text-zinc-500">
            {selected.size} dipilih
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-zinc-300 bg-white px-5 py-2.5 text-sm font-bold text-zinc-700"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={confirm}
              disabled={selected.size === 0}
              className="rounded-lg bg-natalo-600 px-5 py-2.5 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-50"
            >
              Tambahkan ({selected.size})
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
