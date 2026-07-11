import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { MultiImageUpload } from "@/components/MultiImageUpload";
import { ProductVideoUpload } from "@/components/admin/ProductVideoUpload";
import { VariantEditor } from "@/components/admin/VariantEditor";
import {
  AdminPage,
  Button,
  FormField,
  SectionCard,
  SubmitButton,
} from "@/components/admin/ui";

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

    // Flash Sale dihapus dari form ini — dikelola di /admin/diskon/flash-sale.
    // Existing product.flashSaleEndsAt di DB di-preserve (skip dari update).

    const images = formData
      .getAll("images")
      .map((v) => String(v).trim())
      .filter(Boolean);
    const imageUrl = images[0] ?? null;
    const gallery = images.slice(1);

    const categoryId = String(formData.get("categoryId") || "").trim() || null;
    const brandId = String(formData.get("brandId") || "").trim() || null;

    // Produk varian: field Harga di-`disabled` di UI → TIDAK terkirim di
    // FormData → price=0. Jangan wajibkan price untuk produk varian (harga
    // diatur per-varian), kalau tidak action `return` diam-diam: tak update,
    // tak redirect. Harga tetap wajib untuk produk non-varian.
    if (!name || !description || (!product?.hasVariants && !price)) return;

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
      brandAutoAssigned: boolean;
      sku: string | null;
      price?: number;
      stock?: number;
      weightGram?: number;
      lastEditedAt: Date;
    } = {
      name,
      description,
      imageUrl,
      gallery,
      categoryId,
      brandId,
      brandAutoAssigned: false,
      sku,
      // Tandai admin baru mengedit produk ini → naik ke atas di admin list.
      lastEditedAt: new Date(),
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

  const jumpLinkClass =
    "block rounded-lg px-3 py-2 text-sm font-semibold text-zinc-600 transition hover:bg-natalo-50 hover:text-natalo-700";

  return (
    <AdminPage maxWidth="xl">
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

      <form action={updateProduct} className="mt-5 md:mt-8">
        <div className="grid gap-6 md:grid-cols-[180px_minmax(0,1fr)]">
          {/* Menu lompat — sticky, desktop only. Pakai anchor (#id) supaya
              tak perlu JS. */}
          <nav aria-label="Bagian form" className="hidden md:block">
            <div className="sticky top-6 space-y-1 rounded-2xl border border-zinc-200 bg-white p-2">
              <a href="#dasar" className={jumpLinkClass}>Informasi Dasar</a>
              <a href="#penjualan" className={jumpLinkClass}>Informasi Penjualan</a>
              <a href="#pengiriman" className={jumpLinkClass}>Pengiriman</a>
            </div>
          </nav>

          {/* Konten form */}
          <div className="min-w-0 space-y-6">
            {/* ── Informasi Dasar ── */}
            <div id="dasar" className="scroll-mt-24">
              <SectionCard title="Informasi Dasar">
                <div className="space-y-5">
                  <MultiImageUpload
                    name="images"
                    max={5}
                    defaultValue={[
                      ...(product.imageUrl ? [product.imageUrl] : []),
                      ...product.gallery,
                    ]}
                  />
                  <div className="mt-5 border-t border-zinc-100 pt-4">
                    <p className="mb-2 text-sm font-semibold text-zinc-800">Video Produk</p>
                    <ProductVideoUpload
                      productId={product.id}
                      initial={{
                        videoStatus: product.videoStatus,
                        videoThumbnailUrl: product.videoThumbnailUrl,
                        videoDurationSec: product.videoDurationSec,
                      }}
                    />
                  </div>
                  <Field label="Nama produk" name="name" required defaultValue={product.name} />
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div>
                      <label className="block text-sm font-semibold text-zinc-700">Kategori</label>
                      <select
                        name="categoryId"
                        defaultValue={product.categoryId ?? ""}
                        className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-600"
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
                      <label className="block text-sm font-semibold text-zinc-700">
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
                        className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-600"
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
                  <Field
                    label="Deskripsi"
                    name="description"
                    required
                    defaultValue={product.description}
                    textarea
                  />
                </div>
              </SectionCard>
            </div>

            {/* ── Informasi Penjualan (Variasi + Harga/Stok/SKU) ── */}
            <div id="penjualan" className="scroll-mt-24 space-y-5">
              {/* VariantEditor standalone (state + API sendiri). Anchor
                  id="variants" di-target dari ?from=new. */}
              <div id="variants" className="scroll-mt-24">
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

              <SectionCard title="Harga & Stok">
                <div className="space-y-5">
                  {/* Conditional disable: kalau produk punya varian, Harga/
                      Stok base di-sync dari aggregate varian aktif. */}
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
                        ? "Diatur per varian di tabel Variasi di atas."
                        : undefined
                    }
                  />
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
                    label="SKU Induk"
                    name="sku"
                    defaultValue={product.sku ?? ""}
                    placeholder={product.hasVariants ? "—" : "Mis. PROD-001"}
                    disabled={product.hasVariants}
                    hint={
                      product.hasVariants
                        ? "Tidak diperlukan — SKU diatur per varian di tabel Variasi di atas."
                        : "Opsional. Identifier produk untuk inventory tracking (huruf, angka, _, -)."
                    }
                  />
                </div>
              </SectionCard>
            </div>

            {/* ── Pengiriman ── */}
            <div id="pengiriman" className="scroll-mt-24">
              <SectionCard title="Pengiriman">
                <div className="max-w-xs">
                  <Field
                    label="Berat (gram)"
                    name="weightGram"
                    type="number"
                    defaultValue={String(product.weightGram)}
                    disabled={product.hasVariants}
                    hint={
                      product.hasVariants
                        ? "Diatur per varian di tabel Variasi di atas."
                        : "Berat setelah dikemas — dipakai hitung ongkir."
                    }
                  />
                </div>
              </SectionCard>
            </div>
          </div>
        </div>

        {/* ── Bar Simpan menempel ──
            Sticky di bawah viewport. Di mobile diangkat di atas bottom-nav
            admin (~4rem); di desktop menempel dekat bawah. SubmitButton tetap
            di dalam <form> jadi pending-state jalan. */}
        <div className="sticky bottom-[calc(4rem+env(safe-area-inset-bottom))] z-20 mt-6 flex items-center justify-end gap-3 rounded-2xl border border-zinc-200 bg-white/95 px-4 py-3 shadow-lg backdrop-blur md:bottom-4">
          <Button href="/admin/products" variant="secondary">
            Batal
          </Button>
          <SubmitButton>Simpan perubahan</SubmitButton>
        </div>
      </form>
    </AdminPage>
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
  const cls = `block w-full rounded-xl border px-4 py-3 text-sm outline-none focus:border-natalo-600 ${
    disabled
      ? "cursor-not-allowed border-zinc-200 bg-zinc-50 text-zinc-400"
      : "border-zinc-300"
  }`;
  return (
    <FormField label={label} required={required} hint={hint}>
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
    </FormField>
  );
}
