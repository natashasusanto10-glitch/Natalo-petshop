import type { Prisma } from "@prisma/client";
import type { z } from "zod";
import type { putVariantsPayloadSchema } from "@/lib/validators/variant-schema";
import { describeVariantSkuConflict } from "./sku-conflict";

type Payload = z.infer<typeof putVariantsPayloadSchema>;
const combinationKey = (refs: string[]) => JSON.stringify([...refs].sort());

/** Called inside the product transaction. Retained variants keep IDs used by
 * orders, promotions, and stock subscribers; only removed combinations retire. */
export async function saveAdminVariants(
  tx: Prisma.TransactionClient,
  productId: string,
  payload: Payload
) {
  const old = await tx.productVariant.findMany({
    where: {
      productId,
      OR: [
        { deletedAt: null },
        {
          id: {
            in: payload.variants.flatMap((row) => (row.id ? [row.id] : [])),
          },
        },
      ],
    },
    include: {
      options: { include: { option: { include: { attribute: true } } } },
    },
  });
  const owned = new Map(old.map((row) => [row.id, row]));
  const byCombination = new Map(
    old
      .filter((row) => row.deletedAt === null)
      .map((row) => [
        combinationKey(
          row.options.map(
            (ref) => `${ref.option.attribute.position}:${ref.option.value}`
          )
        ),
        row.id,
      ])
  );
  const used = new Set<string>();
  const targets = payload.variants.map((row) => {
    const id = row.id ?? byCombination.get(combinationKey(row.optionRefs));
    if (id && !owned.has(id))
      throw new Error(
        "Varian tidak termasuk produk ini. Muat ulang halaman sebelum menyimpan."
      );
    if (id && used.has(id))
      throw new Error(
        "Identitas varian tidak boleh dipakai pada dua kombinasi."
      );
    if (id) used.add(id);
    return { row, id };
  });
  // Free this product's unique SKUs while replacements are written atomically.
  await tx.productVariant.updateMany({
    where: { productId, deletedAt: null },
    data: { deletedAt: new Date(), isActive: false, sku: null },
  });
  if (!payload.hasVariants) return;
  await tx.variantAttribute.deleteMany({ where: { productId } });
  const optionIds = new Map<string, string>();
  for (const attribute of payload.attributes) {
    const created = await tx.variantAttribute.create({
      data: {
        productId,
        name: attribute.name,
        position: attribute.position,
        options: {
          create: attribute.options.map((option) => ({
            value: option.value,
            position: option.position,
          })),
        },
      },
      include: { options: true },
    });
    created.options.forEach((option) =>
      optionIds.set(`${attribute.position}:${option.value}`, option.id)
    );
  }
  for (const { row, id } of targets) {
    const refs = row.optionRefs.map((ref) => optionIds.get(ref));
    if (refs.some((ref) => !ref))
      throw new Error(
        "Pilihan variasi tidak ditemukan. Periksa daftar variasi."
      );
    if (row.sku) {
      const conflict = await describeVariantSkuConflict(tx, row.sku, productId);
      if (conflict) throw new Error(conflict);
    }
    const fields = {
      sku: row.sku || null,
      price: row.price,
      stock: row.stock,
      weightGram: row.weightGram,
      imageUrl: row.imageUrl || null,
      isActive: row.isActive,
      deletedAt: null,
    };
    if (id) {
      await tx.productVariantOption.deleteMany({ where: { variantId: id } });
      await tx.productVariant.update({
        where: { id },
        data: {
          ...fields,
          options: {
            create: refs.map((optionId) => ({ optionId: optionId! })),
          },
        },
      });
    } else
      await tx.productVariant.create({
        data: {
          ...fields,
          productId,
          options: {
            create: refs.map((optionId) => ({ optionId: optionId! })),
          },
        },
      });
  }
  const active = await tx.productVariant.findMany({
    where: { productId, deletedAt: null, isActive: true },
    select: { price: true, stock: true, weightGram: true },
  });
  if (active.length) {
    const cheapest = active.reduce((a, b) => (b.price < a.price ? b : a));
    await tx.product.update({
      where: { id: productId },
      data: {
        price: cheapest.price,
        stock: active.reduce((sum, row) => sum + row.stock, 0),
        weightGram: cheapest.weightGram,
        discountPrice: null,
      },
    });
  }
}
