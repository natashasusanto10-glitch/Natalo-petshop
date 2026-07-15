import assert from "node:assert/strict";
import test from "node:test";
import { memberOrdersInclude, serializeMemberOrder } from "@/lib/member-orders";

function orderFixture(overrides: Record<string, unknown> = {}) {
  return {
    id: "order-1",
    orderNumber: "ORD-1",
    createdAt: new Date("2026-07-15T00:00:00.000Z"),
    updatedAt: new Date("2026-07-15T08:00:00.000Z"),
    status: "DELIVERED",
    paymentStatus: "PAID",
    paymentProvider: "MIDTRANS",
    paymentProofUrl: null,
    manualBank: null,
    uniqueCode: null,
    total: 100000,
    subtotal: 100000,
    shippingCost: 0,
    discount: 0,
    paymentUrl: null,
    biteshipTrackingUrl: null,
    orderType: "DELIVERY",
    readyForPickupAt: null,
    pickedUpAt: null,
    shippedAt: new Date("2026-07-15T04:00:00.000Z"),
    timelineEvents: [
      { status: "DELIVERED", occurredAt: new Date("2026-07-15T07:00:00.000Z") },
    ],
    items: [
      {
        id: "item-1",
        name: "Produk",
        quantity: 1,
        price: 100000,
        productId: "product-1",
        variantLabel: null,
        product: { imageUrl: "/product.jpg", category: { name: "Makanan" } },
        reviews: [{ id: "review-1" }],
      },
    ],
    ...overrides,
  } as any;
}

test("member order contract includes review state and Flutter statusUpdatedAt", () => {
  const result = serializeMemberOrder(orderFixture());
  assert.equal(result.items[0].reviewed, true);
  assert.equal(result.statusUpdatedAt, "2026-07-15T07:00:00.000Z");
  assert.equal(result.latestStatusAt, result.statusUpdatedAt);
  assert.ok("reviews" in memberOrdersInclude.items.select);
});

test("member order status timestamp uses relevant canonical legacy field only", () => {
  const readyAt = new Date("2026-07-15T03:00:00.000Z");
  const result = serializeMemberOrder(orderFixture({
    status: "READY_FOR_PICKUP",
    orderType: "SELF_PICKUP",
    timelineEvents: [],
    readyForPickupAt: readyAt,
    items: [{ ...orderFixture().items[0], reviews: [] }],
  }));
  assert.equal(result.statusUpdatedAt, readyAt.toISOString());
  assert.equal(result.items[0].reviewed, false);
});
