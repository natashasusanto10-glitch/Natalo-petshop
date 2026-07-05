import assert from "node:assert/strict";
import test from "node:test";
import {
  filterAvailableAbandonedCartItems,
  splitAbandonedCartCandidates,
} from "@/lib/abandoned-cart-guardrail";
import type { CartStockSnapshot } from "@/lib/cart-stock";

function snapshot(overrides: Partial<CartStockSnapshot>): CartStockSnapshot {
  return {
    key: "prod-1:",
    productId: "prod-1",
    variantId: null,
    variantLabel: null,
    name: "Produk 1",
    requestedQuantity: 1,
    availableStock: 10,
    isAvailable: true,
    source: "product",
    ...overrides,
  };
}

test("filterAvailableAbandonedCartItems keeps only items whose snapshot is available", () => {
  const items = [
    { id: "item-1", productId: "prod-1", variantId: null },
    { id: "item-2", productId: "prod-2", variantId: null },
  ];
  const snapshots = [
    snapshot({ key: "prod-1:", productId: "prod-1", isAvailable: true }),
    snapshot({ key: "prod-2:", productId: "prod-2", isAvailable: false }),
  ];

  const result = filterAvailableAbandonedCartItems(items, snapshots);

  assert.equal(result.length, 1);
  assert.equal(result[0].id, "item-1");
});

test("filterAvailableAbandonedCartItems matches variant-specific items independently", () => {
  const items = [
    { id: "item-1", productId: "prod-1", variantId: "variant-a" },
    { id: "item-2", productId: "prod-1", variantId: "variant-b" },
  ];
  const snapshots = [
    snapshot({
      key: "prod-1:variant-a",
      productId: "prod-1",
      variantId: "variant-a",
      isAvailable: true,
      source: "variant",
    }),
    snapshot({
      key: "prod-1:variant-b",
      productId: "prod-1",
      variantId: "variant-b",
      isAvailable: false,
      source: "variant",
    }),
  ];

  const result = filterAvailableAbandonedCartItems(items, snapshots);

  assert.equal(result.length, 1);
  assert.equal(result[0].id, "item-1");
});

test("filterAvailableAbandonedCartItems drops items with no matching snapshot", () => {
  const items = [{ id: "item-1", productId: "prod-missing", variantId: null }];

  const result = filterAvailableAbandonedCartItems(items, []);

  assert.equal(result.length, 0);
});

test("splitAbandonedCartCandidates marks first-time-eligible items as candidates, not ready to notify", () => {
  const items = [
    { id: "item-1", abandonedCandidateAt: null },
    { id: "item-2", abandonedCandidateAt: null },
  ];

  const result = splitAbandonedCartCandidates(items);

  assert.equal(result.toMark.length, 2);
  assert.equal(result.toNotify.length, 0);
  assert.deepEqual(
    result.toMark.map((i) => i.id),
    ["item-1", "item-2"],
  );
});

test("splitAbandonedCartCandidates notifies items already marked as candidates in a prior run", () => {
  const items = [
    { id: "item-1", abandonedCandidateAt: new Date("2026-07-05T09:00:00Z") },
    { id: "item-2", abandonedCandidateAt: null },
  ];

  const result = splitAbandonedCartCandidates(items);

  assert.equal(result.toNotify.length, 1);
  assert.equal(result.toNotify[0].id, "item-1");
  assert.equal(result.toMark.length, 1);
  assert.equal(result.toMark[0].id, "item-2");
});
