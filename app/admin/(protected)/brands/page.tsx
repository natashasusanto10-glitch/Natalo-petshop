import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import BrandManager, {
  type ManagedBrand,
} from "@/components/admin/BrandManager";

async function requireAdmin() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") redirect("/admin/login");
}
function slugify(name: string) {
  return name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}
function revalidateBrands() {
  for (const path of [
    "/admin/brands",
    "/",
    "/brands",
    "/products",
    "/api/brands",
  ])
    revalidatePath(path);
}
export default async function AdminBrandsPage({
  searchParams,
}: {
  searchParams: Promise<{ edit?: string }>;
}) {
  await requireAdmin();
  const { edit } = await searchParams;
  const [brands, needsReviewCount, noBrandCount] = await Promise.all([
    prisma.brand.findMany({
      orderBy: [{ position: "asc" }, { name: "asc" }],
      include: { _count: { select: { products: true } } },
    }),
    prisma.product.count({ where: { brandAutoAssigned: true } }),
    prisma.product.count({ where: { brandId: null } }),
  ]);
  async function saveBrandAction(data: FormData): Promise<ManagedBrand> {
    "use server";
    await requireAdmin();
    const id = String(data.get("id") || "");
    const name = String(data.get("name") || "").trim();
    const logoUrl = String(data.get("logoUrl") || "").trim() || null;
    const active = data.get("isActive") === "on";
    if (!name || name.length > 80)
      throw new Error("Nama brand wajib diisi, maksimal 80 karakter.");
    if (logoUrl) {
      try {
        const url = new URL(logoUrl);
        if (url.protocol !== "https:") throw new Error();
      } catch {
        throw new Error("URL logo tidak valid.");
      }
    }
    const existing = id
      ? await prisma.brand.findUnique({ where: { id } })
      : null;
    if (id && !existing) throw new Error("Brand tidak ditemukan.");
    // Preserve existing slugs: links and product filters already use them.
    const slug = existing?.slug || slugify(name);
    if (!slug) throw new Error("Nama brand harus memuat huruf atau angka.");
    const duplicate = await prisma.brand.findFirst({
      where: {
        id: { not: id || undefined },
        OR: [{ slug }, { name: { equals: name, mode: "insensitive" } }],
      },
    });
    if (duplicate) throw new Error("Nama brand sudah digunakan.");
    try {
      const brand = await prisma.brand.upsert({
        where: { id: id || "__new_brand__" },
        create: { name, slug, logoUrl, isActive: active, position: 1000 },
        update: {
          name,
          logoUrl,
          isActive: active,
          ...(!active || !logoUrl ? { position: 1000 } : {}),
        },
        include: { _count: { select: { products: true } } },
      });
      revalidateBrands();
      return {
        id: brand.id,
        name: brand.name,
        slug: brand.slug,
        logoUrl: brand.logoUrl,
        hasLogo: Boolean(brand.logoUrl),
        active: brand.isActive,
        position: brand.position,
        products: brand._count.products,
      };
    } catch {
      throw new Error("Brand gagal disimpan. Periksa nama dan coba kembali.");
    }
  }
  async function saveOrderAction(data: FormData) {
    "use server";
    await requireAdmin();
    let ids: unknown;
    try {
      ids = JSON.parse(String(data.get("orderedIds") || ""));
    } catch {
      throw new Error("Urutan tidak valid.");
    }
    if (
      !Array.isArray(ids) ||
      ids.length > 8 ||
      ids.some((id) => typeof id !== "string" || !id) ||
      new Set(ids).size !== ids.length
    )
      throw new Error("Pilih maksimal delapan brand yang berbeda.");
    const orderedIds = ids as string[];
    await prisma.$transaction(async (tx) => {
      const eligible = await tx.brand.count({
        where: {
          id: { in: orderedIds },
          isActive: true,
          logoUrl: { not: null },
        },
      });
      if (eligible !== orderedIds.length)
        throw new Error("Brand harus aktif dan memiliki logo.");
      await tx.brand.updateMany({
        where: { id: { notIn: orderedIds } },
        data: { position: 1000 },
      });
      for (const [position, id] of orderedIds.entries())
        await tx.brand.update({ where: { id }, data: { position } });
    });
    revalidateBrands();
  }
  async function deleteBrandAction(id: string) {
    "use server";
    await requireAdmin();
    const products = await prisma.$transaction(async (tx) => {
      const affected = await tx.product.findMany({
        where: { brandId: id },
        select: { id: true },
      });
      await tx.product.updateMany({
        where: { brandId: id },
        data: { brandId: null, brandAutoAssigned: false },
      });
      await tx.brand.delete({ where: { id } });
      return affected;
    });
    const { syncProduct } = await import("@/lib/search");
    const results = await Promise.allSettled(
      products.map((p) => syncProduct(p.id))
    );
    if (results.some((r) => r.status === "rejected"))
      console.error(
        "Some product search entries could not be refreshed after deleting a brand."
      );
    revalidateBrands();
  }
  return (
    <BrandManager
      initialEditId={edit}
      initialBrands={brands.map((b) => ({
        id: b.id,
        name: b.name,
        slug: b.slug,
        position: b.position,
        products: b._count.products,
        active: b.isActive,
        logoUrl: b.logoUrl,
        hasLogo: Boolean(b.logoUrl),
      }))}
      needsReviewCount={needsReviewCount}
      noBrandCount={noBrandCount}
      saveBrandAction={saveBrandAction}
      saveOrderAction={saveOrderAction}
      deleteBrandAction={deleteBrandAction}
    />
  );
}
