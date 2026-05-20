import { resolveActiveDiscount } from "@/lib/product-pricing";

export type RequestedCheckoutItem = {
  productId: string;
  variantId?: string | null;
  variantLabel?: string | null;
  quantity: number;
};

/**
 * ProductDiscountItem snapshot untuk apply Promo Toko di checkout.
 * Pre-filtered (sudah dalam periode aktif) di query level.
 */
export type CheckoutDiscountItemSnapshot = {
  variantId: string | null;
  discountedPrice: number;
  discount: { endsAt: Date };
};

export type CheckoutProductSnapshot = {
  id: string;
  name: string;
  price: number;
  discountPrice: number | null;
  /** Optional — default null untuk backwards compat dengan test
   *  fixtures atau caller lama yang belum fetch field ini. */
  flashSaleEndsAt?: Date | null;
  stock: number;
  weightGram: number;
  isActive: boolean;
  hasVariants: boolean;
  /** Optional — default empty array supaya logic safe kalau caller
   *  belum fetch ProductDiscountItem (mis. test atau legacy code). */
  discountItems?: CheckoutDiscountItemSnapshot[];
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

/**
 * Hitung harga efektif single product (non-variant) — apply Flash Sale
 * + Promo Toko priority chain (lowest wins).
 */
function singleProductPrice(product: CheckoutProductSnapshot): number {
  const items = product.discountItems ?? [];
  const promoItems = items
    .filter((it) => it.variantId === null)
    .map((it) => ({
      discountedPrice: it.discountedPrice,
      endsAt: it.discount.endsAt,
    }));
  const discount = resolveActiveDiscount(
    product.price,
    {
      discountPrice: product.discountPrice,
      endsAt: product.flashSaleEndsAt ?? null,
    },
    promoItems,
  );
  return discount ? discount.effectivePrice : product.price;
}

/**
 * Hitung harga efektif untuk satu variant — apply Promo Toko match
 * (variantId-specific) + Flash Sale via ratio dari product level.
 */
function variantPrice(
  product: CheckoutProductSnapshot,
  variant: CheckoutVariantSnapshot,
): number {
  const items = product.discountItems ?? [];
  const promoItems = items
    .filter((it) => it.variantId === variant.id)
    .map((it) => ({
      discountedPrice: it.discountedPrice,
      endsAt: it.discount.endsAt,
    }));
  // Flash Sale ratio dari product → variant.
  // product.discountPrice / product.price = ratio diskon.
  const flashEnd = product.flashSaleEndsAt ?? null;
  const flashSaleForVariant =
    flashEnd && product.discountPrice && product.price > 0
      ? {
          discountPrice: Math.round(
            variant.price * (product.discountPrice / product.price),
          ),
          endsAt: flashEnd,
        }
      : { discountPrice: null, endsAt: null };

  const discount = resolveActiveDiscount(
    variant.price,
    flashSaleForVariant,
    promoItems,
  );
  return discount ? discount.effectivePrice : variant.price;
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
        // Apply Flash Sale + Promo Toko per variant (lowest wins).
        price: variantPrice(product, variant),
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
      // Apply Flash Sale + Promo Toko (single product).
      price: singleProductPrice(product),
      quantity: requested.quantity,
      weightGram: product.weightGram,
    });
  }

  return { checkoutItems, stockErrors };
}
