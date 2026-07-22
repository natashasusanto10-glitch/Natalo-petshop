import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { createBrandSchema, slugifyBrandName } from "@/lib/validators/brand-schema";

function revalidateBrandSurfaces() {
  revalidatePath("/admin/brands");
  revalidatePath("/");
  revalidatePath("/brands");
  revalidatePath("/products");
}

/**
 * POST /api/admin/brands
 *
 * Buat brand baru inline dari BrandCombobox (Tambah/Edit Produk) — admin
 * bisa buat brand tanpa keluar dari form produk.
 *
 * Body: {name: string}
 */
export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const parsed = createBrandSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "Nama brand tidak valid" }, { status: 400 });
  }

  const slug = slugifyBrandName(parsed.data.name);
  const existing = await prisma.brand.findUnique({ where: { slug } });
  if (existing) {
    return NextResponse.json({ error: "Brand dengan nama ini sudah ada" }, { status: 409 });
  }

  const brand = await prisma.brand.create({
    data: {
      name: parsed.data.name,
      slug,
      position: 1000,
      isActive: true,
    },
  });

  revalidateBrandSurfaces();

  return NextResponse.json({ id: brand.id, name: brand.name, slug: brand.slug }, { status: 201 });
}
