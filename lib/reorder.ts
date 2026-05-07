/**
 * Service: validasi reorder order/item.
 *
 * Tidak menulis ke cart server-side — return data terstruktur agar frontend
 * bisa merge ke localStorage cart. Cart project ini berbasis localStorage.
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

export type ReorderItemResult =
  | {
      status: "added";
      item: ReorderCartItem;
      priceChanged: boolean;
      previousPrice: number;
    }
  | {
      status: "adjusted";
      item: ReorderCartItem;
      requestedQuantity: number;
      availableStock: number;
      priceChanged: boolean;
      previousPrice: number;
    }
  | {
      status: "skipped";
      productId: string;
      variantId: string | null;
      name: string;
      reason: string;
    };

export type ReorderResult = {
  added: ReorderItemResult[];
  adjusted: ReorderItemResult[];
  skipped: ReorderItemResult[];
  orderNumber: string;
};

interface ReorderOptions {
  /** Jika diset, hanya proses item dengan id ini (untuk single-item reorder). */
  onlyItemId?: string;
}

/**
 * Validasi item-item dari order untuk di-reorder.
 *
 * Aturan:
 *  - Produk inactive / dihapus → skipped
 *  - Varian deleted/inactive → skipped
 *  - Stok = 0 → skipped
 *  - Stok < requested qty → adjusted (clamp ke stok)
 *  - Stok cukup → added
 *
 * Voucher TIDAK ikut di-copy (sesuai kebijakan: voucher = konteks waktu order).
 */
export async function validateReorder(
  orderNumber: string,
  userId: string,
  options: ReorderOptions = {}
): Promise<ReorderResult> {
  // Ambil order milik user (validasi ownership)
  const order = await prisma.order.findFirst({
    where: { orderNumber, userId },
    include: {
      items: options.onlyItemId
        ? { where: { id: options.onlyItemId } }
        : true,
    },
  });

  if (!order) {
    throw new Error("Order tidak ditemukan atau bukan milik Anda.");
  }
  if (order.items.length === 0) {
    throw new Error("Item tidak ditemukan dalam order ini.");
  }

  // Bulk fetch produk + varian untuk efisiensi
  const productIds = [...new Set(order.items.map((i) => i.productId))];
  const variantIds = [
    ...new Set(order.items.map((i) => i.variantId).filter(Boolean)),
  ] as string[];

  const [products, variants] = await Promise.all([
    prisma.product.findMany({
      where: { id: { in: productIds } },
      select: {
        id: true,
        name: true,
        slug: true,
        price: true,
        discountPrice: true,
        stock: true,
        weightGram: true,
        imageUrl: true,
        isActive: true,
        hasVariants: true,
      },
    }),
    variantIds.length > 0
      ? prisma.productVariant.findMany({
          where: { id: { in: variantIds } },
          select: {
            id: true,
            productId: true,
            price: true,
            stock: true,
            weightGram: true,
            imageUrl: true,
            isActive: true,
            deletedAt: true,
          },
        })
      : Promise.resolve([]),
  ]);

  const result: ReorderResult = {
    added: [],
    adjusted: [],
    skipped: [],
    orderNumber: order.orderNumber,
  };

  for (const orderItem of order.items) {
    const product = products.find((p) => p.id === orderItem.productId);

    // ── Produk hilang / inactive ─────────────────────────────────
    if (!product) {
      result.skipped.push({
        status: "skipped",
        productId: orderItem.productId,
        variantId: orderItem.variantId,
        name: orderItem.name,
        reason: "Produk sudah tidak tersedia.",
      });
      continue;
    }
    if (!product.isActive) {
      result.skipped.push({
        status: "skipped",
        productId: orderItem.productId,
        variantId: orderItem.variantId,
        name: orderItem.name,
        reason: "Produk sudah di-nonaktifkan oleh penjual.",
      });
      continue;
    }

    // ── Per varian atau non-varian ───────────────────────────────
    let currentPrice: number;
    let currentStock: number;
    let weightGram: number;
    let imageUrl: string | null;

    if (orderItem.variantId) {
      const variant = variants.find((v) => v.id === orderItem.variantId);
      if (!variant || variant.deletedAt || !variant.isActive) {
        result.skipped.push({
          status: "skipped",
          productId: orderItem.productId,
          variantId: orderItem.variantId,
          name: `${orderItem.name}${
            orderItem.variantLabel ? ` (${orderItem.variantLabel})` : ""
          }`,
          reason: "Varian sudah tidak tersedia.",
        });
        continue;
      }
      currentPrice = variant.price;
      currentStock = variant.stock;
      weightGram = variant.weightGram;
      imageUrl = variant.imageUrl ?? product.imageUrl;
    } else {
      // Non-varian: pakai harga produk current (dengan discount kalau ada)
      const hasDiscount =
        product.discountPrice !== null && product.discountPrice < product.price;
      currentPrice = hasDiscount ? product.discountPrice! : product.price;
      currentStock = product.stock;
      weightGram = product.weightGram;
      imageUrl = product.imageUrl;
    }

    const requestedQty = orderItem.quantity;
    const previousPrice = orderItem.price;
    const priceChanged = currentPrice !== previousPrice;

    // ── Stok 0 ────────────────────────────────────────────────────
    if (currentStock === 0) {
      result.skipped.push({
        status: "skipped",
        productId: orderItem.productId,
        variantId: orderItem.variantId,
        name: `${orderItem.name}${
          orderItem.variantLabel ? ` (${orderItem.variantLabel})` : ""
        }`,
        reason: "Stok habis.",
      });
      continue;
    }

    const cartItem: ReorderCartItem = {
      productId: orderItem.productId,
      variantId: orderItem.variantId,
      variantLabel: orderItem.variantLabel,
      name: orderItem.name,
      price: currentPrice,
      quantity: Math.min(requestedQty, currentStock),
      weightGram,
      stock: currentStock,
      imageUrl,
    };

    // ── Stok kurang → adjust ────────────────────────────────────
    if (currentStock < requestedQty) {
      result.adjusted.push({
        status: "adjusted",
        item: cartItem,
        requestedQuantity: requestedQty,
        availableStock: currentStock,
        priceChanged,
        previousPrice,
      });
      continue;
    }

    // ── Stok cukup → added ───────────────────────────────────────
    result.added.push({
      status: "added",
      item: cartItem,
      priceChanged,
      previousPrice,
    });
  }

  return result;
}
