import assert from "node:assert/strict";
import test from "node:test";
import {
  buildOrderContextV1,
  deterministicOrderMessageId,
  isOrderContextV1,
} from "@/lib/chat/order-contract";
import { buildReviewNoticeText, parseOrderContextOutboxPayload } from "@/lib/chat/order-outbox";
import { validateChatSendContent } from "@/lib/chat/send-content";

const context = buildOrderContextV1({
  orderNumber: "ORD-20260715-ABC",
  status: "PENDING",
  paymentStatus: "PENDING",
  paymentProofStatus: "PENDING_REVIEW",
  total: 250000,
  itemCount: 3,
  paymentProofUrl: "https://example.test/proof.jpg",
  paymentProofVersion: 2,
  createdAt: new Date("2026-07-15T01:00:00.000Z"),
});

test("order_context v1 emits a stable compact allowlisted payload", () => {
  assert.equal(context.schemaVersion, 1);
  assert.deepEqual(context.order, {
    orderNumber: "ORD-20260715-ABC",
    status: "PENDING",
    paymentStatus: "PENDING",
    paymentProofStatus: "PENDING_REVIEW",
    total: 250000,
    itemCount: 3,
    hasPaymentProof: true,
    proofVersion: 2,
    createdAt: "2026-07-15T01:00:00.000Z",
  });
  assert.equal(isOrderContextV1(context), true);
  assert.equal((context.order as Record<string, unknown>).paymentProofUrl, undefined);
});

test("outbox rejects malformed payload and accepts scoped v1 payload", () => {
  assert.equal(parseOrderContextOutboxPayload(context), null);
  assert.ok(parseOrderContextOutboxPayload({ ...context, orderId: "o1", customerId: "u1" }));
  assert.equal(parseOrderContextOutboxPayload({ ...context, schemaVersion: 2, orderId: "o1", customerId: "u1" }), null);
});

test("deterministic order message id is stable across proof versions", () => {
  assert.equal(deterministicOrderMessageId("order_cuid"), "order_context_order_cuid");
});

test("context-only chat send requires a server-resolved context", () => {
  assert.equal(validateChatSendContent("", true).ok, true);
  assert.equal(validateChatSendContent("halo", false).ok, true);
  assert.equal(validateChatSendContent("", false).ok, false);
  assert.equal(validateChatSendContent("x".repeat(4001), true).ok, false);
});

test("review notice text is plain Indonesian for both outcomes", () => {
  assert.equal(
    buildReviewNoticeText({ status: "VERIFIED", byName: "Natasha", orderNumber: "ORD-1" }),
    "Natasha menandai pembayaran ORD-1 sudah masuk",
  );
  assert.equal(
    buildReviewNoticeText({ status: "REJECTED", byName: "Natasha", orderNumber: "ORD-1", reason: "nominal kurang" }),
    "Natasha menolak bukti transfer ORD-1: nominal kurang",
  );
});

test("outbox payload keeps refreshOnly and notice", () => {
  const ctx = buildOrderContextV1({
    orderNumber: "ORD-1", status: "PAID", paymentStatus: "PAID", paymentProofStatus: "VERIFIED",
    total: 10, itemCount: 1, paymentProofUrl: "https://x", paymentProofVersion: 2,
    createdAt: new Date("2026-10-07T00:00:00Z"),
  });
  const parsed = parseOrderContextOutboxPayload({
    ...ctx, orderId: "o1", customerId: "u1", refreshOnly: true, notice: "hai",
  });
  assert.equal(parsed?.refreshOnly, true);
  assert.equal(parsed?.notice, "hai");
});
