import type { CartItem } from '@/lib/cart';
import { prisma } from '@/lib/prisma';
import { buildCheckoutItemsFromInventory } from '@/lib/checkout-items';

function cartItemKey(item: Pick<CartItem, "productId" | "variantId">) {
  return `${item.productId}:${item.variantId ?? ""}`;
}

function variantOptionLabel(
  variant:
    | {
        options?: {
          option: {
            value: string;
            position: number;
            attribute: { position: number };
          };
        }[];
      }
    | null
    | undefined,
) {
  const options = variant?.options ?? [];
  if (options.length === 0) return null;

  const values = [...options]
    .sort((a, b) => {
      const attrDiff = a.option.attribute.position - b.option.attribute.position;
      if (attrDiff !== 0) return attrDiff;
      return a.option.position - b.option.position;
    })
    .map((entry) => entry.option.value.trim())
    .filter(Boolean);

  return values.length ? values.join(", ") : null;
}

export async function applyCurrentCartPricing(items: CartItem[]): Promise<CartItem[]> {
  if (items.length === 0) return items;
  const now = new Date();

  const productIds = [...new Set(items.map((item) => item.productId))];
  const variantIds = [
    ...new Set(items.map((item) => item.variantId).filter(Boolean)),
  ] as string[];

  const [products, variants] = await Promise.all([
    prisma.product.findMany({
      where: { id: { in: productIds } },
      select: {
        id: true,
        name: true,
        price: true,
        discountPrice: true,
        flashSaleEndsAt: true,
        stock: true,
        categoryId: true,
        weightGram: true,
        isActive: true,
        hasVariants: true,
        discountItems: {
          where: {
            isItemActive: true,
            discount: {
              isActive: true,
              startsAt: { lte: now },
              endsAt: { gt: now },
            },
          },
          select: {
            variantId: true,
            discountedPrice: true,
            discount: { select: { endsAt: true } },
          },
        },
      },
    }),
    variantIds.length
      ? prisma.productVariant.findMany({
          where: { id: { in: variantIds }, deletedAt: null, isActive: true },
          select: {
            id: true,
            productId: true,
            price: true,
            stock: true,
            weightGram: true,
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
        })
      : Promise.resolve([]),
  ]);

  const { checkoutItems } = buildCheckoutItemsFromInventory({
    requestedItems: items.map((item) => ({
      productId: item.productId,
      variantId: item.variantId ?? null,
      variantLabel: item.variantLabel ?? null,
      quantity: item.quantity,
    })),
    products,
    variants,
  });
  const checkoutItemByKey = new Map(checkoutItems.map((item) => [cartItemKey(item), item]));
  const productById = new Map(products.map((product) => [product.id, product]));
  const variantById = new Map(variants.map((variant) => [variant.id, variant]));

  return items.map((item) => {
    const checkoutItem = checkoutItemByKey.get(cartItemKey(item));
    if (!checkoutItem) return item;

    const variant = item.variantId ? variantById.get(item.variantId) : null;
    const product = productById.get(item.productId);
    const originalPrice = variant?.price ?? product?.price ?? item.price;
    const label = variant ? variantOptionLabel(variant) : null;

    return {
      ...item,
      variantLabel: label,
      name: checkoutItem.name || item.name,
      price: checkoutItem.price,
      originalPrice,
      subtotal: checkoutItem.price * item.quantity,
      weightGram: checkoutItem.weightGram,
    };
  });
}

