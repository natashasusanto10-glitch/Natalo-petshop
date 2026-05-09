/**
 * Reorder validation service.
 *
 * Old order items are used only as product/variant references. The cart payload
 * is rebuilt from current product, variant, price, and stock data.
 */

import { prisma } from "@/lib/prisma";

export type ReorderCartItem = {
  productId: string;
  variantId: string | null;
  variantLabel: string | null;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
  stock: number;
  imageUrl: string | null;
};

export type ReorderAddedResult = {
  status: "added";
  item: ReorderCartItem;
  priceChanged: boolean;
  previousPrice: number;
};

export type ReorderAdjustedResult = {
  status: "adjusted";
  item: ReorderCartItem;
  requestedQuantity: number;
  availableStock: number;
  priceChanged: boolean;
  previousPrice: number;
};

export type ReorderSkippedResult = {
  status: "skipped";
  productId: string;
  variantId: string | null;
  variantLabel: string | null;
  name: string;
  reason: string;
  reasonCode:
    | "PRODUCT_UNAVAILABLE"
    | "PRODUCT_INACTIVE"
    | "VARIANT_REQUIRED"
    | "VARIANT_UNAVAILABLE"
    | "OUT_OF_STOCK";
  availableStock?: number;
};

export type ReorderResult = {
  added: ReorderAddedResult[];
  adjusted: ReorderAdjustedResult[];
  skipped: ReorderSkippedResult[];
  orderNumber: string;
};

export type ReorderOrderItem = {
  id?: string;
  productId: string;
  variantId: string | null;
  productNameSnapshot?: string;
  variantNameSnapshot?: string | null;
  priceSnapshot?: number;
  name?: string;
  variantLabel?: string | null;
  price?: number;
  quantity: number;
};

export type ReorderOrder = {
  orderNumber: string;
  items: ReorderOrderItem[];
};

export type ReorderCurrentProduct = {
  id: string;
  name: string;
  price: number;
  discountPrice: number | null;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  isActive: boolean;
  hasVariants: boolean;
};

export type ReorderCurrentVariant = {
  id: string;
  productId: string;
  label?: string | null;
  price: number;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  isActive: boolean;
  deletedAt: Date | null;
};

interface ReorderOptions {
  onlyItemId?: string;
}

export type ReorderRepository = {
  findOrder(
    orderNumber: string,
    userId: string,
    onlyItemId?: string,
  ): Promise<ReorderOrder | null>;
  findOrderById?(
    orderId: string,
    userId: string,
    onlyItemId?: string,
  ): Promise<ReorderOrder | null>;
  findProducts(productIds: string[]): Promise<ReorderCurrentProduct[]>;
  findVariants(variantIds: string[]): Promise<ReorderCurrentVariant[]>;
};

function productPrice(product: ReorderCurrentProduct) {
  return product.discountPrice !== null && product.discountPrice < product.price
    ? product.discountPrice
    : product.price;
}

function productNameSnapshot(item: ReorderOrderItem) {
  return item.productNameSnapshot ?? item.name ?? "Produk";
}

function variantNameSnapshot(item: ReorderOrderItem) {
  return item.variantNameSnapshot ?? item.variantLabel ?? null;
}

function priceSnapshot(item: ReorderOrderItem) {
  return item.priceSnapshot ?? item.price ?? 0;
}

function currentVariantLabel(variant: ReorderCurrentVariant, item: ReorderOrderItem) {
  return variant.label ?? variantNameSnapshot(item);
}

function skipped(
  item: ReorderOrderItem,
  reason: string,
  reasonCode: ReorderSkippedResult["reasonCode"],
  availableStock?: number,
): ReorderSkippedResult {
  return {
    status: "skipped",
    productId: item.productId,
    variantId: item.variantId,
    variantLabel: variantNameSnapshot(item),
    name: productNameSnapshot(item),
    reason,
    reasonCode,
    availableStock,
  };
}

