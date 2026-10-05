import { parsePageParam } from "@/lib/admin/pagination";
import { productSearchWhere } from "@/lib/search";
import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { AdminPage, Button, Pagination } from "@/components/admin/ui";

const PAGE_SIZE = 30;

export default async function BrandReviewPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; brand?: string; q?: string }>;
}) {
  const { page: pageStr, brand: brandFilter, q } = await searchParams;
  const page = parsePageParam(pageStr);

  const search = q?.trim().slice(0, 100) ?? "";
  const where = {
    ...productSearchWhere(search),
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
    await requireAdminSession();
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
    await requireAdminSession();
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
    await requireAdminSession();
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
        affectedProducts.map((product) =>
          syncProduct(product.id).catch(() => {})
        )
      );
    }
    revalidatePath("/admin/brands/review");
  }

  return (
    <AdminPage maxWidth="xl" className="admin-operational-page">
      <Button href="/admin/brands" variant="secondary" size="sm">
        ← Kembali ke brand
      </Button>
      <h1 className="mt-2 text-2xl font-semibold tracking-tight text-zinc-950 md:text-3xl">
        Review Auto-Assign Brand
      </h1>
      <p className="mt-1 text-sm text-zinc-500">
        {total} produk dengan brand di-extract otomatis. Konfirmasi atau ubah
        kalau salah.
      </p>

      <form method="get" className="mt-6 grid gap-3 rounded-2xl border border-slate-200 bg-white p-4 sm:grid-cols-[1fr_1fr_auto]">
        <label className="text-sm font-medium">Brand<select name="brand" defaultValue={brandFilter ?? ""} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2"><option value="">Semua brand</option>{brands.filter(brand => (brandCountMap.get(brand.id) ?? 0) > 0).map(brand => <option key={brand.id} value={brand.slug}>{brand.name} ({brandCountMap.get(brand.id)})</option>)}</select></label>
        <label className="text-sm font-medium">Cari produk atau SKU<input type="search" name="q" defaultValue={search} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2" /></label>
        <Button type="submit" className="self-end">Cari</Button>
      </form>
      {/* Bulk confirm — kalau filter brand aktif */}
      {brandFilter && brands.some(brand => brand.slug === brandFilter) && (
        <div className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 p-4">
          <p className="text-sm font-semibold text-amber-900">
            Yakin semua produk di brand &ldquo;
            {brands.find((b) => b.slug === brandFilter)?.name}&rdquo; sudah
            benar?
          </p>
          <p className="mt-1 text-xs text-amber-700">
            Konfirmasi menandai semua produk di brand ini sebagai sudah diperiksa, termasuk di luar hasil pencarian.
          </p>
          <form action={bulkConfirmBrand} className="mt-3">
            <input
              type="hidden"
              name="brandId"
              value={brands.find((b) => b.slug === brandFilter)?.id}
            />
            <Button type="submit" variant="primary">
              ✓ Konfirmasi semua
            </Button>
          </form>
        </div>
      )}

      {/* Product list */}
      <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        {products.length === 0 ? (
          <div className="p-12 text-center">
            <span className="text-4xl">🎉</span>
            <p className="mt-3 font-semibold text-zinc-700">
              Tidak ada produk pada filter ini
            </p>
            <p className="mt-1 text-sm text-zinc-500">
              Coba pencarian atau filter brand lainnya.
            </p>
          </div>
        ) : (
          <div className="divide-y divide-zinc-100">
            {products.map((p) => (
              <div
                key={p.id}
                className="grid gap-3 p-4 md:grid-cols-[1fr_220px_140px] md:gap-4"
              >
                <div className="min-w-0">
                  <Link
                    href={`/admin/products/${p.id}/edit`} target="_blank" rel="noopener noreferrer"
                    className="line-clamp-2 font-semibold text-zinc-900 hover:text-natalo-700"
                  >
                    {p.name}
                  </Link>
                  <p className="mt-1 text-xs text-zinc-600">
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
                  <Button type="submit" variant="secondary">
                    Ubah
                  </Button>
                </form>

                {/* Confirm */}
                <form action={confirmBrand}>
                  <input type="hidden" name="productId" value={p.id} />
                  <Button type="submit" variant="primary" fullWidth>
                    ✓ Sudah benar
                  </Button>
                </form>
              </div>
            ))}
          </div>
        )}
      </div>

      <Pagination
        currentPage={page}
        totalPages={totalPages}
        hrefFor={(target) =>
          `/admin/brands/review?page=${target}${
            brandFilter ? `&brand=${encodeURIComponent(brandFilter)}` : ""
          }${search ? `&q=${encodeURIComponent(search)}` : ""}`
        }
        summary={`${total} produk`}
      />
    </AdminPage>
  );
}
