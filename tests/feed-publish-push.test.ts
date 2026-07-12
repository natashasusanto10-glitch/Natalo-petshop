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
