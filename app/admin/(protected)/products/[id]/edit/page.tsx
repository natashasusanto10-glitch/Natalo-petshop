import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { MultiImageUpload } from "@/components/MultiImageUpload";
import { VariantEditor } from "@/components/admin/VariantEditor";

export default async function AdminProductEditPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

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
    const discountPrice = formData.get("discountPrice")
      ? parseInt(String(formData.get("discountPrice")), 10)
      : null;
    const stock = parseInt(String(formData.get("stock") || "0"), 10);
    const weightGram = parseInt(String(formData.get("weightGram") || "500"), 10);

    const images = formData
      .getAll("images")
      .map((v) => String(v).trim())
      .filter(Boolean);
    const imageUrl = images[0] ?? null;
    const gallery = images.slice(1);

    const categoryId = String(formData.get("categoryId") || "").trim() || null;
    const brandId = String(formData.get("brandId") || "").trim() || null;

    if (!name || !description || !price) return;

    await prisma.product.update({
      where: { id },
      data: {
        name, description, price, discountPrice, stock, weightGram, imageUrl, gallery, categoryId,
        brandId,
        // User assign manual = bukan auto lagi
        brandAutoAssigned: false,
      },
    });

    // Sync ke search index (non-blocking)
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(id).catch(() => {});

    redirect("/admin/products");
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-5 md:py-10">
      <Link href="/admin/products" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
        ← Kembali ke produk
      </Link>
      <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">Edit Produk</h1>
      <p className="mt-1 truncate text-sm text-zinc-500">{product.slug}</p>

      <form action={updateProduct} className="mt-5 space-y-5 md:mt-8">
        <Field label="Nama produk" name="name" required defaultValue={product.name} />
        <Field
          label="Deskripsi"
          name="description"
          required
          defaultValue={product.description}
          textarea
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Harga normal (Rp)" name="price" type="number" required defaultValue={String(product.price)} />
          <Field
            label="Harga diskon (Rp)"
            name="discountPrice"
            type="number"
            defaultValue={product.discountPrice ? String(product.discountPrice) : ""}
          />
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Stok" name="stock" type="number" defaultValue={String(product.stock)} />
          <Field label="Berat (gram)" name="weightGram" type="number" defaultValue={String(product.weightGram)} />
        </div>

        <MultiImageUpload
          name="images"
          max={5}
          defaultValue={[
            ...(product.imageUrl ? [product.imageUrl] : []),
            ...product.gallery,
          ]}
        />

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

      {/* ── Variant Editor (client component) ── */}
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
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
  placeholder?: string;
  textarea?: boolean;
  defaultValue?: string;
}) {
  const cls =
    "mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600";
  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">
        {label}
        {required && <span className="ml-1 text-red-500">*</span>}
      </label>
      {textarea ? (
        <textarea name={name} required={required} placeholder={placeholder} defaultValue={defaultValue} rows={4} className={cls} />
      ) : (
        <input
          type={type}
          name={name}
          required={required}
          placeholder={placeholder}
          defaultValue={defaultValue}
          className={cls}
        />
      )}
    </div>
  );
}
