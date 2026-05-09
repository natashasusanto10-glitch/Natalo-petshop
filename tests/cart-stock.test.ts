import assert from "node:assert/strict";
import test from "node:test";
import { reconcileCartItemsWithStock, type CartStockSnapshot } from "@/lib/cart-stock";
import type { CartItem } from "@/lib/cart";

function item(overrides: Partial<CartItem>): CartItem {
  return {
    productId: "prod-friskies",
    variantId: null,
    variantLabel: null,
    name: "Friskies Party Mix 60g Cat Treats",
    price: 20000,
    quantity: 1,
    subtotal: 20000,
    weightGram: 60,
    imageUrl: null,
    stock: null,
    ...overrides,
  };
}

function snapshot(overrides: Partial<CartStockSnapshot>): CartStockSnapshot {
  return {
    key: "prod-friskies:",
    productId: "prod-friskies",
    variantId: null,
    variantLabel: null,
    name: "Friskies Party Mix 60g Cat Treats",
    requestedQuantity: 1,
    availableStock: 10,
    isAvailable: true,
    source: "product",
    ...overrides,
  };
}

test("cart displays latest available stock instead of cached cart snapshot stock", () => {
  const result = reconcileCartItemsWithStock(
    [item({ quantity: 9, stock: 9 })],
    [snapshot({ requestedQuantity: 9, availableStock: 3 })],
  );

  assert.equal(result.changed, true);
  assert.equal(result.ok, false);
  assert.equal(result.items[0].stock, 3);
  assert.equal(result.items[0].quantity, 3);
  assert.match(result.issues[0].message, /tersedia 3 unit/);
});

test("checkout rejects quantity above current available stock until cart is adjusted", () => {
  const result = reconcileCartItemsWithStock(
    [item({ quantity: 5, stock: 5 })],
    [snapshot({ requestedQuantity: 5, availableStock: 4 })],
  );

  assert.equal(result.ok, false);
  assert.equal(result.issues[0].action, "reduced");
  assert.equal(result.items[0].quantity, 4);
});

test("cart stock updates when available stock changes even if quantity remains valid", () => {
  const result = reconcileCartItemsWithStock(
    [item({ quantity: 2, stock: 9 })],
    [snapshot({ requestedQuantity: 2, availableStock: 6 })],
  );

  assert.equal(result.changed, true);
  assert.equal(result.ok, true);
  assert.equal(result.items[0].stock, 6);
  assert.equal(result.items[0].quantity, 2);
});

test("variant-specific stock is reconciled independently for Beachside and Classic", () => {
  const beachside = item({
    variantId: "variant-beachside",
    variantLabel: "Beachside",
    quantity: 9,
    stock: 9,
  });
  const classic = item({
    variantId: "variant-classic",
    variantLabel: "Classic",
    quantity: 7,
    stock: 7,
  });

  const result = reconcileCartItemsWithStock(
    [beachside, classic],
    [
      snapshot({
        key: "prod-friskies:variant-beachside",
        variantId: "variant-beachside",
        variantLabel: "Beachside",
        requestedQuantity: 9,
        availableStock: 3,
        source: "variant",
      }),
      snapshot({
        key: "prod-friskies:variant-classic",
        variantId: "variant-classic",
        variantLabel: "Classic",
        requestedQuantity: 7,
        availableStock: 4,
        source: "variant",
      }),
    ],
  );

  assert.equal(result.ok, false);
  assert.equal(result.items.find((cartItem) => cartItem.variantLabel === "Beachside")?.stock, 3);
  assert.equal(result.items.find((cartItem) => cartItem.variantLabel === "Beachside")?.quantity, 3);
  assert.equal(result.items.find((cartItem) => cartItem.variantLabel === "Classic")?.stock, 4);
  assert.equal(result.items.find((cartItem) => cartItem.variantLabel === "Classic")?.quantity, 4);
});

test("current implementation uses global product or variant stock; no branch/store stock layer exists", () => {
  const result = reconcileCartItemsWithStock(
    [item({ quantity: 2, stock: 2 })],
    [snapshot({ requestedQuantity: 2, availableStock: 8, source: "product" })],
  );

  assert.equal(result.items[0].stock, 8);
  assert.equal(result.snapshots[0].source, "product");
});