export function buildReorderResult(
  order: ReorderOrder,
  products: ReorderCurrentProduct[],
  variants: ReorderCurrentVariant[],
): ReorderResult {
  const productsById = new Map(products.map((product) => [product.id, product]));
  const variantsById = new Map(variants.map((variant) => [variant.id, variant]));
  const result: ReorderResult = {
    added: [],
    adjusted: [],
    skipped: [],
    orderNumber: order.orderNumber,
  };

  for (const orderItem of order.items) {
    const product = productsById.get(orderItem.productId);

    if (!product) {
      result.skipped.push(
        skipped(orderItem, "Produk sudah tidak tersedia.", "PRODUCT_UNAVAILABLE"),
      );
      continue;
    }

    if (!product.isActive) {
      result.skipped.push(
        skipped(orderItem, "Produk tidak aktif.", "PRODUCT_INACTIVE"),
      );
      continue;
    }

    let currentPrice: number;
    let currentStock: number;
    let weightGram: number;
    let imageUrl: string | null;

    if (orderItem.variantId) {
      const variant = variantsById.get(orderItem.variantId);

      if (
        !variant ||
        variant.productId !== orderItem.productId ||
        variant.deletedAt ||
        !variant.isActive
      ) {
        result.skipped.push(
          skipped(orderItem, "Varian sudah tidak tersedia.", "VARIANT_UNAVAILABLE"),
        );
        continue;
      }

      currentPrice = variant.price;
      currentStock = variant.stock;
      weightGram = variant.weightGram;
      imageUrl = variant.imageUrl ?? product.imageUrl;
    } else {
      if (product.hasVariants) {
        result.skipped.push(
          skipped(orderItem, "Pilih ulang varian produk ini.", "VARIANT_REQUIRED"),
        );
        continue;
      }

      currentPrice = productPrice(product);
      currentStock = product.stock;
      weightGram = product.weightGram;
      imageUrl = product.imageUrl;
    }

    if (currentStock <= 0) {
      result.skipped.push(skipped(orderItem, "Stok habis.", "OUT_OF_STOCK", currentStock));
      continue;
    }

    const requestedQuantity = Math.max(1, orderItem.quantity);
    const quantity = Math.min(requestedQuantity, currentStock);
    const previousPrice = priceSnapshot(orderItem);
    const priceChanged = currentPrice !== previousPrice;
    const variantLabel = orderItem.variantId
      ? currentVariantLabel(variantsById.get(orderItem.variantId)!, orderItem)
      : null;
    const cartItem: ReorderCartItem = {
      productId: orderItem.productId,
      variantId: orderItem.variantId,
      variantLabel,
      name: product.name,
      price: currentPrice,
      quantity,
      weightGram,
      stock: currentStock,
      imageUrl,
    };

    if (currentStock < requestedQuantity) {
      result.adjusted.push({
        status: "adjusted",
        item: cartItem,
        requestedQuantity,
        availableStock: currentStock,
        priceChanged,
        previousPrice,
      });
      continue;
    }

    result.added.push({
      status: "added",
      item: cartItem,
      priceChanged,
      previousPrice,
    });
  }

  return result;
}

export async function validateReorder(
  orderNumber: string,
  userId: string,
  options: ReorderOptions = {},
): Promise<ReorderResult> {
  return validateReorderWithRepository(prismaReorderRepository, orderNumber, userId, options);
}

export async function validateReorderByOrderId(
  orderId: string,
  userId: string,
  options: ReorderOptions = {},
): Promise<ReorderResult> {
  return validateReorderByOrderIdWithRepository(
    prismaReorderRepository,
    orderId,
    userId,
    options,
  );
}

export async function validateReorderWithRepository(
  repository: ReorderRepository,
  orderNumber: string,
  userId: string,
  options: ReorderOptions = {},
): Promise<ReorderResult> {
  const order = await repository.findOrder(orderNumber, userId, options.onlyItemId);

  return validateResolvedReorder(repository, order);
}

