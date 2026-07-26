import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { Prisma } from "@prisma/client";
import { normalizeProductFormPayload } from "@/lib/product/admin-product-form";
import { putVariantsPayloadSchema, formatVariantIssues } from "@/lib/validators/variant-schema";
import { describeVariantSkuConflict } from "@/lib/product/sku-conflict";
import { validateCareFields } from "@/lib/product-dosage";

/**
 * GET /api/admin/products/[id]
 *
 * Detail full satu produk untuk admin view.
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const product = await prisma.product.findUnique({
    where: { id },
    include: {
      category: { select: { id: true, name: true, slug: true } },
      brand: { select: { id: true, name: true, slug: true } },
    },
  });
  if (!product) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }
  return NextResponse.json(product);
}

/**
 * PATCH /api/admin/products/[id]
 *
 * Update partial: nama, harga, stok, isActive, deskripsi, gambar, dll.
 * Dipakai oleh flutter_admin product edit screen.
 *
 * Body: subset dari Product fields. Hanya field yang di-include yang
 * akan di-update (diff).
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const body = (await request.json().catch(() => null)) as Record<
    string,
    unknown
  > | null;

  if (!body) {
    return NextResponse.json({ error: "Body invalid" }, { status: 400 });
  }

  const data: Prisma.ProductUpdateInput = {};

  // Whitelist field yang admin boleh update. Tidak include id, slug
  // (slug tidak boleh diubah karena bagian URL canonical), createdAt.
  if (typeof body.name === "string" && body.name.trim().length > 0) {
    data.name = body.name.trim();
  }
  if (typeof body.description === "string") {
    data.description = body.description.trim();
  }
  if (typeof body.price === "number" && body.price >= 0) {
    data.price = Math.round(body.price);
  }
  if (typeof body.memberPrice === "number") {
    data.memberPrice = body.memberPrice >= 0 ? Math.round(body.memberPrice) : null;
  }
  if (typeof body.discountPrice === "number") {
    data.discountPrice =
      body.discountPrice >= 0 ? Math.round(body.discountPrice) : null;
  }
  if (typeof body.stock === "number" && body.stock >= 0) {
    data.stock = Math.round(body.stock);
  }
  if (typeof body.weightGram === "number" && body.weightGram > 0) {
    data.weightGram = Math.round(body.weightGram);
  }
  if (typeof body.imageUrl === "string") {
    data.imageUrl = body.imageUrl.trim() || null;
  }
  const existingProduct = await prisma.product.findUnique({ where: { id }, select: { price: true, stock: true, weightGram: true } });
  if (!existingProduct) return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  if (Array.isArray(body.imageUrls) || Array.isArray(body.gallery)) {
    const imageUrls = Array.isArray(body.imageUrls)
      ? body.imageUrls.filter((value): value is string => typeof value === "string")
      : [typeof body.imageUrl === "string" ? body.imageUrl : "", ...(body.gallery as unknown[]).filter((value): value is string => typeof value === "string")];
    try {
      const normalized = normalizeProductFormPayload({
        name: typeof body.name === "string" ? body.name : "existing",
        imageUrls,
      });
      data.imageUrl = normalized.imageUrl;
      data.gallery = normalized.gallery;
    } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : "Foto produk tidak bisa diproses." }, { status: 400 });
    }
  }
  if (typeof body.categoryId === "string") data.category = body.categoryId.trim() ? { connect: { id: body.categoryId.trim() } } : { disconnect: true };
  if (body.categoryId === null) data.category = { disconnect: true };
  if (typeof body.brandId === "string") data.brand = body.brandId.trim() ? { connect: { id: body.brandId.trim() } } : { disconnect: true };
  if (body.brandId === null) data.brand = { disconnect: true };
  if (typeof body.sku === "string") data.sku = body.sku.trim() || null;
  if (body.careCategory !== undefined || body.targetSpecies !== undefined || body.dosageRules !== undefined) {
    const careFields = validateCareFields(body);
    if (!careFields.ok) return NextResponse.json({ error: careFields.error }, { status: 400 });
    data.careCategory = careFields.careCategory;
    data.targetSpecies = careFields.targetSpecies;
    data.dosageRules = careFields.dosageRules === null ? Prisma.JsonNull : (careFields.dosageRules as unknown as Prisma.InputJsonValue);
  }
  if (body.video && typeof body.video === "object") {
    const video = body.video as Record<string, unknown>;
    if (typeof video.guid === "string" || video.guid === null) data.videoGuid = video.guid as string | null;
    if (typeof video.status === "string" || video.status === null) data.videoStatus = video.status as string | null;
    if (typeof video.thumbnailUrl === "string" || video.thumbnailUrl === null) data.videoThumbnailUrl = video.thumbnailUrl as string | null;
    if (typeof video.durationSec === "number" || video.durationSec === null) data.videoDurationSec = video.durationSec as number | null;
  }
  let variantPayload: { hasVariants: boolean; attributes: any[]; variants: any[] } | undefined;
  if (body.hasVariants !== undefined || body.attributes !== undefined || body.variants !== undefined) {
    const parsedVariants = putVariantsPayloadSchema.safeParse({
      hasVariants: body.hasVariants === undefined ? true : body.hasVariants,
      attributes: body.attributes ?? [],
      variants: body.variants ?? [],
    });
    if (!parsedVariants.success) return NextResponse.json({ error: formatVariantIssues(parsedVariants.error.issues), issues: parsedVariants.error.issues, fields: parsedVariants.error.flatten().fieldErrors }, { status: 422 });
    variantPayload = parsedVariants.data;
    data.hasVariants = variantPayload.hasVariants;
    const effectivePrice = typeof body.price === "number" ? body.price : existingProduct.price;
    const effectiveStock = typeof body.stock === "number" ? body.stock : existingProduct.stock;
    const effectiveWeight = typeof body.weightGram === "number" ? body.weightGram : existingProduct.weightGram;
    if (!variantPayload.hasVariants && (effectivePrice <= 0 || effectiveStock < 0 || effectiveWeight <= 0)) {
      return NextResponse.json({ error: "Produk tanpa varian wajib memiliki harga, stok, dan berat yang valid" }, { status: 400 });
    }
    if (!variantPayload.hasVariants) { data.price = Math.round(effectivePrice); data.stock = Math.round(effectiveStock); data.weightGram = Math.round(effectiveWeight); }
  }
  if (Object.keys(data).length > 0) data.lastEditedAt = new Date();
  if (typeof body.isActive === "boolean") {
    data.isActive = body.isActive;
  }

  if (Object.keys(data).length === 0) {
    return NextResponse.json(
      { error: "Tidak ada field yang valid untuk update" },
      { status: 400 },
    );
  }

  let updated;
  try {
  updated = await prisma.$transaction(async (tx) => {
    const result = await tx.product.update({
      where: { id },
      data,
      select: {
        id: true,
        name: true,
        slug: true,
        price: true,
        stock: true,
        isActive: true,
        imageUrl: true,
      },
    });
    if (variantPayload) {
      // sku: null WAJIB — sku @unique di level DB, jadi varian lama yang
      // soft-delete tanpa membebaskan SKU mengunci kodenya selamanya
      // (varian baru di bawah tak bisa pakai kode yang sama → P2002).
      // Konsisten dengan pola di variants/route.ts (soft-delete + sku null).
      await tx.productVariant.updateMany({ where: { productId: id, deletedAt: null }, data: { deletedAt: new Date(), isActive: false, sku: null } });
      await tx.variantAttribute.deleteMany({ where: { productId: id } });
      const optionMap = new Map<string, string>();
      for (const attr of variantPayload.attributes) {
        const created = await tx.variantAttribute.create({ data: { productId: id, name: attr.name, position: attr.position, options: { create: attr.options.map((o: any) => ({ value: o.value, position: o.position })) } }, include: { options: true } });
        created.options.forEach((o) => optionMap.set(`${attr.position}:${o.value}`, o.id));
      }
      for (const v of variantPayload.variants) {
        const optionIds = v.optionRefs.map((r: string) => optionMap.get(r)).filter(Boolean) as string[];
        if (optionIds.length !== v.optionRefs.length) continue;
        // Pre-check SKU DENGAN pesan menyebut pemegangnya — tanpa ini,
        // duplikat meledak sebagai P2002 mentah (jalur EDIT tak punya cek
        // sama sekali sebelumnya) dan admin cuma lihat error generik.
        if (v.sku) {
          const conflict = await describeVariantSkuConflict(tx, v.sku, id);
          if (conflict) throw new Error(conflict);
        }
        await tx.productVariant.create({ data: { productId: id, sku: v.sku || null, price: v.price, stock: v.stock, weightGram: v.weightGram, imageUrl: v.imageUrl || null, isActive: v.isActive, options: { create: optionIds.map((optionId) => ({ optionId })) } } });
      }
      const active = await tx.productVariant.findMany({ where: { productId: id, deletedAt: null, isActive: true }, select: { price: true, stock: true, weightGram: true } });
      if (active.length) {
        const cheapest = active.reduce((a, b) => (b.price < a.price ? b : a));
        await tx.product.update({ where: { id }, data: { price: cheapest.price, stock: active.reduce((sum, v) => sum + v.stock, 0), weightGram: cheapest.weightGram, discountPrice: null } });
      }
    }
    return tx.product.findUnique({ where: { id }, select: { id: true, name: true, slug: true, price: true, stock: true, weightGram: true, isActive: true, imageUrl: true } });
  }).catch((err) => { if (err.code === "P2025") return null; throw err; });
  } catch (error) {
    // Tanpa ini, throw di dalam transaction (bentrok SKU, constraint Prisma)
    // jadi 500 non-JSON → klien dapat {} → pesan generik. Sama dengan pola
    // di POST /api/admin/products.
    console.error(`[PATCH /api/admin/products/${id}] gagal update produk`, error);
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      const target = Array.isArray(error.meta?.target) ? error.meta.target.join(", ") : String(error.meta?.target ?? "");
      return NextResponse.json(
        { error: `Nilai duplikat pada ${target || "field unik"} — sudah dipakai produk/varian lain.` },
        { status: 409 },
      );
    }
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal menyimpan perubahan produk." },
      { status: 400 },
    );
  }

  if (!updated) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }

  return NextResponse.json(updated);
}

/**
 * DELETE /api/admin/products/[id]
 *
 * Soft delete: set isActive = false. Tidak benar-benar hapus dari DB
 * karena bisa ter-reference oleh Order/Cart historis.
 */
export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const updated = await prisma.product
    .update({
      where: { id },
      data: { isActive: false },
      select: { id: true, isActive: true },
    })
    .catch((err) => {
      if (err.code === "P2025") return null;
      throw err;
    });
  if (!updated) {
    return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  }
  return NextResponse.json({ ok: true, deactivated: true });
}
