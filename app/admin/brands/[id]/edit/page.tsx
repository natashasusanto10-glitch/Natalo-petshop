import { revalidatePath } from "next/cache";
import { notFound, redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { MultiImageUpload } from "@/components/MultiImageUpload";
import { AdminPage, Button, SubmitButton } from "@/components/admin/ui";

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

export default async function EditBrandPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();

  const { id } = await params;
  const brand = await prisma.brand.findUnique({ where: { id } }).catch(() => null);
  if (!brand) return notFound();

  async function updateBrand(formData: FormData) {
    "use server";
    await requireAdmin();

    const name = String(formData.get("name") || "").trim();
    const rawSlug = String(formData.get("slug") || "").trim();
    const slug = rawSlug || slugify(name);
    if (!name || !slug) return;

    await prisma.brand.update({
      where: { id },
      data: {
        name,
        slug,
        logoUrl: String(formData.get("logoUrl") || "").trim() || null,
        position: parsePosition(formData.get("position")),
        isActive: formData.get("isActive") === "on",
      },
    });
    revalidateBrandSurfaces();
    redirect("/admin/brands");
  }

  return (
    <AdminPage maxWidth="md">
      <Button href="/admin/brands" variant="secondary" size="sm">
        Kembali ke Brand
      </Button>

      <h1 className="mt-4 text-2xl font-black tracking-tight text-zinc-950">
        Edit Brand
      </h1>

      <form action={updateBrand} className="mt-8 space-y-5">
        <div>
          <label className="block text-sm font-semibold text-zinc-700">
            Nama Brand
          </label>
          <input
            name="name"
            defaultValue={brand.name}
            required
            className="mt-1.5 w-full rounded-2xl border border-zinc-200 px-4 py-3 text-sm outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
          />
        </div>
        <div>
          <label className="block text-sm font-semibold text-zinc-700">
            Slug
          </label>
          <input
            name="slug"
            defaultValue={brand.slug}
            className="mt-1.5 w-full rounded-2xl border border-zinc-200 px-4 py-3 text-sm text-zinc-500 outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
            placeholder="auto-generated dari nama"
          />
        </div>
        <div>
          <label className="block text-sm font-semibold text-zinc-700">
            Urutan
          </label>
          <input
            type="number"
            min="0"
            name="position"
            defaultValue={brand.position}
            className="mt-1.5 w-full rounded-2xl border border-zinc-200 px-4 py-3 text-sm outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
          />
        </div>
        <MultiImageUpload
          name="logoUrl"
          label="Logo brand"
          max={1}
          defaultValue={brand.logoUrl ? [brand.logoUrl] : []}
        />
        <label className="inline-flex items-center gap-2 text-sm font-bold text-zinc-700">
          <input
            type="checkbox"
            name="isActive"
            defaultChecked={brand.isActive}
            className="h-4 w-4 rounded border-zinc-300"
          />
          Aktif di user app
        </label>
        <SubmitButton variant="primary" fullWidth>
          Simpan Perubahan
        </SubmitButton>
      </form>
    </AdminPage>
  );
}
