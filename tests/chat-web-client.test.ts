import assert from "node:assert/strict";
import test from "node:test";
import {
  chatHref, forwardCursor, markFailed, mergeMessages, newClientMsgId,
  orderCardLabel, parseChatContext, pendingMessage, toWebMessage,
} from "@/lib/chat/web-client";

test("newClientMsgId lolos aturan server", () => {
  const id = newClientMsgId();
  assert.match(id, /^web_[A-Za-z0-9_-]{4,60}$/);
  assert.ok(id.length >= 8 && id.length <= 64);
  assert.notEqual(newClientMsgId(), id);
});

test("pesan server menggantikan pesan lokal dengan clientMsgId sama, urut waktu", () => {
  const local = pendingMessage({ clientMsgId: "web_a1b2c3d4", text: "halo", now: 500 });
  const merged = mergeMessages([local], [
    { id: "m2", senderRole: "staff", type: "text", text: "hai", createdAt: 600 },
    { id: "m1", clientMsgId: "web_a1b2c3d4", senderRole: "customer", type: "text", text: "halo", createdAt: 510 },
  ]);
  assert.deepEqual(merged.map((m) => m.localKey), ["m1", "m2"]);
  assert.equal(merged[0].localState, undefined);
});

test("gabung dua kali tidak menggandakan pesan", () => {
  const a = [{ id: "m1", senderRole: "customer" as const, type: "text" as const, text: "x", createdAt: 1 }];
  const once = mergeMessages([], a);
  assert.equal(mergeMessages(once, a).length, 1);
});

test("markFailed hanya menandai pesan lokal yang cocok", () => {
  const list = [pendingMessage({ clientMsgId: "web_aaaa1111", text: "a", now: 1 }), toWebMessage({ id: "m9", senderRole: "staff", type: "text", createdAt: 2 })];
  const out = markFailed(list, "web_aaaa1111");
  assert.equal(out[0].localState, "failed");
  assert.equal(out[1].localState, undefined);
});

test("kursor maju: pakai nextCursor server, lalu createdAt server terbesar, abaikan pesan lokal", () => {
  const list = [toWebMessage({ id: "m1", senderRole: "staff", type: "text", createdAt: 100 }), pendingMessage({ clientMsgId: "web_bbbb2222", text: "b", now: 999 })];
  assert.equal(forwardCursor(list, 150, 50), 150);
  assert.equal(forwardCursor(list, null, 50), 100);
  assert.equal(forwardCursor([], null, 50), 50);
  assert.equal(forwardCursor([toWebMessage({ id: "m4", senderRole: "staff", type: "text", createdAt: 400 })], null, 500), 500);
});

test("label kartu pesanan bahasa sehari-hari", () => {
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentStatus: "PAID" }), { text: "Pembayaran terverifikasi", tone: "ok" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentProofStatus: "REJECTED" }), { text: "Bukti transfer ditolak", tone: "bad" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentProofStatus: "PENDING_REVIEW" }), { text: "Bukti sedang dicek", tone: "warn" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentStatus: "UNPAID" }), { text: "Menunggu pembayaran", tone: "info" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentStatus: "PENDING" }), { text: "Menunggu pembayaran", tone: "info" });
  assert.deepEqual(orderCardLabel({ orderNumber: "A", paymentStatus: "PAID", paymentProofStatus: "REJECTED" }), { text: "Pembayaran terverifikasi", tone: "ok" });
});

test("tautan & konteks chat aman", () => {
  assert.equal(chatHref(), "/chat");
  assert.equal(chatHref({ orderNumber: "ORD-1" }), "/chat?order=ORD-1");
  assert.equal(chatHref({ productId: "p_1" }), "/chat?product=p_1");
  assert.deepEqual(parseChatContext(new URLSearchParams("order=ORD-20261022-5LLQZS")), { type: "order", orderNumber: "ORD-20261022-5LLQZS" });
  assert.deepEqual(parseChatContext(new URLSearchParams("product=cm9abc")), { type: "product", productId: "cm9abc" });
  assert.equal(parseChatContext(new URLSearchParams("order=<script>")), null);
  assert.equal(parseChatContext(new URLSearchParams("")), null);
});
