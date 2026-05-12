import assert from "node:assert/strict";
import test from "node:test";
import { serializeOrderDetail } from "@/lib/order-detail";
import { shouldHideBottomNav } from "@/lib/navigation";

test("order detail serialization exposes product metadata and review state", () => {
  const order = serializeOrderDetail({
    id: "order-1",
    orderNumber: "INV-1",
    customerName: "Budi",
    customerPhone: "081234",
    customerEmail: null,
    status: "DELIVERED",
    paymentStatus: "PAID",
    paymentProvider: "MANUAL",
    paymentUrl: null,
    paymentReference: null,
    subtotal: 100000,
    shippingCost: 10000,
    discount: 0,
    total: 110000,
    manualBank: null,
    uniqueCode: null,
    voucherCode: null,
    manualVoucherCode: null,
    shippingAddress: "Jl. Contoh",
    shippingCity: "Jakarta",
    shippingPostalCode: "12345",
    shippingPinpointAddress: null,
    courierCode: null,
    courierService: null,
    trackingNumber: null,
    shipmentStatus: null,
    biteshipTrackingUrl: null,
    notes: null,
    createdAt: new Date("2026-01-01T00:00:00.000Z"),
    updatedAt: new Date("2026-01-01T00:00:00.000Z"),
    items: [
      {
        id: "item-1",
        name: "Produk",
        quantity: 1,
        price: 100000,
        variantLabel: null,
        productId: "product-1",
        variantId: null,
        product: { slug: "produk", imageUrl: "/produk.jpg" },
        reviews: [{ id: "review-1" }],
      },
    ],
  } as any);

  assert.equal(order.items[0].productSlug, "produk");
  assert.equal(order.items[0].productImage, "/produk.jpg");
  assert.equal(order.items[0].reviewed, true);
});

test("order detail page hides bottom navigation for focused mobile flow", () => {
  assert.equal(shouldHideBottomNav("/pesanan/INV-1"), true);
});
