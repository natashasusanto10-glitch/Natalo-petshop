"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import Link from "next/link";
import { MultiImageUpload } from "@/components/MultiImageUpload";
import {
  VariantEditor,
  type VariantEditorDraftPayload,
} from "@/components/admin/VariantEditor";

interface Props {
  categories: Array<{ id: string; name: string }>;
  brands: Array<{ id: string; name: string }>;
}

/**
 * Form tambah produk baru — Shopee Seller style.
 *
 * Field order (sesuai spec admin):
 *  1. Foto Produk (slot 1 = cover, max 5)
 *  2. Nama Produk
 *  3. Kategori | Brand
 *  4. Deskripsi
 *  5. Variasi section (VariantEditor draft mode — collect state ke parent)
 *  6. Harga Satuan      ┐
 *  7. Stok              ├─ disabled saat varian aktif (data dari per-varian)
 *  8. Berat (gram)      ┘
 *
 * Submit: POST /api/admin/products dengan payload lengkap (product +
 * variants). Backend atomic transaction — kalau varian gagal, product
 * ikut rollback. Setelah sukses redirect ke /admin/products (list).
 */
export function NewProductForm({ categories, brands }: Props) {
  const router = useRouter();

  // Product fields
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [images, setImages] = useState<string[]>([]);
  const [categoryId, setCategoryId] = useState("");
  const [brandId, setBrandId] = useState("");
  const [price, setPrice] = useState("");
  const [stock, setStock] = useState("0");
  const [weightGram, setWeightGram] = useState("500");
  // SKU Induk — identifier opsional untuk produk single (tanpa varian).
  // Saat varian aktif, field ini di-disable + cleared, karena SKU dikelola
  // per-varian di tabel di atas.
  const [sku, setSku] = useState("");

  // Variant state (di-emit oleh VariantEditor via onChange)
  const [variantData, setVariantData] = useState<VariantEditorDraftPayload>({
    hasVariants: false,
    attributes: [],
    variants: [],
  });

  // UI state
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");
  const [showFieldErrors, setShowFieldErrors] = useState(false);

  const hasVariants = variantData.hasVariants;

  // Display total stock dari sum varian aktif (display only — tidak ke DB
  // langsung; backend yang hitung agregat saat save). UX: admin tahu
  // berapa total stok sebelum klik Simpan.
  const totalVariantStock = variantData.variants
    .filter((v) => v.isActive)
    .reduce((sum, v) => sum + (Number(v.stock) || 0), 0);

  // Validasi inline. Wajib field hanya yang relevant dengan mode.
  const baseFieldsValid =
    name.trim().length > 0 && description.trim().length > 0;
  const priceStockWeightValid = hasVariants
    ? true
    : Number(price) > 0 && Number(stock) >= 0 && Number(weightGram) > 0;
  const variantValid = !hasVariants
    ? true
    : variantData.attributes.length > 0 &&
      variantData.attributes.every((a) => a.name.trim() && a.options.length > 0) &&
      variantData.variants.length > 0 &&
      variantData.variants.some((v) => v.isActive) &&
      variantData.variants
        .filter((v) => v.isActive)
        .every((v) => v.price > 0 && v.weightGram > 0);

  const canSubmit = baseFieldsValid && priceStockWeightValid && variantValid;

  async function handleSubmit() {
    setShowFieldErrors(true);
    setSubmitError("");

    if (!canSubmit) {
      setSubmitError(
        "Gagal menyimpan karena terdapat kesalahan, edit dahulu dan coba lagi.",
      );
      return;
    }

    setSubmitting(true);
    try {
      const payload = {
        name: name.trim(),
        description: description.trim(),
        // Saat varian aktif, server akan override price/stock/weightGram
        // dari aggregate varian aktif (min price, sum stock, default
        // weight). Kita kirim 0 / default sebagai placeholder.
        price: hasVariants ? 0 : Math.max(0, parseInt(price || "0", 10)),
        stock: hasVariants ? 0 : Math.max(0, parseInt(stock || "0", 10)),
        weightGram: hasVariants ? 500 : Math.max(1, parseInt(weightGram || "500", 10)),
        imageUrl: images[0] || undefined,
        gallery: images.slice(1),
        categoryId: categoryId || undefined,
        brandId: brandId || undefined,
        // SKU Induk hanya dikirim saat tidak ada varian (single product).
        // Saat varian aktif, server akan null-kan field ini supaya tidak
        // bentrok dengan SKU per-varian.
        sku: !hasVariants && sku.trim() ? sku.trim() : undefined,
        hasVariants,
        attributes: hasVariants ? variantData.attributes : [],
        variants: hasVariants ? variantData.variants : [],
      };

      const res = await fetch("/api/admin/products", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error ?? "Gagal menyimpan produk");
      }
      // Sukses — redirect ke list. Pakai router.push + refresh supaya
      // server component list re-fetch dan tampilin produk baru.
      router.push("/admin/products");
      router.refresh();
    } catch (e) {
      setSubmitError(
        e instanceof Error
          ? e.message
          : "Gagal menyimpan produk. Coba lagi.",
      );
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-7xl px-4 py-5 md:px-8 md:py-10">
      <Link
        href="/admin/products"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke produk
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
        Tambah Produk
      </h1>

      <div className="mt-5 space-y-5 md:mt-8">
        {/* ─── 1. Foto Produk ─────────────────────────────────────── */}
        <Section
          label="Foto Produk"
          required
          hint="Foto pertama = cover (thumbnail di list & search). Max 5 foto, 2 MB per file."
        >
          <MultiImageUpload
            name="images"
            max={5}
            label=""
            defaultValue={images}
            onChange={setImages}
          />
        </Section>

        {/* ─── 2. Nama Produk ─────────────────────────────────────── */}
        <Section label="Nama Produk" required>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Cth. Animal&Co Dog Snack Knotted Bone"
            className={`block w-full rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
              showFieldErrors && !name.trim()
                ? "border-red-400"
                : "border-zinc-300"
            }`}
          />
          {showFieldErrors && !name.trim() && (
            <p className="mt-1 text-xs text-red-500">Kolom wajib diisi</p>
          )}
        </Section>

        {/* ─── 3. Kategori | Brand ────────────────────────────────── */}
        <div className="grid gap-4 sm:grid-cols-2">
          <Section label="Kategori">
            <select
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              className="block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600"
            >
              <option value="">Tanpa kategori</option>
              {categories.map((cat) => (
                <option key={cat.id} value={cat.id}>
                  {cat.name}
                </option>
              ))}
            </select>
          </Section>
          <Section label="Brand">
            <select
              value={brandId}
              onChange={(e) => setBrandId(e.target.value)}
              className="block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600"
            >
              <option value="">Tanpa brand</option>
              {brands.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </Section>
        </div>

        {/* ─── 4. Deskripsi ───────────────────────────────────────── */}
        <Section label="Deskripsi" required>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Deskripsi singkat produk..."
            rows={4}
            className={`block w-full rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
              showFieldErrors && !description.trim()
                ? "border-red-400"
                : "border-zinc-300"
            }`}
          />
          {showFieldErrors && !description.trim() && (
            <p className="mt-1 text-xs text-red-500">Kolom wajib diisi</p>
          )}
        </Section>

        {/* ─── 5. Variasi (draft mode — emit ke variantData state) ── */}
        <VariantEditor
          initialHasVariants={false}
          initialAttributes={[]}
          initialVariants={[]}
          onChange={setVariantData}
        />

        {/* ─── 6. Harga Satuan ────────────────────────────────────── */}
        <Section
          label="Harga Satuan (Rp)"
          required={!hasVariants}
          hint={
            hasVariants
              ? "Diatur per varian di tabel di atas."
              : undefined
          }
        >
          <input
            type="number"
            value={hasVariants ? "" : price}
            onChange={(e) => setPrice(e.target.value)}
            disabled={hasVariants}
            placeholder={hasVariants ? "—" : "25000"}
            min={0}
            className={`block w-full rounded-xl border bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400 ${
              showFieldErrors && !hasVariants && Number(price) <= 0
                ? "border-red-400"
                : "border-zinc-300"
            }`}
          />
          {showFieldErrors && !hasVariants && Number(price) <= 0 && (
            <p className="mt-1 text-xs text-red-500">Harga harus lebih dari 0</p>
          )}
        </Section>

        {/* ─── 7. Stok | 8. Berat ────────────────────────────────── */}
        <div className="grid gap-4 sm:grid-cols-2">
          <Section
            label="Stok"
            required={!hasVariants}
            hint={
              hasVariants
                ? `Total: ${totalVariantStock} dari semua varian aktif.`
                : undefined
            }
          >
            <input
              type="number"
              value={hasVariants ? "" : stock}
              onChange={(e) => setStock(e.target.value)}
              disabled={hasVariants}
              placeholder={hasVariants ? "—" : "0"}
              min={0}
              className="block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400"
            />
          </Section>
          <Section
            label="Berat (gram)"
            required={!hasVariants}
            hint={
              hasVariants
                ? "Diatur per varian di tabel di atas."
                : undefined
            }
          >
            <input
              type="number"
              value={hasVariants ? "" : weightGram}
              onChange={(e) => setWeightGram(e.target.value)}
              disabled={hasVariants}
              placeholder={hasVariants ? "—" : "500"}
              min={1}
              className="block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400"
            />
          </Section>
        </div>

        {/* ─── 9. SKU Induk ─────────────────────────────────────────
            Identifier opsional untuk produk single (tanpa varian).
            Saat varian aktif, field disabled karena SKU per-varian
            ada di tabel Variasi di atas. */}
        <Section
          label="SKU Induk"
          hint={
            hasVariants
              ? "Tidak diperlukan — SKU diatur per varian di tabel di atas."
              : "Opsional. Identifier produk untuk inventory tracking (huruf, angka, _, -)."
          }
        >
          <input
            type="text"
            value={hasVariants ? "" : sku}
            onChange={(e) => setSku(e.target.value.toUpperCase())}
            disabled={hasVariants}
            placeholder={hasVariants ? "—" : "Mis. PROD-001"}
            maxLength={80}
            className="block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm outline-none focus:border-natalo-600 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400"
          />
        </Section>

        {/* ─── Error banner ───────────────────────────────────────── */}
        {submitError && (
          <div className="flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-4">
            <span className="text-red-500">⚠</span>
            <p className="flex-1 text-sm font-semibold text-red-700">
              {submitError}
            </p>
          </div>
        )}

        {/* ─── Submit buttons ─────────────────────────────────────── */}
        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Link
            href="/admin/products"
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
            {submitting ? "Menyimpan..." : "Simpan Produk"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Sub-component: Section wrapper with label + required dot + hint ─
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
