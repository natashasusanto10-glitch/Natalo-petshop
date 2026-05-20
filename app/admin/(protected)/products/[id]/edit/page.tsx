import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { MultiImageUpload } from "@/components/MultiImageUpload";
import { VariantEditor } from "@/components/admin/VariantEditor";

export default async function AdminProductEditPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { id } = await params;
  const { from } = await searchParams;
  // Hint dari /new redirect — show success banner + nudge ke variant editor.
  const justCreated = from === "new";

  const [product, categories, brands] = await Promise.all([
    prisma.product.findUnique({
      where: { id },
      include: {
        variantAttrs: {
          orderBy: { position: "asc" },
          include: { options: { orderBy: { position: "asc" } } },
        },
        variants: {
          where: { deletedAt: null },
          include: { options: { select: { optionId: true } } },
          orderBy: { createdAt: "asc" },
        },
      },
    }),
    prisma.category.findMany({ orderBy: { name: "asc" } }),
    prisma.brand.findMany({ orderBy: { name: "asc" } }),
  ]);

  if (!product) return notFound();

  async function updateProduct(formData: FormData) {
    "use server";

    const name = String(formData.get("name") || "").trim();
    const description = String(formData.get("description") || "").trim();
    const price = parseInt(String(formData.get("price") || "0"), 10);
    const stock = parseInt(String(formData.get("stock") || "0"), 10);
    const weightGram = parseInt(String(formData.get("weightGram") || "500"), 10);
    // SKU Induk — hanya valid untuk produk tanpa varian. Empty string
    // = clear, null = preserve (admin tidak isi). Validasi format
    // huruf/angka/_/- saja.
    const skuRaw = String(formData.get("sku") || "").trim().toUpperCase();
    const sku = product?.hasVariants
      ? null  // produk dengan varian: SKU Induk selalu null
      : skuRaw && /^[A-Za-z0-9_\-]+$/.test(skuRaw)
        ? skuRaw
        : null;
    // discountPrice tidak diambil dari form lagi — fitur diskon akan
    // dipindah ke halaman terpisah (/admin/diskon ala Shopee Promosi).
    // Existing discountPrice di DB di-preserve (tidak di-update).

    // Flash Sale explicit end time. Input HTML datetime-local return
    // string format "YYYY-MM-DDTHH:MM" tanpa timezone — interpret as
    // local time, serialize ke UTC saat save. Empty string = NULL
    // (admin tidak set / clear field) → auto-include via threshold.
    const flashSaleEndsAtRaw = String(formData.get("flashSaleEndsAt") || "").trim();
    const flashSaleEndsAt = flashSaleEndsAtRaw ? new Date(flashSaleEndsAtRaw) : null;

    const images = formData
      .getAll("images")
      .map((v) => String(v).trim())
      .filter(Boolean);
    const imageUrl = images[0] ?? null;
    const gallery = images.slice(1);

    const categoryId = String(formData.get("categoryId") || "").trim() || null;
    const brandId = String(formData.get("brandId") || "").trim() || null;

    if (!name || !description || !price) return;

    // Capture stock SEBELUM update untuk detect transition 0 → >0
    // (restock trigger). Hanya fire push kalau stock memang naik dari 0.
    const wasOutOfStock = product?.stock === 0;

    // Kalau produk punya varian, Product.price/stock/weightGram di-sync
    // dari aggregate varian aktif (lihat PUT variants endpoint). Admin
    // tidak bisa override dari form ini — field-nya disabled di UI.
    // Skip 3 field tsb dari update payload untuk preserve aggregate.
    const baseData: {
      name: string;
      description: string;
      imageUrl: string | null;
      gallery: string[];
      categoryId: string | null;
      brandId: string | null;
      flashSaleEndsAt: Date | null;
      brandAutoAssigned: boolean;
      sku: string | null;
      price?: number;
      stock?: number;
      weightGram?: number;
    } = {
      name,
      description,
      imageUrl,
      gallery,
      categoryId,
      brandId,
      flashSaleEndsAt,
      brandAutoAssigned: false,
      sku,
    };
    if (!product?.hasVariants) {
      baseData.price = price;
      baseData.stock = stock;
      baseData.weightGram = weightGram;
    }
    await prisma.product.update({ where: { id }, data: baseData });

    // Sync ke search index (non-blocking)
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(id).catch(() => {});

    // Restock trigger — kalau product berubah dari stock=0 ke stock>0,
    // notify semua subscriber yang mendaftar lewat "Beri tahu saat tersedia".
    // Hanya untuk produk tanpa variant (variantId=null subscription). Untuk
    // produk dengan variant, trigger di-handle di variants PUT route.
    if (wasOutOfStock && stock > 0) {
      const { sendBackInStockPush } = await import("@/lib/push-marketing");
      await sendBackInStockPush(id, null).catch((err) => {
        console.warn("[admin/products edit] back-in-stock push failed:", err);
      });
    }

    redirect("/admin/products");
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-5 md:py-10">
      <Link href="/admin/products" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
        ← Kembali ke produk
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">Edit Produk</h1>
      <p className="mt-1 truncate text-sm text-zinc-500">{product.slug}</p>

      {justCreated && (
        <div className="mt-4 flex items-start gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 p-4">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-emerald-500 text-white">
            ✓
          </div>
          <div className="flex-1 text-sm">
            <p className="font-bold text-emerald-900">
              Produk berhasil dibuat
            </p>
            <p className="mt-0.5 text-emerald-800">
              Tambah variasi produk (warna, ukuran, dsb.) di bagian{" "}
              <a
                href="#variants"
                className="font-bold underline underline-offset-2 hover:text-emerald-700"
              >
                Variasi Produk ↓
              </a>{" "}
              di bawah, atau klik <strong>Simpan perubahan</strong> kalau
              produk ini tidak punya varian.
            </p>
          </div>
        </div>
      )}

      <form action={updateProduct} className="mt-5 space-y-5 md:mt-8">
        {/* ── 1. Foto Produk ─────────────────────────────────────── */}
        <MultiImageUpload
          name="images"
          max={5}
          defaultValue={[
            ...(product.imageUrl ? [product.imageUrl] : []),
            ...product.gallery,
          ]}
        />

        {/* ── 2. Nama Produk ─────────────────────────────────────── */}
        <Field label="Nama produk" name="name" required defaultValue={product.name} />

        {/* ── 3. Kategori | Brand ────────────────────────────────── */}
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-sm font-medium text-zinc-700">Kategori</label>
            <select
              name="categoryId"
              defaultValue={product.categoryId ?? ""}
              className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
            >
              <option value="">Tanpa kategori</option>
              {categories.map((cat) => (
                <option key={cat.id} value={cat.id}>
                  {cat.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-zinc-700">
              Brand{" "}
              {product.brandAutoAssigned && (
                <span className="ml-1 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-700">
                  auto — verify
                </span>
              )}
            </label>
            <select
              name="brandId"
              defaultValue={product.brandId ?? ""}
              className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
            >
              <option value="">Tanpa brand</option>
              {brands.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* ── 4. Deskripsi ───────────────────────────────────────── */}
        <Field
          label="Deskripsi"
          name="description"
          required
          defaultValue={product.description}
          textarea
        />

        {/* ── 5. Variasi — render di section dedicated di bawah form
            (lihat <VariantEditor /> di bawah form ini). Tidak masuk
            ke form action ini karena VariantEditor pakai API call
            sendiri. */}

        {/* ── 6. Harga Satuan ────────────────────────────────────── */}
        {/* Conditional disable: kalau produk punya varian, Harga base
            di-sync dari MIN(varian aktif) — admin tidak bisa override.
            Field tetap visible supaya admin tahu value saat ini. */}
        <Field
          label={
            product.hasVariants
              ? "Harga Satuan (Rp) — diatur per varian"
              : "Harga Satuan (Rp)"
          }
          name="price"
          type="number"
          required={!product.hasVariants}
          defaultValue={String(product.price)}
          disabled={product.hasVariants}
          hint={
            product.hasVariants
              ? "Diatur per varian di tabel Variasi di bawah."
              : undefined
          }
        />

        {/* ── 7. Stok | 8. Berat ─────────────────────────────────── */}
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label={product.hasVariants ? "Stok (total varian)" : "Stok"}
            name="stock"
            type="number"
            defaultValue={String(product.stock)}
            disabled={product.hasVariants}
            hint={
              product.hasVariants
                ? `Total ${product.stock} dari semua varian aktif.`
                : undefined
            }
          />
          <Field
            label="Berat (gram)"
            name="weightGram"
            type="number"
            defaultValue={String(product.weightGram)}
            disabled={product.hasVariants}
            hint={
              product.hasVariants
                ? "Diatur per varian di tabel Variasi di bawah."
                : undefined
            }
          />
        </div>

        {/* ── 9. SKU Induk ─────────────────────────────────────────
            Identifier opsional untuk produk single. Disabled saat
            varian aktif (SKU dikelola per-varian di tabel Variasi). */}
        <Field
          label="SKU Induk"
          name="sku"
          defaultValue={product.sku ?? ""}
          placeholder={product.hasVariants ? "—" : "Mis. PROD-001"}
          disabled={product.hasVariants}
          hint={
            product.hasVariants
              ? "Tidak diperlukan — SKU diatur per varian di tabel Variasi di bawah."
              : "Opsional. Identifier produk untuk inventory tracking (huruf, angka, _, -)."
          }
        />

        {/* Flash Sale explicit end time. Kalau di-set, produk ini SELALU
            masuk Flash Sale section di home apapun discount %-nya, dengan
            countdown timer. Kalau kosong, produk masuk Flash Sale section
            hanya kalau discount >= 20% (auto-include). */}
        <div className="rounded-xl border border-amber-200 bg-amber-50/50 p-4">
          <label className="block text-sm font-bold text-amber-900">
            ⚡ Flash Sale berakhir (opsional)
          </label>
          <p className="mt-1 text-xs text-amber-800">
            Set kalau ini produk Flash Sale dengan countdown timer. Setelah
            waktu ini, produk otomatis keluar dari Flash Sale section.
            Kosongkan kalau produk tidak Flash Sale (diskon ≥20% tetap
            otomatis masuk).
          </p>
          <input
            type="datetime-local"
            name="flashSaleEndsAt"
            defaultValue={
              product.flashSaleEndsAt
                ? new Date(
                    product.flashSaleEndsAt.getTime() -
                      product.flashSaleEndsAt.getTimezoneOffset() * 60000,
                  )
                    .toISOString()
                    .slice(0, 16)
                : ""
            }
            className="mt-2 block w-full rounded-xl border border-amber-300 bg-white px-4 py-3 text-sm outline-none focus:border-amber-600"
          />
        </div>

        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Link
            href="/admin/products"
            className="rounded-full border border-zinc-300 px-6 py-3 text-center text-sm font-bold"
          >
            Batal
          </Link>
          <button
            type="submit"
            className="flex-1 rounded-full bg-zinc-950 px-6 py-3 text-sm font-bold text-white sm:flex-none"
          >
            Simpan perubahan
          </button>
        </div>
      </form>

      {/* ── Variant Editor (client component) ──
          Anchor `id="variants"` di-target dari /admin/products/new redirect
          (?from=new#variants) supaya browser scroll otomatis ke editor
          variasi setelah produk baru dibuat. */}
      <div id="variants" className="scroll-mt-6">
      <VariantEditor
        productId={id}
        initialHasVariants={product.hasVariants}
        initialAttributes={product.variantAttrs.map((a) => ({
          id: a.id,
          name: a.name,
          position: a.position,
          options: a.options.map((o) => ({
            id: o.id,
            value: o.value,
            position: o.position,
          })),
        }))}
        initialVariants={product.variants.map((v) => ({
          id: v.id,
          price: v.price,
          stock: v.stock,
          weightGram: v.weightGram,
          sku: v.sku,
          imageUrl: v.imageUrl,
          isActive: v.isActive,
          options: v.options,
        }))}
      />
      </div>
    </div>
  );
}

function Field({
  label,
  name,
  type = "text",
  required,
  placeholder,
  textarea,
  defaultValue,
  disabled,
  hint,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
  placeholder?: string;
  textarea?: boolean;
  defaultValue?: string;
  disabled?: boolean;
  hint?: string;
}) {
  const cls = `mt-1 block w-full rounded-xl border px-4 py-3 text-sm outline-none focus:border-zinc-600 ${
    disabled
      ? "cursor-not-allowed border-zinc-200 bg-zinc-50 text-zinc-400"
      : "border-zinc-300"
  }`;
  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">
        {label}
        {required && <span className="ml-1 text-red-500">*</span>}
      </label>
      {textarea ? (
        <textarea
          name={name}
          required={required}
          placeholder={placeholder}
          defaultValue={defaultValue}
          rows={4}
          disabled={disabled}
          className={cls}
        />
      ) : (
        <input
          type={type}
          name={name}
          required={required}
          placeholder={placeholder}
          defaultValue={defaultValue}
          disabled={disabled}
          className={cls}
        />
      )}
      {hint && <p className="mt-1 text-xs text-zinc-500">ⓘ {hint}</p>}
    </div>
  );
}
