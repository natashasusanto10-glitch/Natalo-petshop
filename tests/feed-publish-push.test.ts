import { test } from "node:test";
import assert from "node:assert/strict";
import { buildFeedPushPayload } from "../lib/feed/publish-push-payload";

test("buildFeedPushPayload: title dipotong 60 char", () => {
  const longTitle = "A".repeat(80);
  const result = buildFeedPushPayload("post1", longTitle, "deskripsi singkat");
  assert.equal(result.title.length, 60);
  assert.equal(result.title, "A".repeat(60));
});

test("buildFeedPushPayload: body dipotong 120 char", () => {
  const longDescription = "B".repeat(200);
  const result = buildFeedPushPayload("post1", "Judul", longDescription);
  assert.equal(result.body.length, 120);
  assert.equal(result.body, "B".repeat(120));
});

test("buildFeedPushPayload: description null → fallback body", () => {
  const result = buildFeedPushPayload("post1", "Judul", null);
  assert.equal(result.body, "Ada konten baru di Natalo 🎥");
});

test("buildFeedPushPayload: description kosong/whitespace → fallback body", () => {
  const result = buildFeedPushPayload("post1", "Judul", "   ");
  assert.equal(result.body, "Ada konten baru di Natalo 🎥");
});

test("buildFeedPushPayload: url dan tag mengikuti postId", () => {
  const result = buildFeedPushPayload("abc123", "Judul", "deskripsi");
  assert.equal(result.url, "/feed/abc123");
  assert.equal(result.tag, "feed-publish-abc123");
});

test("buildFeedPushPayload: title dan body pendek tidak dipotong", () => {
  const result = buildFeedPushPayload("post1", "Judul pendek", "Deskripsi pendek");
  assert.equal(result.title, "Judul pendek");
  assert.equal(result.body, "Deskripsi pendek");
});

// Regresi bug prod: judul diawali emoji, slice(0,60) per code-unit membelah
// surrogate pair tepat di batas → lone surrogate → Prisma tolak INSERT
// ("unexpected end of hex escape") → announcement + push mati senyap.
function hasLoneSurrogate(s: string): boolean {
  // Iterasi per code unit; surrogate tinggi (D800-DBFF) harus diikuti
  // surrogate rendah (DC00-DFFF), dan surrogate rendah tak boleh berdiri
  // sendiri.
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const next = s.charCodeAt(i + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return true;
      i++;
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return true;
    }
  }
  return false;
}

test("buildFeedPushPayload: emoji di batas potong TIDAK terbelah (title)", () => {
  // 59 huruf + emoji (2 code unit) → batas 60 jatuh di TENGAH emoji.
  const title = "A".repeat(59) + "🐱" + "ekstra";
  const result = buildFeedPushPayload("post1", title, "deskripsi");
  assert.equal(hasLoneSurrogate(result.title), false);
  // Emoji ikut utuh (potong per code point: 59 huruf + 🐱 = 60 code point).
  assert.equal(result.title, "A".repeat(59) + "🐱");
});

test("buildFeedPushPayload: emoji di batas potong TIDAK terbelah (body)", () => {
  const body = "B".repeat(119) + "🐾" + "ekstra";
  const result = buildFeedPushPayload("post1", "Judul", body);
  assert.equal(hasLoneSurrogate(result.body), false);
  assert.equal(result.body, "B".repeat(119) + "🐾");
});

test("buildFeedPushPayload: judul penuh emoji dipotong utuh per code point", () => {
  const title = "🐱".repeat(70); // 140 code unit, 70 code point
  const result = buildFeedPushPayload("post1", title, "x");
  assert.equal(hasLoneSurrogate(result.title), false);
  assert.equal(Array.from(result.title).length, 60);
});
