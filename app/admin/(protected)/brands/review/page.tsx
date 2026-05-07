import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";

const PAGE_SIZE = 30;

export default async function BrandReviewPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; brand?: string }>;
}) {
  const { page: pageStr, brand: brandFilter } = await searchParams;
  const page = Math.max(1, Number(pageStr) || 1);

  const where = {
    brandAutoAssigned: true,
    ...(brandFilter ? { brand: { slug: brandFilter } } : {}),
  };

  const [products, total, brands, brandCounts] = await Promise.all([
    prisma.product.findMany({
      where,
      orderBy: { name: "asc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
      include: { brand: true },
    }),
    prisma.product.count({ where }),
    prisma.brand.findMany({ orderBy: { name: "asc" } }),
    prisma.product.groupBy({
      by: ["brandId"],
      where: { brandAutoAssigned: true },
      _count: true,
    }),
  ]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const brandCountMap = new Map(brandCounts.map((b) => [b.brandId, b._count]));

  // Server Action: konfirmasi assignment (hilangkan flag auto)
  async function confirmBrand(formData: FormData) {
    "use server";
    const productId = String(formData.get("productId"));
    await prisma.product.update({
      where: { id: productId },
      data: { brandAutoAssigned: false },
    });
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(productId).catch(() => {});
    revalidatePath("/admin/brands/review");
  }

  // Server Action: ubah brand
  async function changeBrand(formData: FormData) {
    "use server";
    const productId = String(formData.get("productId"));
    const newBrandId = String(formData.get("brandId"));
    await prisma.product.update({
      where: { id: productId },
      data: {
        brandId: newBrandId === "_none_" ? null : newBrandId,
        brandAutoAssigned: false, // user sudah pilih → bukan lagi auto
      },
    });
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(productId).catch(() => {});
    revalidatePath("/admin/brands/review");
  }

  // Server Action: bulk confirm semua di brand tertentu
  async function bulkConfirmBrand(formData: FormData) {
    "use server";
    const brandId = String(formData.get("brandId"));
    const affectedProducts = await prisma.product.findMany({
      where: { brandId, brandAutoAssigned: true },
      select: { id: true },
    });
    await prisma.product.updateMany({
      where: { brandId, brandAutoAssigned: true },
      data: { brandAutoAssigned: false },
    });
    if (affectedProducts.length > 0) {
      const { syncProduct } = await import("@/lib/search");
      await Promise.all(
        affectedProducts.map((product) => syncProduct(product.id).catch(() => {}))
      );
    }
    revalidatePath("/admin/brands/review");
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <Link
        href="/admin/brands"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke brand
      </Link>
      <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">
        Review Auto-Assign Brand
      </h1>
      <p className="mt-1 text-sm text-zinc-500">
        {total} produk dengan brand di-extract otomatis. Konfirmasi atau ubah
        kalau salah.
      </p>

      {/* Filter by brand chip */}
      <div className="mt-6 flex flex-wrap gap-2">
        <Link
          href="/admin/brands/review"
          className={`rounded-full border px-4 py-1.5 text-sm font-semibold transition ${
            !brandFilter
              ? "border-zinc-950 bg-zinc-950 text-white"
              : "border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
          }`}
        >
          Semua brand
        </Link>
        {brands
          .filter((b) => (brandCountMap.get(b.id) ?? 0) > 0)
          .map((b) => {
            const count = brandCountMap.get(b.id) ?? 0;
            const active = brandFilter === b.slug;
            return (
              <Link
                key={b.id}
                href={`/admin/brands/review?brand=${b.slug}`}
                className={`flex items-center gap-2 rounded-full border px-4 py-1.5 text-sm font-semibold transition ${
                  active
                    ? "border-amber-500 bg-amber-500 text-white"
                    : "border-amber-200 bg-amber-50 text-amber-700 hover:border-amber-400"
                }`}
              >
                {b.name}
                <span
                  className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${
                    active ? "bg-white/20 text-white" : "bg-white text-amber-600"
                  }`}
                >
                  {count}
                </span>
              </Link>
            );
          })}
      </div>

      {/* Bulk confirm — kalau filter brand aktif */}
      {brandFilter && (
        <div className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 p-4">
          <p className="text-sm font-semibold text-amber-900">
            Yakin semua produk di brand &ldquo;{brands.find((b) => b.slug === brandFilter)?.name}&rdquo; sudah benar?
          </p>
          <p className="mt-1 text-xs text-amber-700">
            Konfirmasi sekaligus akan menghilangkan flag &ldquo;perlu review&rdquo; dari semua produk di brand ini.
          </p>
          <form
            action={bulkConfirmBrand}
            className="mt-3"
          >
            <input
              type="hidden"
              name="brandId"
              value={brands.find((b) => b.slug === brandFilter)?.id}
            />
            <button
              type="submit"
              className="rounded-full bg-amber-500 px-5 py-2 text-sm font-bold text-white hover:bg-amber-600"
            >
              ✓ Konfirmasi semua
            </button>
          </form>
        </div>
      )}

      {/* Product list */}
      <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        {products.length === 0 ? (
          <div className="p-12 text-center">
            <span className="text-4xl">🎉</span>
            <p className="mt-3 font-semibold text-zinc-700">
              Tidak ada yang perlu di-review!
            </p>
            <p className="mt-1 text-sm text-zinc-500">
              Semua brand sudah di-konfirmasi.
            </p>
          </div>
        ) : (
          <div className="divide-y divide-zinc-100">
            {products.map((p) => (
              <div
                key={p.id}
                className="grid gap-4 p-4 sm:grid-cols-[1fr_220px_140px]"
              >
                <div className="min-w-0">
                  <Link
                    href={`/admin/products/${p.id}/edit`}
                    className="line-clamp-2 font-semibold text-zinc-900 hover:text-natalo-700"
                  >
                    {p.name}
                  </Link>
                  <p className="mt-1 text-xs text-zinc-400">
                    Saat ini:{" "}
                    <span className="font-bold text-amber-700">
                      {p.brand?.name ?? "—"}
                    </span>
                  </p>
                </div>

                {/* Ganti brand */}
                <form action={changeBrand} className="flex gap-2">
                  <input type="hidden" name="productId" value={p.id} />
                  <select
                    name="brandId"
                    defaultValue={p.brandId ?? "_none_"}
                    className="min-w-0 flex-1 rounded-full border border-zinc-300 bg-white px-3 py-1.5 text-xs font-medium outline-none focus:border-zinc-600"
                  >
                    <option value="_none_">— Tanpa brand —</option>
                    {brands.map((b) => (
                      <option key={b.id} value={b.id}>
                        {b.name}
                      </option>
                    ))}
                  </select>
                  <button
                    type="submit"
                    className="rounded-full border border-zinc-300 px-3 py-1.5 text-xs font-bold hover:bg-zinc-50"
                  >
                    Ubah
                  </button>
                </form>

                {/* Confirm */}
                <form action={confirmBrand}>
                  <input type="hidden" name="productId" value={p.id} />
                  <button
                    type="submit"
                    className="w-full rounded-full bg-green-500 px-3 py-1.5 text-xs font-bold text-white hover:bg-green-600"
                  >
                    ✓ Sudah benar
                  </button>
                </form>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-zinc-500">
            Halaman {page} dari {totalPages} · {total} produk
          </p>
          <div className="flex gap-2">
            {page > 1 && (
              <Link
                href={`/admin/brands/review?page=${page - 1}${brandFilter ? `&brand=${brandFilter}` : ""}`}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-semibold hover:bg-zinc-50"
              >
                ← Sebelumnya
              </Link>
            )}
            {page < totalPages && (
              <Link
                href={`/admin/brands/review?page=${page + 1}${brandFilter ? `&brand=${brandFilter}` : ""}`}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-semibold hover:bg-zinc-50"
              >
                Selanjutnya →
              </Link>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
