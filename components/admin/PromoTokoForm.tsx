"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

interface EligibleProduct {
  id: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
  category: { name: string } | null;
}

interface InitialData {
  id?: string;
  name: string;
  discountType: "PERCENTAGE" | "FIXED_AMOUNT";
  discountValue: string;
  maxDiscountCap: string;
  startsAt: string;
  endsAt: string;
  productIds: string[];
  isActive: boolean;
}

interface Props {
  /** Saat edit, kirim initial data dari server. Saat create, undefined. */
  initial?: InitialData;
  /** Saat edit, kirim id supaya endpoint eligible-products bisa exclude. */
  excludeId?: string;
}

const emptyInitial: InitialData = {
  name: "",
  discountType: "PERCENTAGE",
  discountValue: "",
  maxDiscountCap: "",
  startsAt: "",
  endsAt: "",
  productIds: [],
  isActive: true,
};

/**
 * Form Promo Toko — create + edit shared component.
 *
 * Layout 2 section (ala Shopee Seller):
 *  1. Info Promo — nama, periode, tipe diskon, nilai, max cap
 *  2. Produk yang Dipromosikan — multi-checklist dengan filter
 *
 * Validasi inline + banner error global. Submit ke API:
 *  - Create: POST /api/admin/discounts/promo-toko
 *  - Edit  : PUT  /api/admin/discounts/promo-toko/[id]
 * Sukses → router.push /admin/diskon.
 */
