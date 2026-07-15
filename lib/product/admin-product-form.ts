import type { Prisma } from "@prisma/client";
import { prisma } from "../prisma";
import { deleteProductVideo } from "./product-video";

export type ProductCreationState = "creating" | "ready";

export type ProductFormPayload = {
  name: string;
  description?: string;
  imageUrls: string[];
  categoryId?: string | null;
  brandId?: string | null;
  price?: number;
  stock?: number;
  weightGram?: number;
  sku?: string | null;
  hasVariants?: boolean;
  attributes?: unknown[];
  variants?: unknown[];
  video?: { guid?: string | null; url?: string | null; status?: string | null } | null;
};

export type NormalizedProductFormPayload = {
  name: string;
  description: string;
  imageUrl: string;
  gallery: string[];
  categoryId: string | null;
  brandId: string | null;
  price?: number;
  stock?: number;
  weightGram?: number;
  sku: string | null;
  hasVariants: boolean;
  attributes: unknown[];
  variants: unknown[];
  video: ProductFormPayload["video"];
};

export function normalizeProductFormPayload(input: ProductFormPayload): NormalizedProductFormPayload {
  const images = (input.imageUrls ?? []).map((url) => url.trim()).filter(Boolean);
  if (images.length === 0) throw new Error("Minimal satu foto wajib diisi");
  if (images.length > 9) throw new Error("Maksimal 9 foto dapat diisi");
  return {
    name: input.name.trim(),
    description: input.description?.trim() ?? "",
    imageUrl: images[0],
    gallery: images.slice(1),
    categoryId: input.categoryId?.trim() || null,
    brandId: input.brandId?.trim() || null,
    price: input.price === undefined ? undefined : Math.round(input.price),
    stock: input.stock === undefined ? undefined : Math.round(input.stock),
    weightGram: input.weightGram === undefined ? undefined : Math.round(input.weightGram),
    sku: input.sku?.trim() || null,
    hasVariants: input.hasVariants ?? false,
    attributes: input.attributes ?? [],
    variants: input.variants ?? [],
    video: input.video ?? null,
  };
}

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
