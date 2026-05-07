import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { syncProduct } from "@/lib/search";

type Update = { id: string; price?: number; stock?: number };

const MAX_UPDATES = 100;

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id: productId } = await params;
  const body = await request.json();
  if (!Array.isArray(body?.updates)) {
    return NextResponse.json({ error: "Payload tidak valid" }, { status: 400 });
  }

  const updates: Update[] = body.updates;
  if (updates.length === 0 || updates.length > MAX_UPDATES) {
    return NextResponse.json(
      { error: `Update varian harus 1-${MAX_UPDATES} item` },
      { status: 400 }
    );
  }

  const seen = new Set<string>();
  for (const update of updates) {
    if (typeof update.id !== "string" || !update.id) {
      return NextResponse.json({ error: "ID varian tidak valid" }, { status: 400 });
    }
    if (seen.has(update.id)) {
      return NextResponse.json({ error: "ID varian tidak boleh duplikat" }, { status: 400 });
    }
    seen.add(update.id);

    if (update.price !== undefined && (!Number.isInteger(update.price) || update.price < 0)) {
      return NextResponse.json({ error: "Harga varian harus angka >= 0" }, { status: 400 });
    }
    if (update.stock !== undefined && (!Number.isInteger(update.stock) || update.stock < 0)) {
      return NextResponse.json({ error: "Stok varian harus angka >= 0" }, { status: 400 });
    }
    if (update.price === undefined && update.stock === undefined) {
      return NextResponse.json(
        { error: "Setiap update harus punya price atau stock" },
        { status: 400 }
      );
    }
  }

  const product = await prisma.product.findUnique({
    where: { id: productId },
    select: { id: true, hasVariants: true },
  });
  if (!product) return NextResponse.json({ error: "Produk tidak ditemukan" }, { status: 404 });
  if (!product.hasVariants) {
    return NextResponse.json({ error: "Produk ini tidak memakai varian" }, { status: 400 });
  }

  const result = await prisma.$transaction(async (tx) => {
    const updateResults = await Promise.all(
      updates.map((update) =>
        tx.productVariant.updateMany({
          where: { id: update.id, productId, deletedAt: null },
          data: {
            ...(update.price !== undefined ? { price: update.price } : {}),
            ...(update.stock !== undefined ? { stock: update.stock } : {}),
          },
        })
      )
    );
    const updated = updateResults.reduce((sum, item) => sum + item.count, 0);
    if (updated !== updates.length) {
      throw new Error("Sebagian varian tidak ditemukan atau bukan milik produk ini.");
    }

    const activeVariants = await tx.productVariant.findMany({
      where: { productId, deletedAt: null, isActive: true },
      select: { price: true, stock: true, weightGram: true },
    });

    if (activeVariants.length === 0) {
      await tx.product.update({
        where: { id: productId },
        data: { stock: 0 },
      });
      return { updated, aggregate: { price: 0, stock: 0 } };
    }

    const prices = activeVariants.map((variant) => variant.price);
    const minPrice = Math.min(...prices);
    const cheapest = activeVariants.find((variant) => variant.price === minPrice)!;
    const totalStock = activeVariants.reduce((sum, variant) => sum + variant.stock, 0);

    await tx.product.update({
      where: { id: productId },
      data: {
        price: minPrice,
        stock: totalStock,
        weightGram: cheapest.weightGram,
        discountPrice: null,
      },
    });

    return { updated, aggregate: { price: minPrice, stock: totalStock } };
  });

  syncProduct(productId).catch((error) => {
    console.error("[variants bulk PATCH syncProduct]", error);
  });

  return NextResponse.json(result);
}
