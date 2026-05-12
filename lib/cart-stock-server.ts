import { prisma } from "@/lib/prisma";
import {
  buildCartStockSnapshots,
  cartStockKey,
  normalizeCartStockVariantId,
  type AggregatedCartStockInput,
  type CartStockInput,
  type CartStockSnapshot,
} from "@/lib/cart-stock";

export async function getCartStockSnapshots(items: CartStockInput[]): Promise<CartStockSnapshot[]> {
  const requestedMap = new Map<string, AggregatedCartStockInput>();
  for (const item of items) {
    const variantId = normalizeCartStockVariantId(item.variantId);
    const key = cartStockKey({ productId: item.productId, variantId });
    const current = requestedMap.get(key);
    requestedMap.set(key, {
      ...item,
      variantId,
      variantLabel: item.variantLabel ?? null,
      quantity: (current?.quantity ?? 0) + item.quantity,
    });
  }

  const requestedItems = [...requestedMap.values()];
  const productIds = [...new Set(requestedItems.map((item) => item.productId))];
  const variantIds = [
    ...new Set(requestedItems.map((item) => item.variantId).filter(Boolean)),
  ] as string[];

  const [products, variants] = await Promise.all([
    productIds.length
      ? prisma.product.findMany({
          where: { id: { in: productIds } },
          select: { id: true, name: true, stock: true, isActive: true, hasVariants: true },
        })
      : Promise.resolve([]),
    variantIds.length
      ? prisma.productVariant.findMany({
          where: { id: { in: variantIds } },
          select: {
            id: true,
            productId: true,
            stock: true,
            isActive: true,
            deletedAt: true,
          },
        })
      : Promise.resolve([]),
  ]);

  return buildCartStockSnapshots({ requestedItems, products, variants });
}
