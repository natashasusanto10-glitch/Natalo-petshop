import assert from "node:assert/strict";
import test from "node:test";
import { createHmac } from "node:crypto";
import {
  chatIdForUser,
  projectMessageForCustomer,
  isValidClientMsgId,
  verifyWebhookSignature,
  slidingWindowAllow,
  parseChatEnabled,
  computeChatHoursStatus,
} from "@/lib/chat/core";

test("chatIdForUser memprefix cust_", () => {
  assert.equal(chatIdForUser("ckuser123"), "cust_ckuser123");
});

test("projeksi membuang staffOnly & internal", () => {
  const staffOnly = projectMessageForCustomer({
    type: "system", text: "assigned ke CS", staffOnly: true, createdAt: 1,
  });
  assert.equal(staffOnly, null);

  const ok = projectMessageForCustomer({
    id: "m1", senderRole: "staff", senderName: "Sisca", type: "text",
    text: "halo", createdAt: 2, status: "sent",
    // field yang TAK boleh bocor:
    readByStaffAt: 99, internalFlag: true,
  } as Record<string, unknown>);
  assert.equal(ok?.text, "halo");
  assert.equal(ok?.senderRole, "staff");
  assert.equal((ok as Record<string, unknown>).readByStaffAt, undefined);
  assert.equal((ok as Record<string, unknown>).internalFlag, undefined);
});

test("projeksi product: hanya field allowlist yang ikut, cost/margin/supplier dibuang", () => {
  const ok = projectMessageForCustomer({
    type: "product",
    senderRole: "staff",
    createdAt: 3,
    product: {
      productId: "p1",
      name: "RC",
      price: 285000,
      stock: 8,
      // field internal yang TAK boleh bocor ke customer:
      cost: 120000,
      margin: 0.4,
      supplier: "X",
    },
  } as Record<string, unknown>);
  assert.equal(ok?.product?.productId, "p1");
  assert.equal(ok?.product?.name, "RC");
  assert.equal(ok?.product?.price, 285000);
  assert.equal(ok?.product?.stock, 8);
  assert.equal((ok?.product as Record<string, unknown> | undefined)?.cost, undefined);
  assert.equal((ok?.product as Record<string, unknown> | undefined)?.margin, undefined);
  assert.equal((ok?.product as Record<string, unknown> | undefined)?.supplier, undefined);
});

test("projeksi order: hanya field allowlist yang ikut, field internal dibuang", () => {
  const ok = projectMessageForCustomer({
    type: "order_context",
    senderRole: "staff",
    createdAt: 4,
    order: {
      orderNumber: "ORD-1",
      status: "shipped",
      total: 150000,
      // field internal yang TAK boleh bocor ke customer:
      cost: 90000,
      margin: 0.4,
      internalNotes: "customer complained",
    },
  } as Record<string, unknown>);
  assert.equal(ok?.order?.orderNumber, "ORD-1");
  assert.equal(ok?.order?.status, "shipped");
  assert.equal(ok?.order?.total, 150000);
  assert.equal((ok?.order as Record<string, unknown> | undefined)?.cost, undefined);
  assert.equal((ok?.order as Record<string, unknown> | undefined)?.margin, undefined);
  assert.equal((ok?.order as Record<string, unknown> | undefined)?.internalNotes, undefined);
});

test("isValidClientMsgId menolak sampah", () => {
  assert.equal(isValidClientMsgId("550e8400-e29b-41d4-a716-446655440000"), true);
  assert.equal(isValidClientMsgId(""), false);
  assert.equal(isValidClientMsgId("x".repeat(200)), false);
  assert.equal(isValidClientMsgId(123 as unknown), false);
});

test("verifyWebhookSignature HMAC cocok & timing-safe", () => {
  const body = JSON.stringify({ chatId: "cust_a", messageId: "m1" });
  const secret = "s3cr3t";
  const sig = createHmac("sha256", secret).update(body).digest("hex");
  assert.equal(verifyWebhookSignature(body, sig, secret), true);
  assert.equal(verifyWebhookSignature(body, "deadbeef", secret), false);
  assert.equal(verifyWebhookSignature(body, "", secret), false);
});

test("slidingWindowAllow menahan burst", () => {
  const now = 10_000;
  // 5 pesan dalam 10 dtk terakhir, limit 5 -> tolak yg ke-6
  const ts = [9500, 9000, 8500, 8000, 7500];
  assert.equal(slidingWindowAllow(ts, now, 5, 10_000), false);
  // yg lama keluar window -> izinkan
  assert.equal(slidingWindowAllow([500, 400], now, 5, 10_000), true);
});

test("parseChatEnabled default true, hanya false eksplisit yang mematikan", () => {
  assert.equal(parseChatEnabled(undefined), true);
  assert.equal(parseChatEnabled({}), true);
  assert.equal(parseChatEnabled({ chatEnabled: false }), false);
  assert.equal(parseChatEnabled({ chatEnabled: true }), true);
});

test("computeChatHoursStatus: online/di-luar-jam berbasis WIB", () => {
  const hours = { timezone: "Asia/Jakarta", days: {
    mon: { open: "08:00", close: "21:00" }, sun: { open: null, close: null } } };
  // 2024-01-01 = Senin. 05:00 UTC = 12:00 WIB -> online
  assert.equal(computeChatHoursStatus(hours, Date.UTC(2024, 0, 1, 5, 0)).online, true);
  // 15:00 UTC = 22:00 WIB -> tutup
  assert.equal(computeChatHoursStatus(hours, Date.UTC(2024, 0, 1, 15, 0)).online, false);
  // 2024-01-07 = Minggu (tutup seharian)
  assert.equal(computeChatHoursStatus(hours, Date.UTC(2024, 0, 7, 5, 0)).online, false);
});
