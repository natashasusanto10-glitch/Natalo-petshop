import { prisma } from "@/lib/prisma";
import { cartStockKey, type CartStockInput, type CartStockSnapshot } from "@/lib/cart-stock";

export async function getCartStockSnapshots(items: CartStockInput[]): Promise<CartStockSnapshot[]> {
  const requestedMap = new Map<string, CartStockInput & { quantity: number }>();
  for (const item of items) {
    const key = cartStockKey(item);
    const current = requestedMap.get(key);
    requestedMap.set(key, {
      ...item,
      variantId: item.variantId ?? null,
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
          select: { id: true, name: true, stock: true, isActive: true },
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

  return requestedItems.map((requested) => {
    const key = cartStockKey(requested);
    const product = products.find((item) => item.id === requested.productId);
    const displayName = requested.name || product?.name || "Produk";

    if (!product || !product.isActive) {
      return {
        key,
        productId: requested.productId,
        variantId: requested.variantId ?? null,
        variantLabel: requested.variantLabel ?? null,
        name: displayName,
        requestedQuantity: requested.quantity,
        availableStock: 0,
        isAvailable: false,
        source: requested.variantId ? "variant" : "product",
        message: `${displayName} sudah tidak tersedia.`,
      };
    }

    if (requested.variantId) {
      const variant = variants.find(
        (item) => item.id === requested.variantId && item.productId === requested.productId,
      );
      const isAvailable = Boolean(variant && variant.isActive && !variant.deletedAt);
      return {
        key,
        productId: requested.productId,
        variantId: requested.variantId,
        variantLabel: requested.variantLabel ?? null,
        name: displayName,
        requestedQuantity: requested.quantity,
        availableStock: isAvailable ? variant?.stock ?? 0 : 0,
        isAvailable,
        source: "variant",
        message: isAvailable
          ? undefined
          : `Varian ${displayName}${requested.variantLabel ? ` (${requested.variantLabel})` : ""} sudah tidak tersedia.`,
      };
    }

    return {
      key,
      productId: requested.productId,
      variantId: null,
      variantLabel: null,
      name: displayName,
      requestedQuantity: requested.quantity,
      availableStock: product.stock,
      isAvailable: true,
      source: "product",
    };
  });
}