export async function validateReorderByOrderIdWithRepository(
  repository: ReorderRepository,
  orderId: string,
  userId: string,
  options: ReorderOptions = {},
): Promise<ReorderResult> {
  if (!repository.findOrderById) {
    throw new Error("Repository reorder belum mendukung pencarian order id.");
  }

  const order = await repository.findOrderById(orderId, userId, options.onlyItemId);

  return validateResolvedReorder(repository, order);
}

async function validateResolvedReorder(
  repository: ReorderRepository,
  order: ReorderOrder | null,
) {
  if (!order) {
    throw new Error("Order tidak ditemukan atau bukan milik Anda.");
  }

  if (order.items.length === 0) {
    throw new Error("Item tidak ditemukan dalam order ini.");
  }

  const productIds = [...new Set(order.items.map((item) => item.productId))];
  const variantIds = [
    ...new Set(order.items.map((item) => item.variantId).filter(Boolean)),
  ] as string[];

  const [products, variants] = await Promise.all([
    repository.findProducts(productIds),
    variantIds.length > 0 ? repository.findVariants(variantIds) : Promise.resolve([]),
  ]);

  return buildReorderResult(order, products, variants);
}

const prismaReorderRepository: ReorderRepository = {
  async findOrder(orderNumber, userId, onlyItemId) {
    const order = await prisma.order.findFirst({
      where: { orderNumber, userId },
      include: {
        items: onlyItemId ? { where: { id: onlyItemId } } : true,
      },
    });

    if (!order) return null;

    return {
      orderNumber: order.orderNumber,
      items: order.items.map((item) => ({
        id: item.id,
        productId: item.productId,
        variantId: item.variantId,
        productNameSnapshot: item.name,
        variantNameSnapshot: item.variantLabel,
        priceSnapshot: item.price,
        quantity: item.quantity,
      })),
    };
  },

  async findOrderById(orderId, userId, onlyItemId) {
    const order = await prisma.order.findFirst({
      where: { id: orderId, userId },
      include: {
        items: onlyItemId ? { where: { id: onlyItemId } } : true,
      },
    });

    if (!order) return null;

    return {
      orderNumber: order.orderNumber,
      items: order.items.map((item) => ({
        id: item.id,
        productId: item.productId,
        variantId: item.variantId,
        productNameSnapshot: item.name,
        variantNameSnapshot: item.variantLabel,
        priceSnapshot: item.price,
        quantity: item.quantity,
      })),
    };
  },

  findProducts(productIds) {
    return prisma.product.findMany({
      where: { id: { in: productIds } },
      select: {
        id: true,
        name: true,
        price: true,
        discountPrice: true,
        stock: true,
        weightGram: true,
        imageUrl: true,
        isActive: true,
        hasVariants: true,
      },
    });
  },

  findVariants(variantIds) {
    return prisma.productVariant.findMany({
      where: { id: { in: variantIds } },
      select: {
        id: true,
        productId: true,
        sku: true,
        price: true,
        stock: true,
        weightGram: true,
        imageUrl: true,
        isActive: true,
        deletedAt: true,
        options: {
          select: {
            option: {
              select: {
                value: true,
                position: true,
                attribute: { select: { position: true } },
              },
            },
          },
        },
      },
    }).then((variants) =>
      variants.map((variant) => ({
        id: variant.id,
        productId: variant.productId,
        label: variantLabelFromOptions(variant),
        price: variant.price,
        stock: variant.stock,
        weightGram: variant.weightGram,
        imageUrl: variant.imageUrl,
        isActive: variant.isActive,
        deletedAt: variant.deletedAt,
      })),
    );
  },
};

type VariantWithOptions = {
  sku: string | null;
  options: Array<{
    option: {
      value: string;
      position: number;
      attribute: { position: number };
    };
  }>;
};

function variantLabelFromOptions(variant: VariantWithOptions) {
  const label = [...variant.options]
    .sort((a, b) => {
      const attrDiff = a.option.attribute.position - b.option.attribute.position;
      return attrDiff || a.option.position - b.option.position;
    })
    .map((ref) => ref.option.value)
    .filter(Boolean)
    .join(" / ");

  return label || variant.sku || null;
}
