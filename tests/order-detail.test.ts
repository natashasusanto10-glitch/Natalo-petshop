import assert from "node:assert/strict";
import test from "node:test";
import {
  getFirstReviewableOrderItem,
  manualPaymentDeadlineIso,
  serializeOrderDetail,
} from "@/lib/order-detail";
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
    productVoucherCode: null,
    shippingVoucherCode: null,
    loyaltyVoucherCode: null,
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
    // serializeOrderDetail meng-iterate voucherUsages (detail diskon per
    // voucher, ditambahkan setelah test ini ditulis) — fixture wajib punya
    // array ini walau kosong supaya `.map()` tidak crash.
    voucherUsages: [],
  } as any);

  assert.equal(order.items[0].productSlug, "produk");
  assert.equal(order.items[0].productImage, "/produk.jpg");
  assert.equal(order.items[0].reviewed, true);
});

test("order detail page hides bottom navigation for focused mobile flow", () => {
  assert.equal(shouldHideBottomNav("/pesanan/INV-1"), true);
});

test("order detail review CTA targets the first unreviewed delivered item", () => {
  const items = [
    { id: "item-reviewed", reviewed: true },
    { id: "item-open", reviewed: false },
    { id: "item-later", reviewed: false },
  ];

  const item = getFirstReviewableOrderItem({
    status: "DELIVERED",
    canReview: true,
    items,
  });

  assert.equal(item?.id, "item-open");
});

test("order detail review CTA is unavailable before delivery or without owner access", () => {
  const items = [{ id: "item-open", reviewed: false }];

  assert.equal(
    getFirstReviewableOrderItem({
      status: "SHIPPED",
      canReview: true,
      items,
    }),
    null
  );
  assert.equal(
    getFirstReviewableOrderItem({
      status: "DELIVERED",
      canReview: false,
      items,
    }),
    null
  );
});

test("manual payment deadline follows the configured checkout window", () => {
  const previous = process.env.AUTO_CANCEL_MANUAL_HOURS;
  process.env.AUTO_CANCEL_MANUAL_HOURS = "12";
  try {
    const deadline = manualPaymentDeadlineIso({
      paymentProvider: "MANUAL",
      paymentStatus: "PENDING",
      status: "PENDING",
      paymentProofUrl: null,
      createdAt: new Date("2026-07-14T06:00:00.000Z"),
    } as any);

    assert.equal(deadline, "2026-07-14T18:00:00.000Z");
  } finally {
    if (previous == null) delete process.env.AUTO_CANCEL_MANUAL_HOURS;
    else process.env.AUTO_CANCEL_MANUAL_HOURS = previous;
  }
});

test("manual payment deadline is hidden after proof or for Midtrans", () => {
  const base = {
    paymentStatus: "PENDING",
    status: "PENDING",
    createdAt: new Date("2026-07-14T06:00:00.000Z"),
  };

  assert.equal(
    manualPaymentDeadlineIso({
      ...base,
      paymentProvider: "MANUAL",
      paymentProofUrl: "https://cdn.example/proof.jpg",
    } as any),
    null
  );
  assert.equal(
    manualPaymentDeadlineIso({
      ...base,
      paymentProvider: "MIDTRANS",
      paymentProofUrl: null,
    } as any),
    null
  );
});
