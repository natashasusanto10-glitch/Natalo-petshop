import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  generateProductDescription,
  GenerateDescriptionError,
} from "@/lib/ai/generate-product-description";

/**
 * POST /api/admin/products/[id]/generate-description
 *
 * Generate deskripsi produk Bahasa Indonesia via Claude API, berdasarkan
 * nama (DB atau form belum-disimpan), kategori, brand, dan varian produk.
 *
 * Body opsional: { name?: string } — nama produk dari form (mungkin
 * belum disimpan). Kalau kosong, pakai nama dari DB.
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const body = (await request.json().catch(() => ({}))) as {
    name?: string;
    categoryName?: string | null;
    brandName?: string | null;
    variantOptions?: string[];
  };

  const product = await prisma.product.findUnique({
    where: { id },
    select: {
      name: true,
      category: { select: { name: true } },
      brand: { select: { name: true } },
      variantAttrs: { select: { options: { select: { value: true } } } },
    },
  });

  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }

  const persistedVariantOptions = product.variantAttrs.flatMap((attr) =>
    attr.options.map((opt) => opt.value),
  );

  const overrideName = typeof body.name === "string" ? body.name.trim() : "";
  const name = overrideName || product.name;

  try {
    const description = await generateProductDescription({
      name,
      categoryName: body.categoryName ?? product.category?.name ?? null,
      brandName: body.brandName ?? product.brand?.name ?? null,
      variantOptions: Array.isArray(body.variantOptions) ? body.variantOptions : persistedVariantOptions,
    });
    return NextResponse.json({ description });
  } catch (err) {
    if (err instanceof GenerateDescriptionError) {
      const status =
        err.code === "INVALID_INPUT" || err.code === "MISSING_KEY" ? 400 : 502;
      return NextResponse.json({ error: err.message }, { status });
    }
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
