export type RequestedCheckoutItem = {
  productId: string;
  variantId?: string | null;
  variantLabel?: string | null;
  quantity: number;
};

export type CheckoutProductSnapshot = {
  id: string;
  name: string;
  price: number;
  discountPrice: number | null;
  stock: number;
  weightGram: number;
  isActive: boolean;
  hasVariants: boolean;
};

export type CheckoutVariantSnapshot = {
  id: string;
  productId: string;
  price: number;
  stock: number;
  weightGram: number;
};

export type CheckedOutItem = {
  productId: string;
  variantId?: string | null;
  variantLabel?: string | null;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
};

function productPrice(product: CheckoutProductSnapshot) {
  return product.discountPrice !== null && product.discountPrice < product.price
    ? product.discountPrice
    : product.price;
}

export function buildCheckoutItemsFromInventory({
  requestedItems,
  products,
  variants,
}: {
  requestedItems: Iterable<RequestedCheckoutItem>;
  products: CheckoutProductSnapshot[];
  variants: CheckoutVariantSnapshot[];
}) {
  const checkoutItems: CheckedOutItem[] = [];
  const stockErrors: string[] = [];

  for (const requested of requestedItems) {
    const product = products.find((row) => row.id === requested.productId);
    if (!product || !product.isActive) {
      stockErrors.push("Produk di keranjang sudah tidak tersedia.");
      continue;
    }

    if (requested.variantId) {
      if (!product.hasVariants) {
        stockErrors.push(`Produk "${product.name}" tidak memakai varian.`);
        continue;
      }

      const variant = variants.find(
        (row) => row.id === requested.variantId && row.productId === requested.productId,
      );
      if (!variant) {
        stockErrors.push(`Varian produk "${product.name}" sudah tidak tersedia.`);
        continue;
      }
      if (variant.stock < requested.quantity) {
        stockErrors.push(
          `"${product.name} (${requested.variantLabel ?? ""})" hanya tersedia ${variant.stock} unit.`,
        );
        continue;
      }

      checkoutItems.push({
        productId: product.id,
        variantId: variant.id,
        variantLabel: requested.variantLabel ?? null,
        name: product.name,
        price: variant.price,
        quantity: requested.quantity,
        weightGram: variant.weightGram,
      });
      continue;
    }

    if (product.hasVariants) {
      stockErrors.push(`Pilih varian untuk produk "${product.name}" sebelum checkout.`);
      continue;
    }

    if (product.stock < requested.quantity) {
      stockErrors.push(
        `${product.name} hanya tersedia ${product.stock}, sedangkan keranjang berisi ${requested.quantity}.`,
      );
      continue;
    }

    checkoutItems.push({
      productId: product.id,
      variantId: null,
      variantLabel: null,
      name: product.name,
      price: productPrice(product),
      quantity: requested.quantity,
      weightGram: product.weightGram,
    });
  }

  return { checkoutItems, stockErrors };
}
