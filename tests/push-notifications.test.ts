import assert from "node:assert/strict";
import test from "node:test";
import { buildOrderStatusPushPayload, firstOrderItemImageUrl } from "@/lib/push";
import { getPushNavigationTarget } from "@/lib/push-client";

test("order push payload carries order metadata for notification click routing", () => {
  const payload = buildOrderStatusPushPayload({
    orderId: "order-1",
    orderNumber: "ORD-1",
    status: "SHIPPED",
    trackingToken: "track-token",
    trackingNumber: "AWB123",
    courierCode: "jne",
  });

  assert.equal(payload?.data?.order_id, "order-1");
  assert.equal(payload?.data?.order_number, "ORD-1");
  assert.equal(payload?.data?.order_status, "SHIPPED");
  assert.equal(payload?.url, "/pesanan/ORD-1?token=track-token");
});

test("delivered push opens order detail with review intent", () => {
  const payload = buildOrderStatusPushPayload({
    orderId: "order-2",
    orderNumber: "ORD-2",
    status: "DELIVERED",
  });

  assert.equal(payload?.actions?.[0]?.action, "review");
  assert.equal(payload?.url, "/pesanan/ORD-2?review=1");
});

test("push click target accepts internal order URLs and rejects admin URLs", () => {
  assert.equal(
    getPushNavigationTarget({ url: "/pesanan/ORD-1?review=1" }),
    "/pesanan/ORD-1?review=1"
  );
  assert.equal(
    getPushNavigationTarget({ order_number: "ORD-2" }),
    "/pesanan/ORD-2"
  );
  assert.equal(getPushNavigationTarget({ url: "/admin/orders" }), null);
});

test("firstOrderItemImageUrl: ambil foto item pertama", () => {
  const url = firstOrderItemImageUrl([
    { product: { imageUrl: "https://cdn/first.jpg" } },
    { product: { imageUrl: "https://cdn/second.jpg" } },
  ]);
  assert.equal(url, "https://cdn/first.jpg");
});

test("firstOrderItemImageUrl: order tanpa item → null", () => {
  assert.equal(firstOrderItemImageUrl([]), null);
});

test("firstOrderItemImageUrl: item pertama tanpa foto produk → null", () => {
  assert.equal(
    firstOrderItemImageUrl([{ product: { imageUrl: null } }]),
    null,
  );
});
