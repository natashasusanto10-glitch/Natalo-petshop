import assert from "node:assert/strict";
import test from "node:test";
import {
  hasValidPaymentProofBytes,
  normalizeAllowedPaymentProofType,
  parseAllowedPaymentProofUrl,
} from "@/lib/chat/payment-proof-security";

test("proof proxy only permits UploadThing HTTPS hosts", () => {
  assert.equal(parseAllowedPaymentProofUrl("https://ufs.sh/f/key")?.hostname, "ufs.sh");
  assert.equal(parseAllowedPaymentProofUrl("https://evil.example/proof.jpg"), null);
  assert.equal(parseAllowedPaymentProofUrl("http://ufs.sh/f/key"), null);
  assert.equal(parseAllowedPaymentProofUrl("https://ufs.sh.evil.example/f/key"), null);
});

test("proof proxy rejects SVG/GIF and content-type spoofing", () => {
  assert.equal(normalizeAllowedPaymentProofType("image/jpeg; charset=binary"), "image/jpeg");
  assert.equal(normalizeAllowedPaymentProofType("image/svg+xml"), null);
  assert.equal(normalizeAllowedPaymentProofType("image/gif"), null);
  const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.equal(hasValidPaymentProofBytes(png, "image/png"), true);
  assert.equal(hasValidPaymentProofBytes(new TextEncoder().encode("<svg></svg>"), "image/png"), false);
});
