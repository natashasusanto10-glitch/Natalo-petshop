import Link from "next/link";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";
import { BrandLogoOrderClient } from "@/components/admin/BrandLogoOrderClient";
import { BrandLogoUploadButton } from "@/components/admin/BrandLogoUploadButton";
import { BrandCreateDialog } from "@/components/admin/BrandCreateDialog";
import { PageHeader, EmptyState, Badge, AdminPage, Button } from "@/components/admin/ui";

function slugify(name: string) {
  return name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
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
        // Brand baru tidak menyela urutan utama. Admin dapat menempatkannya
        // lewat drag setelah logo dilengkapi.
        position: 1000,
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
    const orderedIds = parseOrderedIds(formData.get("orderedIds")).slice(0, 18);
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

  async function promoteBrand(brandId: string) {
    "use server";
    const candidate = await prisma.brand.findFirst({
      where: { id: brandId, isActive: true, logoUrl: { not: null } },
      select: { id: true },
    });
    if (!candidate) throw new Error("Brand tidak memenuhi syarat.");

    const currentPrimary = await prisma.brand.findMany({
      where: { isActive: true, logoUrl: { not: null } },
      orderBy: [{ position: "asc" }, { createdAt: "desc" }, { name: "asc" }],
      take: 18,
      select: { id: true },
    });
    if (currentPrimary.some((brand) => brand.id === brandId)) return;

    const lastPrimary = currentPrimary.length >= 18 ? currentPrimary.at(-1) : undefined;
    const targetPosition = Math.min(currentPrimary.length, 17);
    await prisma.$transaction([
      ...(lastPrimary
        ? [prisma.brand.update({ where: { id: lastPrimary.id }, data: { position: 1000 } })]
        : []),
      prisma.brand.update({ where: { id: brandId }, data: { position: targetPosition } }),
    ]);
    revalidateBrandSurfaces();
  }

  const logoOrderBrands = brands
    .filter((brand) => brand.isActive && brand.logoUrl)
    .slice(0, 18)
    .map((brand) => ({
      id: brand.id,
      name: brand.name,
      logoUrl: brand.logoUrl,
    }));
  const primaryIds = new Set(logoOrderBrands.map((brand) => brand.id));
  const otherBrands = brands
    .filter((brand) => !primaryIds.has(brand.id))
    .map((brand) => ({
      id: brand.id,
      name: brand.name,
      logoUrl: brand.logoUrl,
      isActive: brand.isActive,
    }));
  const activeCount = brands.filter((brand) => brand.isActive).length;
  const withoutLogoCount = brands.filter((brand) => !brand.logoUrl).length;

  const allBrandsPanel = (
    <div>
      <div className="flex flex-col gap-2 border-b border-zinc-100 px-4 py-5 sm:px-6">
        <h2 className="text-base font-black text-zinc-950">Semua Brand</h2>
        <p className="text-xs font-semibold text-zinc-500">
          Kelola logo, status, produk, dan informasi setiap brand.
        </p>
      </div>
      {brands.length === 0 ? (
        <EmptyState
          icon="🏭"
          title="Belum ada brand"
          description="Tambahkan brand pertama untuk mulai mengelola katalog."
          size="full"
        />
      ) : (
        <div className="divide-y divide-zinc-100">
          {brands.map((brand) => (
            <div
              key={brand.id}
              className="flex flex-col gap-3 px-4 py-4 transition hover:bg-zinc-50 sm:flex-row sm:items-center sm:justify-between sm:gap-4 sm:px-6"
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
                    <Badge variant={brand.isActive ? "success" : "neutral"}>
                      {brand.isActive ? "Aktif" : "Nonaktif"}
                    </Badge>
                    {primaryIds.has(brand.id) && (
                      <span className="rounded-full bg-blue-50 px-2 py-0.5 text-[10px] font-black text-blue-700">
                        Utama #{brand.position + 1}
                      </span>
                    )}
                    {!brand.logoUrl && (
                      <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-black text-amber-700">
                        Tanpa logo
                      </span>
                    )}
                  </div>
                  <p className="mt-0.5 text-xs text-zinc-500">
                    /{brand.slug} · {brand._count.products} produk
                  </p>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-2 sm:flex sm:items-center">
                <Button href={`/admin/brands/${brand.id}/edit`} variant="secondary" size="md">
                  Edit
                </Button>
                <Button href={`/admin/products?brand=${brand.slug}`} variant="secondary" size="md">
                  Produk
                </Button>
                <form action={deleteBrand}>
                  <input type="hidden" name="id" value={brand.id} />
                  <ConfirmSubmitButton
                    className="inline-flex min-h-11 w-full items-center justify-center rounded-full border border-zinc-200 bg-white px-4 text-sm font-bold text-zinc-500 transition hover:border-red-200 hover:bg-red-50 hover:text-red-600"
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
  );

  return (
    <AdminPage maxWidth="xl">
      <PageHeader
        title="Brand"
        subtitle={`${brands.length} brand terdaftar.`}
        actions={<BrandCreateDialog createAction={createBrand} />}
      />

      <div className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <SummaryCard label="Total Brand" value={brands.length} tone="blue" icon="◇" />
        <SummaryCard label="Aktif" value={activeCount} tone="green" icon="✓" />
        <SummaryCard label="Tanpa Logo" value={withoutLogoCount} tone="amber" icon="▧" />
        <SummaryCard label="Perlu Review" value={needsReviewCount} tone="violet" icon="↻" />
      </div>

      <div className="mt-3 grid gap-3 sm:grid-cols-2">
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
      {error === "exists" && (
        <p className="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
          Brand dengan nama tersebut sudah ada.
        </p>
      )}

      <div className="mt-6">
        <BrandLogoOrderClient
          brands={logoOrderBrands}
          otherBrands={otherBrands}
          allBrandsPanel={allBrandsPanel}
          saveAction={saveBrandOrder}
          promoteAction={promoteBrand}
        />
      </div>
    </AdminPage>
  );
}

function SummaryCard({
  label,
  value,
  tone,
  icon,
}: {
  label: string;
  value: number;
  tone: "blue" | "green" | "amber" | "violet";
  icon: string;
}) {
  const styles = {
    blue: "bg-blue-50 text-blue-700",
    green: "bg-emerald-50 text-emerald-700",
    amber: "bg-amber-50 text-amber-700",
    violet: "bg-violet-50 text-violet-700",
  }[tone];
  return (
    <div className="flex items-center gap-4 rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <span className={`grid h-12 w-12 shrink-0 place-items-center rounded-xl text-xl font-black ${styles}`} aria-hidden="true">
        {icon}
      </span>
      <div>
        <p className="text-xs font-bold text-zinc-500">{label}</p>
        <p className="mt-0.5 text-2xl font-black text-zinc-950">{value}</p>
      </div>
    </div>
  );
}
