import assert from "node:assert/strict";
import test from "node:test";
import {
  buildCheckoutItemsFromInventory,
  type CheckoutProductSnapshot,
  type CheckoutVariantSnapshot,
} from "@/lib/checkout-items";

function product(overrides: Partial<CheckoutProductSnapshot> = {}): CheckoutProductSnapshot {
  return {
    id: "product-1",
    name: "Royal Canin Kitten",
    price: 120000,
    discountPrice: null,
    stock: 5,
    weightGram: 500,
    isActive: true,
    hasVariants: false,
    ...overrides,
  };
}

function variant(overrides: Partial<CheckoutVariantSnapshot> = {}): CheckoutVariantSnapshot {
  return {
    id: "variant-1",
    productId: "product-1",
    price: 125000,
    stock: 3,
    weightGram: 2000,
    ...overrides,
  };
}

test("checkout rejects variant products without a selected variant", () => {
  const result = buildCheckoutItemsFromInventory({
    requestedItems: [{ productId: "product-1", variantId: null, quantity: 1 }],
    products: [product({ hasVariants: true, stock: 3 })],
    variants: [variant()],
  });

  assert.equal(result.checkoutItems.length, 0);
  assert.match(result.stockErrors[0], /Pilih varian/);
});

test("checkout rejects variants that do not belong to the requested product", () => {
  const result = buildCheckoutItemsFromInventory({
    requestedItems: [
      {
        productId: "product-1",
        variantId: "variant-from-other-product",
        variantLabel: "2 KG",
        quantity: 1,
      },
    ],
    products: [product({ hasVariants: true })],
    variants: [variant({ id: "variant-from-other-product", productId: "product-2" })],
  });

  assert.equal(result.checkoutItems.length, 0);
  assert.match(result.stockErrors[0], /Varian produk/);
});

test("checkout builds valid variant items from variant price and stock", () => {
  const result = buildCheckoutItemsFromInventory({
    requestedItems: [
      {
        productId: "product-1",
        variantId: "variant-1",
        variantLabel: "2 KG",
        quantity: 2,
      },
    ],
    products: [product({ hasVariants: true, stock: 10 })],
    variants: [variant({ price: 125000, stock: 2, weightGram: 2000 })],
  });

  assert.deepEqual(result.stockErrors, []);
  assert.equal(result.checkoutItems[0].variantId, "variant-1");
  assert.equal(result.checkoutItems[0].price, 125000);
  assert.equal(result.checkoutItems[0].quantity, 2);
  assert.equal(result.checkoutItems[0].weightGram, 2000);
});

test("checkout rejects non-variant products submitted with a variant id", () => {
  const result = buildCheckoutItemsFromInventory({
    requestedItems: [{ productId: "product-1", variantId: "variant-1", quantity: 1 }],
    products: [product({ hasVariants: false })],
    variants: [variant()],
  });

  assert.equal(result.checkoutItems.length, 0);
  assert.match(result.stockErrors[0], /tidak memakai varian/);
});
