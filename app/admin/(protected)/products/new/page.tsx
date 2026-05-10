import Link from "next/link";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { MultiImageUpload } from "@/components/MultiImageUpload";

function toSlug(name: string) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

export default async function AdminProductNewPage() {
  const [categories, brands] = await Promise.all([
    prisma.category.findMany({ orderBy: { name: "asc" } }),
    prisma.brand.findMany({ orderBy: { name: "asc" } }),
  ]);

  async function createProduct(formData: FormData) {
    "use server";

    const name = String(formData.get("name") || "").trim();
    const description = String(formData.get("description") || "").trim();
    const price = parseInt(String(formData.get("price") || "0"), 10);
    const discountPrice = formData.get("discountPrice")
      ? parseInt(String(formData.get("discountPrice")), 10)
      : null;
    const stock = parseInt(String(formData.get("stock") || "0"), 10);
    const weightGram = parseInt(String(formData.get("weightGram") || "500"), 10);

    // Multi-image: ambil semua URL dari field "images" yg di-submit oleh
    // MultiImageUpload sbg array (1 hidden input per gambar).
    const images = formData
      .getAll("images")
      .map((v) => String(v).trim())
      .filter(Boolean);
    const imageUrl = images[0] ?? null;
    const gallery = images.slice(1);

    const categoryId = String(formData.get("categoryId") || "").trim() || null;
    const brandId = String(formData.get("brandId") || "").trim() || null;

    if (!name || !description || !price) return;

    let slug = toSlug(name);
    const existing = await prisma.product.findUnique({ where: { slug } });
    if (existing) slug = `${slug}-${Date.now()}`;

    const created = await prisma.product.create({
      data: {
        name,
        slug,
        description,
        price,
        discountPrice,
        stock,
        weightGram,
        imageUrl,
        gallery,
        categoryId,
        brandId,
      },
    });

    // Sync ke search index (non-blocking)
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(created.id).catch(() => {});

    redirect("/admin/products");
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <Link href="/admin/products" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
        ← Kembali ke produk
      </Link>
      <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">Tambah Produk</h1>

      <form action={createProduct} className="mt-8 space-y-5">
        <Field label="Nama produk" name="name" required placeholder="Contoh: Pakan Ikan Neon Tetra" />
        <Field
          label="Deskripsi"
          name="description"
          required
          placeholder="Deskripsi singkat produk..."
          textarea
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Harga normal (Rp)" name="price" type="number" required placeholder="50000" />
          <Field label="Harga diskon (Rp)" name="discountPrice" type="number" placeholder="45000" />
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Stok" name="stock" type="number" placeholder="0" defaultValue="0" />
          <Field label="Berat (gram)" name="weightGram" type="number" placeholder="500" defaultValue="500" />
        </div>

        <MultiImageUpload name="images" max={5} />

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-sm font-medium text-zinc-700">Kategori</label>
            <select
              name="categoryId"
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
            <label className="block text-sm font-medium text-zinc-700">Brand</label>
            <select
              name="brandId"
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

        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            className="rounded-full bg-zinc-950 px-6 py-3 text-sm font-bold text-white"
          >
            Simpan produk
          </button>
          <Link
            href="/admin/products"
            className="rounded-full border border-zinc-300 px-6 py-3 text-sm font-bold"
          >
            Batal
          </Link>
        </div>
      </form>
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
        <textarea name={name} required={required} placeholder={placeholder} rows={4} className={cls} />
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
