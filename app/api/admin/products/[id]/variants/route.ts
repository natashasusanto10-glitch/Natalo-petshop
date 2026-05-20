/**
 * PUT /api/admin/products/[id]/variants
 *
 * Simpan/update struktur varian produk secara atomik.
 * Melakukan full-replace: attribute + option + variant dibangun ulang dari payload.
 * Variant yang sudah pernah di-order akan di-soft-delete (bukan hard-delete).
 */

import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { syncProduct } from "@/lib/search";
import { putVariantsPayloadSchema } from "@/lib/validators/variant-schema";

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const csrfReject = assertSameOrigin(request);
    if (csrfReject) return csrfReject;

    const session = await getSession("ADMIN");
    if (!session || session.role !== "ADMIN")
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const { id: productId } = await params;
    const parsed = putVariantsPayloadSchema.safeParse(await request.json());
    if (!parsed.success) {
      return NextResponse.json(
        {
          error: "Payload varian tidak valid",
          fields: parsed.error.flatten().fieldErrors,
        },
        { status: 422 }
      );
    }
    const { hasVariants, attributes, variants } = parsed.data;

    // Validasi produk ada
    const product = await prisma.product.findUnique({ where: { id: productId } });
    if (!product) return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });

    await prisma.$transaction(async (tx) => {
      // ── Update flag hasVariants ─────────────────────────────────
      await tx.product.update({
        where: { id: productId },
        data: { hasVariants },
      });

      if (!hasVariants) {
        // Nonaktifkan semua variant yang ada
        await tx.productVariant.updateMany({
          where: { productId, deletedAt: null },
          data: { deletedAt: new Date(), isActive: false },
        });
        // Tidak perlu sync — Product.price/stock/weightGram pakai nilai sendiri
        return;
      }

      // ── Cari variant lama yang pernah di-order (perlu soft-delete) ──
      const oldVariantsWithOrders = await tx.productVariant.findMany({
        where: { productId, deletedAt: null },
        include: { orderItems: { take: 1, select: { id: true } } },
      });
      const variantsWithOrders = new Set(
        oldVariantsWithOrders.filter((v) => v.orderItems.length > 0).map((v) => v.id)
      );

      // ── Hard-delete variant lama tanpa order (junction table ikut cascade) ──
      const toHardDelete = oldVariantsWithOrders
        .filter((v) => !variantsWithOrders.has(v.id))
        .map((v) => v.id);
      if (toHardDelete.length > 0) {
        await tx.productVariant.deleteMany({ where: { id: { in: toHardDelete } } });
      }

      // ── Soft-delete variant lama yang punya order ──────────────
      if (variantsWithOrders.size > 0) {
        await tx.productVariant.updateMany({
          where: { id: { in: [...variantsWithOrders] } },
          data: { deletedAt: new Date(), isActive: false, sku: null },
        });
      }

      // ── Hard-delete attribute lama (options & junction ikut cascade) ──
      await tx.variantAttribute.deleteMany({ where: { productId } });

      // ── Buat attribute + option baru ────────────────────────────
      // Map: "attrPosition:optionValue" → option DB id
      const optionRefMap = new Map<string, string>();

      for (const attr of attributes) {
        const createdAttr = await tx.variantAttribute.create({
          data: {
            productId,
            name: attr.name,
            position: attr.position,
            options: {
              create: attr.options.map((opt) => ({
                value: opt.value,
                position: opt.position,
              })),
            },
          },
          include: { options: true },
        });

        // Populate map
        for (const opt of createdAttr.options) {
          const key = `${attr.position}:${opt.value}`;
          optionRefMap.set(key, opt.id);
        }
      }

      // ── Buat variant baru ────────────────────────────────────────
      for (const v of variants) {
        const optionIds = v.optionRefs
          .map((ref) => optionRefMap.get(ref))
          .filter((id): id is string => !!id);

        if (optionIds.length !== v.optionRefs.length) {
          // Opsi tidak ditemukan, skip variant ini
          continue;
        }

        // Validasi SKU unik (kalau ada)
        if (v.sku) {
          const existingSku = await tx.productVariant.findFirst({
            where: { sku: v.sku },
          });
          if (existingSku) {
            throw new Error(`SKU "${v.sku}" sudah digunakan oleh varian lain.`);
          }
        }

        await tx.productVariant.create({
          data: {
            productId,
            sku: v.sku || null,
            price: v.price,
            stock: v.stock,
            weightGram: v.weightGram,
            imageUrl: v.imageUrl || null,
            isActive: v.isActive,
            options: {
              create: optionIds.map((optionId) => ({ optionId })),
            },
          },
        });
      }

      // ── Sync field aggregate di Product dari varian aktif ────────
      // price       = harga TERMURAH varian aktif
      // stock       = TOTAL stok semua varian aktif
      // weightGram  = berat varian TERMURAH (representasi default)
      const activeVariants = await tx.productVariant.findMany({
        where: { productId, deletedAt: null, isActive: true },
        select: { price: true, stock: true, weightGram: true },
      });

      if (activeVariants.length > 0) {
        const prices = activeVariants.map((v) => v.price);
        const minPrice = Math.min(...prices);
        const cheapest = activeVariants.find((v) => v.price === minPrice)!;
        const totalStock = activeVariants.reduce((s, v) => s + v.stock, 0);

        await tx.product.update({
          where: { id: productId },
          data: {
            price: minPrice,
            stock: totalStock,
            weightGram: cheapest.weightGram,
            // discountPrice di-clear: gunakan harga varian (no double discount)
            discountPrice: null,
          },
        });
      }
    });

    syncProduct(productId).catch((error) => {
      console.error("[variants PUT syncProduct]", error);
    });

    // Restock trigger — kalau Product.stock berubah dari 0 ke >0
    // (aggregate dari sum variant stocks di transaction), notify
    // subscriber yang mendaftar untuk produk ini (variantId=null).
    // Note: variant-specific subscribers di-handle via CASCADE delete saat
    // variant lama di-hard-delete; subscribe ulang ke variant baru kalau
    // user mau.
    if (product.stock === 0) {
      const refreshed = await prisma.product.findUnique({
        where: { id: productId },
        select: { stock: true },
      });
      if (refreshed && refreshed.stock > 0) {
        const { sendBackInStockPush } = await import("@/lib/push-marketing");
        sendBackInStockPush(productId, null).catch((err) => {
          console.warn("[variants PUT back-in-stock]:", err);
        });
      }
    }

    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[variants PUT]", error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal menyimpan varian" },
      { status: 500 }
    );
  }
}

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN")
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id: productId } = await params;

  const product = await prisma.product.findUnique({
    where: { id: productId },
    include: {
      variantAttrs: {
        orderBy: { position: "asc" },
        include: { options: { orderBy: { position: "asc" } } },
      },
      variants: {
        where: { deletedAt: null },
        include: { options: { select: { optionId: true } } },
        orderBy: { createdAt: "asc" },
      },
    },
  });

  if (!product) return NextResponse.json({ error: "Not found" }, { status: 404 });

  return NextResponse.json({
    hasVariants: product.hasVariants,
    attributes: product.variantAttrs,
    variants: product.variants,
  });
}
