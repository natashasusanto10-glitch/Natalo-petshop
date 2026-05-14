import Link from "next/link";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";
import { MultiImageUpload } from "@/components/MultiImageUpload";
import { BrandLogoOrderClient } from "@/components/admin/BrandLogoOrderClient";
import { BrandLogoUploadButton } from "@/components/admin/BrandLogoUploadButton";

function slugify(name: string) {
  return name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function parsePosition(value: FormDataEntryValue | null) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.floor(parsed)) : 0;
}

function revalidateBrandSurfaces() {
  revalidatePath("/admin/brands");
  revalidatePath("/");
  revalidatePath("/brands");
  revalidatePath("/products");
}

function parseOrderedIds(value: FormDataEntryValue | null) {
  if (typeof value !== "string") return [];
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed)
      ? parsed.filter((id): id is string => typeof id === "string" && id.length > 0)
      : [];
  } catch {
    return [];
  }
}

export default async function AdminBrandsPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const brands = await prisma.brand.findMany({
    orderBy: [{ position: "asc" }, { createdAt: "desc" }, { name: "asc" }],
    include: {
      _count: { select: { products: true } },
    },
  });

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

    await prisma.brand.create({
      data: {
        name,
        slug,
        logoUrl: String(formData.get("logoUrl") || "").trim() || null,
        position: parsePosition(formData.get("position")),
        isActive: formData.get("isActive") === "on",
      },
    });
    revalidateBrandSurfaces();
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
        affectedProducts.map((product) => syncProduct(product.id).catch(() => {})),
      );
    }

    revalidateBrandSurfaces();
  }

  async function saveBrandOrder(formData: FormData) {
    "use server";
    const orderedIds = parseOrderedIds(formData.get("orderedIds")).slice(0, 12);
    if (orderedIds.length === 0) return;

    await prisma.$transaction([
      ...orderedIds.map((id, index) =>
        prisma.brand.update({
          where: { id },
          data: { position: index },
        }),
      ),
      prisma.brand.updateMany({
        where: {
          id: { notIn: orderedIds },
          isActive: true,
          logoUrl: { not: null },
          position: { lt: 1000 },
        },
        data: { position: 1000 },
      }),
    ]);

    revalidateBrandSurfaces();
  }

  async function updateBrandLogo(brandId: string, logoUrl: string) {
    "use server";
    const cleanLogoUrl = logoUrl.trim();
    if (!brandId || !cleanLogoUrl) return;

    await prisma.brand.update({
      where: { id: brandId },
      data: { logoUrl: cleanLogoUrl },
    });

    revalidateBrandSurfaces();
  }

  const logoOrderBrands = brands
    .filter((brand) => brand.isActive && brand.logoUrl)
    .slice(0, 12)
    .map((brand) => ({
      id: brand.id,
      name: brand.name,
      logoUrl: brand.logoUrl,
    }));

  return (
    <div className="mx-auto max-w-5xl px-4 py-5 md:py-10">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <Link
            href="/admin"
            className="hidden text-sm font-bold text-zinc-500 hover:text-zinc-950 md:inline"
          >
            Kembali ke admin
          </Link>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:mt-2 md:text-3xl">
            Brand
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            {brands.length} brand terdaftar
          </p>
        </div>
      </div>

      <div className="mt-6 grid gap-3 sm:grid-cols-2">
        {needsReviewCount > 0 && (
          <Link
            href="/admin/brands/review"
            className="flex items-center justify-between rounded-2xl border border-amber-200 bg-amber-50 p-4 transition hover:border-amber-400"
          >
            <div>
              <p className="text-sm font-bold text-amber-900">
                Perlu review ({needsReviewCount})
              </p>
              <p className="mt-0.5 text-xs text-amber-700">
                Brand di-extract otomatis, butuh konfirmasi.
              </p>
            </div>
            <span className="text-amber-600">Lihat</span>
          </Link>
        )}
        {noBrandCount > 0 && (
          <Link
            href="/admin/products?brand=none"
            className="flex items-center justify-between rounded-2xl border border-zinc-200 bg-white p-4 transition hover:border-zinc-400"
          >
            <div>
              <p className="text-sm font-bold text-zinc-900">
                Tanpa brand ({noBrandCount})
              </p>
              <p className="mt-0.5 text-xs text-zinc-600">
                Assign brand manual lewat halaman edit produk.
              </p>
            </div>
            <span className="text-zinc-500">Lihat</span>
          </Link>
        )}
      </div>

      <form
        action={createBrand}
        className="mt-6 grid gap-4 rounded-2xl border border-zinc-200 bg-zinc-50 p-4"
      >
        <div className="grid gap-3 md:grid-cols-[1fr_140px]">
          <input
            type="text"
            name="name"
            placeholder="Nama brand baru - contoh: Royal Canin"
            required
            className="min-w-0 rounded-full border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-zinc-600"
          />
          <input
            type="number"
            min="0"
            name="position"
            placeholder="Urutan"
            className="rounded-full border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-zinc-600"
          />
        </div>
        <MultiImageUpload name="logoUrl" label="Logo brand" max={1} />
        <div className="flex flex-wrap items-center justify-between gap-3">
          <label className="inline-flex items-center gap-2 text-sm font-bold text-zinc-700">
            <input
              type="checkbox"
              name="isActive"
              defaultChecked
              className="h-4 w-4 rounded border-zinc-300"
            />
            Aktif di user app
          </label>
          <button
            type="submit"
            className="rounded-full bg-zinc-950 px-5 py-2.5 text-sm font-bold text-white hover:bg-zinc-800"
          >
            + Tambah brand
          </button>
        </div>
      </form>
      {error === "exists" && (
        <p className="mt-2 text-sm font-semibold text-red-600">
          Brand dengan nama tersebut sudah ada.
        </p>
      )}

      <div className="mt-6">
        <BrandLogoOrderClient brands={logoOrderBrands} saveAction={saveBrandOrder} />
      </div>

      <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        {brands.length === 0 ? (
          <div className="p-12 text-center text-sm text-zinc-500">
            Belum ada brand.
          </div>
        ) : (
          <div className="divide-y divide-zinc-100">
            {brands.map((brand) => (
              <div
                key={brand.id}
                className="flex flex-col gap-3 p-4 hover:bg-zinc-50 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
              >
                <div className="flex min-w-0 flex-1 items-center gap-3">
                  <BrandLogoUploadButton
                    brandId={brand.id}
                    brandName={brand.name}
                    logoUrl={brand.logoUrl}
                    updateLogoAction={updateBrandLogo}
                  />
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-bold text-zinc-900">{brand.name}</p>
                      <span
                        className={`rounded-full px-2 py-0.5 text-[10px] font-black ${
                          brand.isActive
                            ? "bg-green-50 text-green-700"
                            : "bg-zinc-100 text-zinc-500"
                        }`}
                      >
                        {brand.isActive ? "Aktif" : "Nonaktif"}
                      </span>
                    </div>
                    <p className="text-xs text-zinc-400">
                      /{brand.slug} - urutan {brand.position} -{" "}
                      {brand._count.products} produk
                    </p>
                  </div>
                </div>
                <div className="grid grid-cols-3 gap-2 sm:flex sm:items-center">
                  <Link
                    href={`/admin/brands/${brand.id}/edit`}
                    className="rounded-full border border-zinc-200 px-3 py-1.5 text-center text-xs font-bold text-zinc-700 hover:border-zinc-400"
                  >
                    Edit
                  </Link>
                  <Link
                    href={`/admin/products?brand=${brand.slug}`}
                    className="rounded-full border border-zinc-200 px-3 py-1.5 text-center text-xs font-bold text-zinc-700 hover:border-zinc-400"
                  >
                    Produk
                  </Link>
                  <form action={deleteBrand}>
                    <input type="hidden" name="id" value={brand.id} />
                    <ConfirmSubmitButton
                      className="w-full rounded-full border border-red-100 px-3 py-1.5 text-xs font-bold text-red-500 hover:bg-red-50"
                      message={`Hapus brand "${brand.name}"? ${brand._count.products} produk akan kehilangan label brand-nya (tapi produk tidak terhapus).`}
                    >
                      Hapus
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
