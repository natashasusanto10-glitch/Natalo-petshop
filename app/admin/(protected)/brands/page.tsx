import Link from "next/link";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";

function slugify(name: string) {
  return name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

export default async function AdminBrandsPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const brands = await prisma.brand.findMany({
    orderBy: { name: "asc" },
    include: {
      _count: { select: { products: true } },
    },
  });

  // Hitung produk yang perlu review (auto-assigned) dan yang tanpa brand
  const [needsReviewCount, noBrandCount] = await Promise.all([
    prisma.product.count({ where: { brandAutoAssigned: true } }),
    prisma.product.count({ where: { brandId: null } }),
  ]);

  async function createBrand(formData: FormData) {
    "use server";
    const name = String(formData.get("name") || "").trim();
    if (!name) return;
    const slug = slugify(name);
    const existing = await prisma.brand.findUnique({ where: { slug } });
    if (existing) {
      redirect("/admin/brands?error=exists");
    }
    await prisma.brand.create({ data: { name, slug } });
    revalidatePath("/admin/brands");
  }

  async function deleteBrand(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const affectedProducts = await prisma.product.findMany({
      where: { brandId: id },
      select: { id: true },
    });

    await prisma.$transaction(async (tx) => {
      await tx.product.updateMany({
        where: { brandId: id },
        data: { brandId: null, brandAutoAssigned: false },
      });
      await tx.brand.delete({ where: { id } });
    });

    if (affectedProducts.length > 0) {
      const { syncProduct } = await import("@/lib/search");
      await Promise.all(
        affectedProducts.map((product) => syncProduct(product.id).catch(() => {}))
      );
    }

    revalidatePath("/admin/brands");
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-10">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <Link
            href="/admin"
            className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
          >
            ← Kembali ke admin
          </Link>
          <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">
            Brand
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            {brands.length} brand terdaftar
          </p>
        </div>
      </div>

      {/* Quick stats */}
      <div className="mt-6 grid gap-3 sm:grid-cols-2">
        {needsReviewCount > 0 && (
          <Link
            href="/admin/brands/review"
            className="flex items-center justify-between rounded-2xl border border-amber-200 bg-amber-50 p-4 transition hover:border-amber-400"
          >
            <div>
              <p className="text-sm font-bold text-amber-900">
                ⚠️ Perlu review ({needsReviewCount})
              </p>
              <p className="mt-0.5 text-xs text-amber-700">
                Brand di-extract otomatis, butuh konfirmasi.
              </p>
            </div>
            <span className="text-amber-600">→</span>
          </Link>
        )}
        {noBrandCount > 0 && (
          <Link
            href="/admin/products?brand=none"
            className="flex items-center justify-between rounded-2xl border border-zinc-200 bg-white p-4 transition hover:border-zinc-400"
          >
            <div>
              <p className="text-sm font-bold text-zinc-900">
                ❓ Tanpa brand ({noBrandCount})
              </p>
              <p className="mt-0.5 text-xs text-zinc-600">
                Assign brand manual lewat halaman edit produk.
              </p>
            </div>
            <span className="text-zinc-500">→</span>
          </Link>
        )}
      </div>

      {/* Form tambah brand */}
      <form
        action={createBrand}
        className="mt-6 flex flex-wrap gap-2 rounded-2xl border border-zinc-200 bg-zinc-50 p-3"
      >
        <input
          type="text"
          name="name"
          placeholder="Nama brand baru — contoh: Royal Canin"
          required
          className="min-w-0 flex-1 rounded-full border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-zinc-600"
        />
        <button
          type="submit"
          className="rounded-full bg-zinc-950 px-5 py-2.5 text-sm font-bold text-white hover:bg-zinc-800"
        >
          + Tambah brand
        </button>
      </form>
      {error === "exists" && (
        <p className="mt-2 text-sm font-semibold text-red-600">
          Brand dengan nama tersebut sudah ada.
        </p>
      )}

      {/* List */}
      <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        {brands.length === 0 ? (
          <div className="p-12 text-center text-sm text-zinc-500">
            Belum ada brand.
          </div>
        ) : (
          <div className="divide-y divide-zinc-100">
            {brands.map((b) => (
              <div
                key={b.id}
                className="flex items-center justify-between gap-4 p-4 hover:bg-zinc-50"
              >
                <div className="min-w-0 flex-1">
                  <p className="font-bold text-zinc-900">{b.name}</p>
                  <p className="text-xs text-zinc-400">
                    /{b.slug} · {b._count.products} produk
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <Link
                    href={`/admin/products?brand=${b.slug}`}
                    className="rounded-full border border-zinc-200 px-3 py-1.5 text-xs font-bold text-zinc-700 hover:border-zinc-400"
                  >
                    Lihat produk
                  </Link>
                  <form action={deleteBrand}>
                    <input type="hidden" name="id" value={b.id} />
                    <ConfirmSubmitButton
                      className="rounded-full border border-red-100 px-3 py-1.5 text-xs font-bold text-red-500 hover:bg-red-50"
                      message={`Hapus brand "${b.name}"? ${b._count.products} produk akan kehilangan label brand-nya (tapi produk tidak terhapus).`}
                    >
                      🗑️
                    </ConfirmSubmitButton>
                  </form>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