export function PromoTokoForm({ initial, excludeId }: Props) {
  const router = useRouter();
  const isEdit = !!initial?.id;
  const data = initial ?? emptyInitial;

  // ── Form state ──────────────────────────────────────────────
  const [name, setName] = useState(data.name);
  const [discountType, setDiscountType] = useState<"PERCENTAGE" | "FIXED_AMOUNT">(
    data.discountType,
  );
  const [discountValue, setDiscountValue] = useState(data.discountValue);
  const [maxDiscountCap, setMaxDiscountCap] = useState(data.maxDiscountCap);
  const [startsAt, setStartsAt] = useState(data.startsAt);
  const [endsAt, setEndsAt] = useState(data.endsAt);
  const [selectedProductIds, setSelectedProductIds] = useState<Set<string>>(
    new Set(data.productIds),
  );

  // ── Product picker state ────────────────────────────────────
  const [products, setProducts] = useState<EligibleProduct[]>([]);
  const [loadingProducts, setLoadingProducts] = useState(false);
  const [productSearch, setProductSearch] = useState("");

  // Fetch eligible products on mount + on search change
  useEffect(() => {
    let cancelled = false;
    const fetchProducts = async () => {
      setLoadingProducts(true);
      try {
        const params = new URLSearchParams();
        if (productSearch.trim()) params.set("q", productSearch.trim());
        if (excludeId) params.set("excludeId", excludeId);
        const res = await fetch(
          `/api/admin/discounts/promo-toko/eligible-products?${params.toString()}`,
        );
        if (!res.ok) throw new Error("Gagal load produk");
        const json = await res.json();
        if (!cancelled) setProducts(json.products ?? []);
      } catch {
        // silent — biarin kosong
      } finally {
        if (!cancelled) setLoadingProducts(false);
      }
    };
    const debounce = setTimeout(fetchProducts, productSearch ? 300 : 0);
    return () => {
      cancelled = true;
      clearTimeout(debounce);
    };
  }, [productSearch, excludeId]);

  // ── Submit state ────────────────────────────────────────────
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
  const dv = parseInt(discountValue || "0", 10);
  if (!dv || dv < 1) errors.discountValue = "Nilai diskon wajib > 0";
  if (discountType === "PERCENTAGE" && dv > 95) {
    errors.discountValue = "Persentase maksimal 95%";
  }
  if (selectedProductIds.size === 0) {
    errors.products = "Pilih minimal 1 produk";
  }

  const canSubmit = Object.keys(errors).length === 0;

  function toggleProduct(productId: string) {
    setSelectedProductIds((prev) => {
      const next = new Set(prev);
      if (next.has(productId)) next.delete(productId);
      else next.add(productId);
      return next;
    });
  }

  function toggleAll() {
    if (selectedProductIds.size === products.length) {
      setSelectedProductIds(new Set());
    } else {
      setSelectedProductIds(new Set(products.map((p) => p.id)));
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
        discountType,
        discountValue: dv,
        maxDiscountCap:
          discountType === "PERCENTAGE" && maxDiscountCap
            ? parseInt(maxDiscountCap, 10)
            : null,
        startsAt: new Date(startsAt).toISOString(),
        endsAt: new Date(endsAt).toISOString(),
        productIds: Array.from(selectedProductIds),
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
            `Produk sudah masuk promo lain: ${json.conflictingPromoNames.join(", ")}. Hapus produk yang konflik dulu.`,
          );
        }
        throw new Error(json.error ?? "Gagal menyimpan");
      }
      router.push("/admin/diskon");
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan");
      setSubmitting(false);
    }
  }

  // Preview harga setelah diskon (untuk produk pertama yang dipilih)
  const previewProduct = products.find((p) => selectedProductIds.has(p.id));
  const previewDiscounted = previewProduct
    ? computeDiscountedPrice(
        previewProduct.price,
        discountType,
        dv,
        maxDiscountCap ? parseInt(maxDiscountCap, 10) : null,
      )
    : null;

  return (
    <div className="mx-auto max-w-4xl px-4 py-5 md:px-8 md:py-10">
      <Link
        href="/admin/diskon"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke Buat Diskon
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
        {isEdit ? "Edit Promo Toko" : "Buat Promo Toko"}
      </h1>

      {/* ─── Section 1: Info Promo ─────────────────────────────────── */}
      <div className="mt-6 rounded-2xl border border-zinc-200 bg-white p-4 md:p-6">
        <h2 className="text-base font-bold text-zinc-900">
          <span className="mr-1 text-red-500">•</span>Info Promo
        </h2>

        <div className="mt-4 space-y-4">
          <Section label="Nama Promo" required>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Cth. Promo Hari Pet Nasional"
              maxLength={200}
              className={`block w-full rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
                showFieldErrors && errors.name
                  ? "border-red-400"
                  : "border-zinc-300"
              }`}
            />
            {showFieldErrors && errors.name && (
              <p className="mt-1 text-xs text-red-500">{errors.name}</p>
            )}
          </Section>

          <div className="grid gap-4 sm:grid-cols-2">
            <Section label="Mulai" required>
              <input
                type="datetime-local"
                value={startsAt}
                onChange={(e) => setStartsAt(e.target.value)}
                className={`block w-full rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
                  showFieldErrors && errors.startsAt
                    ? "border-red-400"
                    : "border-zinc-300"
                }`}
              />
              {showFieldErrors && errors.startsAt && (
                <p className="mt-1 text-xs text-red-500">{errors.startsAt}</p>
              )}
            </Section>
            <Section label="Berakhir" required>
              <input
                type="datetime-local"
                value={endsAt}
                onChange={(e) => setEndsAt(e.target.value)}
                className={`block w-full rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
                  showFieldErrors && errors.endsAt
                    ? "border-red-400"
                    : "border-zinc-300"
                }`}
              />
              {showFieldErrors && errors.endsAt && (
                <p className="mt-1 text-xs text-red-500">{errors.endsAt}</p>
              )}
            </Section>
          </div>

          <Section label="Tipe Diskon" required>
            <div className="flex gap-3">
              <label className="flex flex-1 cursor-pointer items-center gap-2 rounded-xl border border-zinc-200 bg-zinc-50/60 p-3 hover:bg-natalo-50/30">
                <input
                  type="radio"
                  name="discountType"
                  checked={discountType === "PERCENTAGE"}
                  onChange={() => setDiscountType("PERCENTAGE")}
                  className="h-4 w-4"
                />
                <div className="flex-1">
                  <p className="text-sm font-semibold">Persentase (%)</p>
                  <p className="text-xs text-zinc-500">Mis. 20% off</p>
                </div>
              </label>
              <label className="flex flex-1 cursor-pointer items-center gap-2 rounded-xl border border-zinc-200 bg-zinc-50/60 p-3 hover:bg-natalo-50/30">
                <input
                  type="radio"
                  name="discountType"
                  checked={discountType === "FIXED_AMOUNT"}
                  onChange={() => setDiscountType("FIXED_AMOUNT")}
                  className="h-4 w-4"
                />
                <div className="flex-1">
                  <p className="text-sm font-semibold">Nominal (Rp)</p>
                  <p className="text-xs text-zinc-500">Mis. Rp 5.000 off</p>
                </div>
              </label>
            </div>
          </Section>

          <div className="grid gap-4 sm:grid-cols-2">
            <Section
              label={`Nilai Diskon${discountType === "PERCENTAGE" ? " (%)" : " (Rp)"}`}
              required
            >
              <input
                type="number"
                value={discountValue}
                onChange={(e) => setDiscountValue(e.target.value)}
                placeholder={discountType === "PERCENTAGE" ? "20" : "5000"}
                min={1}
                max={discountType === "PERCENTAGE" ? 95 : undefined}
                className={`block w-full rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
                  showFieldErrors && errors.discountValue
                    ? "border-red-400"
                    : "border-zinc-300"
                }`}
              />
              {showFieldErrors && errors.discountValue && (
                <p className="mt-1 text-xs text-red-500">
                  {errors.discountValue}
                </p>
              )}
            </Section>
            {discountType === "PERCENTAGE" && (
              <Section
                label="Max Discount Cap (Rp)"
                hint="Opsional. Batas atas diskon untuk persentase besar (mis. 20% max Rp 20.000)."
              >
                <input
                  type="number"
                  value={maxDiscountCap}
                  onChange={(e) => setMaxDiscountCap(e.target.value)}
                  placeholder="Opsional"
                  min={0}
                  className="block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600"
                />
              </Section>
            )}
          </div>
        </div>
      </div>

      {/* ─── Section 2: Produk yang Dipromosikan ───────────────────── */}
      <div className="mt-6 rounded-2xl border border-zinc-200 bg-white p-4 md:p-6">
        <div className="flex items-baseline justify-between">
          <h2 className="text-base font-bold text-zinc-900">
            <span className="mr-1 text-red-500">•</span>Produk yang Dipromosikan
          </h2>
          <span className="text-xs font-semibold text-zinc-500">
            {selectedProductIds.size} dipilih dari {products.length}
          </span>
        </div>

        {/* Search bar */}
        <div className="mt-3 flex gap-2">
          <input
            type="text"
            value={productSearch}
            onChange={(e) => setProductSearch(e.target.value)}
            placeholder="🔍 Cari nama produk..."
            className="flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
          />
          <button
            type="button"
            onClick={toggleAll}
            className="rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm font-bold text-zinc-700 hover:bg-zinc-50"
          >
            {selectedProductIds.size === products.length && products.length > 0
              ? "Batalkan Semua"
              : "Pilih Semua"}
          </button>
        </div>

        {/* Product list */}
        <div className="mt-3 max-h-96 overflow-y-auto rounded-xl border border-zinc-200">
          {loadingProducts ? (
            <p className="px-4 py-8 text-center text-sm text-zinc-400">
              Memuat produk...
            </p>
          ) : products.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-zinc-400">
              {productSearch
                ? "Tidak ada produk cocok dengan pencarian."
                : "Semua produk sedang di Promo Toko aktif lain. Tunggu promo berakhir dulu."}
            </p>
          ) : (
            <div className="divide-y divide-zinc-100">
              {products.map((p) => (
                <label
                  key={p.id}
                  className="flex cursor-pointer items-center gap-3 px-4 py-2.5 hover:bg-zinc-50"
                >
                  <input
                    type="checkbox"
                    checked={selectedProductIds.has(p.id)}
                    onChange={() => toggleProduct(p.id)}
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
                    <p className="truncate text-sm font-semibold text-zinc-900">
                      {p.name}
                    </p>
                    <p className="text-xs text-zinc-500">
                      Rp {p.price.toLocaleString("id-ID")}
                      {p.category?.name && (
                        <>
                          {" "}
                          • <span>{p.category.name}</span>
                        </>
                      )}
                      {p.stock !== undefined && (
                        <> • Stok: {p.stock}</>
                      )}
                    </p>
                  </div>
                </label>
              ))}
            </div>
          )}
        </div>

        {showFieldErrors && errors.products && (
          <p className="mt-2 text-xs text-red-500">{errors.products}</p>
        )}
      </div>

      {/* ─── Preview ───────────────────────────────────────────────── */}
      {previewProduct && previewDiscounted !== null && (
        <div className="mt-6 rounded-2xl border border-emerald-200 bg-emerald-50/50 p-4">
          <p className="text-xs font-bold uppercase tracking-wide text-emerald-700">
            Preview Harga Setelah Promo
          </p>
          <div className="mt-2 flex items-center gap-3">
            {previewProduct.imageUrl && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={previewProduct.imageUrl}
                alt=""
                className="h-12 w-12 rounded border border-emerald-200 object-cover"
              />
            )}
            <div>
              <p className="text-sm font-semibold text-zinc-900">
                {previewProduct.name}
              </p>
              <p className="mt-0.5 text-sm">
                <span className="text-zinc-400 line-through">
                  Rp {previewProduct.price.toLocaleString("id-ID")}
                </span>
                {"  "}
                <span className="font-black text-emerald-700">
                  Rp {previewDiscounted.toLocaleString("id-ID")}
                </span>
                <span className="ml-2 inline-block rounded bg-red-500 px-2 py-0.5 text-[10px] font-bold text-white">
                  {discountType === "PERCENTAGE"
                    ? `-${dv}%`
                    : `Hemat Rp ${dv.toLocaleString("id-ID")}`}
                </span>
              </p>
            </div>
          </div>
        </div>
      )}

      {/* ─── Error banner ──────────────────────────────────────────── */}
      {error && (
        <div className="mt-6 flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-4">
          <span className="text-red-500">⚠</span>
          <p className="flex-1 text-sm font-semibold text-red-700">{error}</p>
        </div>
      )}

      {/* ─── Submit ────────────────────────────────────────────────── */}
      <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row">
        <Link
          href="/admin/diskon"
          className="rounded-full border border-zinc-300 px-6 py-3 text-center text-sm font-bold"
        >
          Batal
        </Link>
        <button
          type="button"
          onClick={handleSubmit}
          disabled={submitting}
          className="flex-1 rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-50 sm:flex-none"
        >
          {submitting
            ? "Menyimpan..."
            : isEdit
              ? "Simpan Perubahan"
              : "Simpan Promo"}
        </button>
      </div>
    </div>
  );
}

function Section({
  label,
  required,
  hint,
  children,
}: {
  label: string;
  required?: boolean;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="block text-sm font-semibold text-zinc-700">
        {required && <span className="mr-1 text-red-500">•</span>}
        {label}
      </label>
      <div className="mt-1.5">{children}</div>
      {hint && <p className="mt-1 text-xs text-zinc-500">ⓘ {hint}</p>}
    </div>
  );
}

// Kalkulasi harga setelah diskon — pure function, sync dengan logic
// yang akan dipakai di Phase 1D (customer-side price calculator).
function computeDiscountedPrice(
  originalPrice: number,
  type: "PERCENTAGE" | "FIXED_AMOUNT",
  value: number,
  maxCap: number | null,
): number {
  if (!value || value <= 0) return originalPrice;
  if (type === "PERCENTAGE") {
    let off = Math.round((originalPrice * value) / 100);
    if (maxCap !== null && maxCap > 0 && off > maxCap) off = maxCap;
    return Math.max(0, originalPrice - off);
  }
  // FIXED_AMOUNT
  return Math.max(0, originalPrice - value);
}
