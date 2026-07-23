import test from "node:test";
import assert from "node:assert/strict";
import { buildMyTagWhere, parseHiddenBody } from "../lib/feed/tagged-users";

test("parseHiddenBody: hanya boolean yang valid", () => {
  assert.deepEqual(parseHiddenBody({ hidden: true }), { ok: true, hidden: true });
  assert.deepEqual(parseHiddenBody({ hidden: false }), { ok: true, hidden: false });
  assert.equal(parseHiddenBody({ hidden: "true" }).ok, false);
  assert.equal(parseHiddenBody({}).ok, false);
  assert.equal(parseHiddenBody(null).ok, false);
});

test("buildMyTagWhere: mengunci taggedUserId ke session user, bukan postId", () => {
  assert.deepEqual(buildMyTagWhere("post1", "userA"), {
    feedPostId: "post1",
    taggedUserId: "userA",
  });

  // Properti caller-owns-row: taggedUserId adalah SELALU arg kedua
  // (session user), tidak pernah terpengaruh oleh postId/arg pertama.
  // Kalau helper diubah untuk membaca taggedUserId dari postId, assert
  // di bawah ini akan gagal.
  const whereA = buildMyTagWhere("post1", "userA");
  const whereB = buildMyTagWhere("post2", "userA");
  assert.equal(whereA.taggedUserId, whereB.taggedUserId);
  assert.notEqual(whereA.feedPostId, whereB.feedPostId);
});
