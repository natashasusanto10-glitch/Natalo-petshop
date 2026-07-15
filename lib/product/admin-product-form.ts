import type { Prisma } from "@prisma/client";
import { prisma } from "../prisma";
import { deleteProductVideo } from "./product-video";

export type ProductCreationState = "creating" | "ready";

export function productIsVisibleWhere(): { creationState: "ready" } {
  return { creationState: "ready" };
}

export function shouldDeleteCreatingProduct(state: ProductCreationState): boolean {
  return state === "creating";
}

/** Create a product and its nested variants while keeping it invisible. */
export async function createHiddenProduct(payload: Prisma.ProductCreateInput) {
  return prisma.$transaction(async (tx) =>
    tx.product.create({
      data: {
        ...payload,
        creationState: "creating",
        isActive: false,
      },
    }),
  );
}

/** Publish a hidden product, deriving active state from available stock. */
export async function finalizeCreatedProduct(id: string) {
  const product = await prisma.product.findUnique({
    where: { id },
    include: { variants: { select: { stock: true, isActive: true } } },
  });
  if (!product || product.creationState !== "creating") return product;

  const hasStock = product.hasVariants
    ? product.variants.some((variant) => variant.isActive && variant.stock > 0)
    : product.stock > 0;
  const finalized = await prisma.product.updateMany({
    where: { id, creationState: "creating" },
    data: { creationState: "ready", isActive: hasStock },
  });
  if (!finalized.count) return null;
  const updated = await prisma.product.findUnique({ where: { id } });
  if (updated) {
    const { syncProduct } = await import("../search");
    void syncProduct(id);
  }
  return updated;
}

/** Remove only an unfinished product and best-effort clean its Bunny asset. */
export async function compensateCreatedProduct(id: string): Promise<boolean> {
  const product = await prisma.product.findUnique({
    where: { id },
    select: { creationState: true, videoGuid: true },
  });
  if (!product || !shouldDeleteCreatingProduct(product.creationState as ProductCreationState)) {
    return false;
  }
  await prisma.product.delete({ where: { id } });
  if (product.videoGuid) await deleteProductVideo(product.videoGuid);
  return true;
}
