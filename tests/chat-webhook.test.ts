import assert from "node:assert/strict";
import test from "node:test";
import { createHmac } from "node:crypto";
import { verifyWebhookSignature } from "@/lib/chat/core";
import { parseWebhookPayload } from "@/app/api/chat/webhook/route";

// ---------------------------------------------------------------------------
// parseWebhookPayload — helper murni: parse + validasi field wajib dari raw
// body JSON. Field wajib mengikuti kontrak final Plan 2 Task 8 + Plan 3:
// { chatId, customerUserId, messageId, preview, senderName }. senderName
// OPSIONAL (route fallback ke "Natalo" bila kosong — lihat brief).
// ---------------------------------------------------------------------------

test("parseWebhookPayload: payload valid -> objek dengan semua field", () => {
  const raw = JSON.stringify({
    chatId: "cust_u1",
    customerUserId: "u1",
    messageId: "m1",
    preview: "Halo, ada yang bisa dibantu?",
    senderName: "Sisca",
  });
  const parsed = parseWebhookPayload(raw);
  assert.deepEqual(parsed, {
    chatId: "cust_u1",
    customerUserId: "u1",
    messageId: "m1",
    preview: "Halo, ada yang bisa dibantu?",
    senderName: "Sisca",
  });
});

test("parseWebhookPayload: senderName opsional -> tetap objek (undefined)", () => {
  const raw = JSON.stringify({
    chatId: "cust_u1",
    customerUserId: "u1",
    messageId: "m1",
    preview: "Halo",
  });
  const parsed = parseWebhookPayload(raw);
  assert.ok(parsed);
  assert.equal(parsed?.chatId, "cust_u1");
  assert.equal(parsed?.senderName, undefined);
});

test("parseWebhookPayload: field wajib hilang -> null", () => {
  assert.equal(
    parseWebhookPayload(JSON.stringify({ customerUserId: "u1", messageId: "m1", preview: "x" })),
    null,
  ); // chatId hilang
  assert.equal(
    parseWebhookPayload(JSON.stringify({ chatId: "c1", messageId: "m1", preview: "x" })),
    null,
  ); // customerUserId hilang
  assert.equal(
    parseWebhookPayload(JSON.stringify({ chatId: "c1", customerUserId: "u1", preview: "x" })),
    null,
  ); // messageId hilang
  assert.equal(
    parseWebhookPayload(JSON.stringify({ chatId: "c1", customerUserId: "u1", messageId: "m1" })),
    null,
  ); // preview hilang
});

test("parseWebhookPayload: field wajib bukan string -> null", () => {
  assert.equal(
    parseWebhookPayload(
      JSON.stringify({ chatId: 123, customerUserId: "u1", messageId: "m1", preview: "x" }),
    ),
    null,
  );
});

test("parseWebhookPayload: raw bukan JSON valid -> null", () => {
  assert.equal(parseWebhookPayload("{not json"), null);
  assert.equal(parseWebhookPayload(""), null);
});

test("parseWebhookPayload: JSON valid tapi bukan object (array/null/string) -> null", () => {
  assert.equal(parseWebhookPayload("[1,2,3]"), null);
  assert.equal(parseWebhookPayload("null"), null);
  assert.equal(parseWebhookPayload('"hello"'), null);
});

// ---------------------------------------------------------------------------
// verifyWebhookSignature (reuse Task 2, sudah diuji di chat-core.test.ts) —
// di sini kita uji ulang lewat skenario webhook nyata: HMAC dihitung dgn
// node:crypto atas raw body PERSIS (bukan objek yang di-reserialize), supaya
// perilaku "signature dihitung atas exact bytes" ter-cover di test ini juga.
// ---------------------------------------------------------------------------

const SECRET = "test-webhook-secret-xyz";

function signRaw(raw: string, secret: string): string {
  return createHmac("sha256", secret).update(raw).digest("hex");
}

test("verifyWebhookSignature: signature valid atas raw body -> true", () => {
  const raw = JSON.stringify({
    chatId: "cust_u1", customerUserId: "u1", messageId: "m1", preview: "Halo", senderName: "Sisca",
  });
  const sig = signRaw(raw, SECRET);
  assert.equal(verifyWebhookSignature(raw, sig, SECRET), true);
});

test("verifyWebhookSignature: body tampered setelah signing -> false", () => {
  const raw = JSON.stringify({
    chatId: "cust_u1", customerUserId: "u1", messageId: "m1", preview: "Halo", senderName: "Sisca",
  });
  const sig = signRaw(raw, SECRET);
  const tampered = raw.replace("Halo", "HALO!!");
  assert.equal(verifyWebhookSignature(tampered, sig, SECRET), false);
});

test("verifyWebhookSignature: secret salah -> false", () => {
  const raw = JSON.stringify({ chatId: "c1", customerUserId: "u1", messageId: "m1", preview: "x" });
  const sig = signRaw(raw, SECRET);
  assert.equal(verifyWebhookSignature(raw, sig, "secret-lain"), false);
});

test("verifyWebhookSignature: header/secret kosong -> false", () => {
  const raw = JSON.stringify({ chatId: "c1", customerUserId: "u1", messageId: "m1", preview: "x" });
  assert.equal(verifyWebhookSignature(raw, "", SECRET), false);
  assert.equal(verifyWebhookSignature(raw, signRaw(raw, SECRET), ""), false);
});
