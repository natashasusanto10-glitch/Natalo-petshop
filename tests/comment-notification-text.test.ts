import { test } from "node:test";
import assert from "node:assert/strict";
import { buildCommentNotificationText } from "../lib/feed/notification-center";

test("judul = nama + 'berkomentar' (memuat 'komentar'), body = isi", () => {
  const r = buildCommentNotificationText("Andi", "Done ✅");
  assert.equal(r.title, "Andi berkomentar");
  assert.match(r.title, /komentar/); // load-bearing utk filter tab Feed
  assert.equal(r.body, "Done ✅");
});

test("isi panjang → body ter-truncate (limit 80, akhiran …)", () => {
  const long = "a".repeat(200);
  const r = buildCommentNotificationText("Budi", long);
  assert.equal(r.body.length, 80); // 79 char + '…'
  assert.ok(r.body.endsWith("…"));
});

test("nama brand admin diteruskan apa adanya (brand-safety di call-site)", () => {
  const r = buildCommentNotificationText("Natalo Petshop Official", "halo");
  assert.equal(r.title, "Natalo Petshop Official berkomentar");
});

test("isi kosong/whitespace → body kosong (truncateFeedText trim)", () => {
  assert.equal(buildCommentNotificationText("Andi", "   ").body, "");
});
