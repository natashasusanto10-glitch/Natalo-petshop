import test from "node:test";
import assert from "node:assert/strict";
import {
  parseTaggedUsersInput,
  buildTaggedUserRows,
  MAX_TAGGED_USERS_PER_POST,
} from "../lib/feed/tagged-users";

test("buildTaggedUserRows: foto — mediaIndex dipetakan ke mediaId sesuai urutan", () => {
  const parsed = parseTaggedUsersInput(
    [
      { userId: "u1", mediaIndex: 0, x: 0.5, y: 0.5 },
      { userId: "u2", mediaIndex: 1, x: 0.2, y: 0.8 },
    ],
    { mediaCount: 2, isVideo: false },
  );
  assert.ok(parsed.ok);
  const rows = buildTaggedUserRows(parsed.tags, "post1", ["mA", "mB"]);
  assert.deepEqual(rows, [
    { feedPostId: "post1", taggedUserId: "u1", mediaId: "mA", x: 0.5, y: 0.5, hidden: false },
    { feedPostId: "post1", taggedUserId: "u2", mediaId: "mB", x: 0.2, y: 0.8, hidden: false },
  ]);
});

test("buildTaggedUserRows: video — mediaId/x/y null semua", () => {
  const parsed = parseTaggedUsersInput(
    [{ userId: "u1" }, { userId: "u2", mediaIndex: 3, x: 0.4, y: 0.4 }],
    { mediaCount: 0, isVideo: true },
  );
  assert.ok(parsed.ok);
  const rows = buildTaggedUserRows(parsed.tags, "post1", []);
  assert.deepEqual(rows, [
    { feedPostId: "post1", taggedUserId: "u1", mediaId: null, x: null, y: null, hidden: false },
    { feedPostId: "post1", taggedUserId: "u2", mediaId: null, x: null, y: null, hidden: false },
  ]);
});

test("buildTaggedUserRows: preserve hidden flag — existing user keeps hidden=true, new user defaults false", () => {
  const parsed = parseTaggedUsersInput(
    [
      { userId: "u1", mediaIndex: 0, x: 0.5, y: 0.5 }, // survives, was hidden
      { userId: "u3", mediaIndex: 1, x: 0.1, y: 0.1 }, // net-new
    ],
    { mediaCount: 2, isVideo: false },
  );
  assert.ok(parsed.ok);
  // Simulate: u1 previously hidden=true, u2 (removed in this edit) hidden=false —
  // u2 being in the map but absent from the new tag list is irrelevant/no-op.
  const prevHiddenByUserId = new Map([
    ["u1", true],
    ["u2", false],
  ]);
  const rows = buildTaggedUserRows(
    parsed.tags,
    "post1",
    ["mA", "mB"],
    prevHiddenByUserId,
  );
  assert.deepEqual(rows, [
    { feedPostId: "post1", taggedUserId: "u1", mediaId: "mA", x: 0.5, y: 0.5, hidden: true },
    { feedPostId: "post1", taggedUserId: "u3", mediaId: "mB", x: 0.1, y: 0.1, hidden: false },
  ]);
});

test("parseTaggedUsersInput: >20 orang ditolak (jalur edit pakai parser sama)", () => {
  const raw = Array.from({ length: MAX_TAGGED_USERS_PER_POST + 1 }, (_, i) => ({
    userId: `u${i}`,
  }));
  const parsed = parseTaggedUsersInput(raw, { mediaCount: 0, isVideo: true });
  assert.equal(parsed.ok, false);
});

test("parseTaggedUsersInput: foto tanpa koordinat ditolak", () => {
  const parsed = parseTaggedUsersInput([{ userId: "u1" }], {
    mediaCount: 2,
    isVideo: false,
  });
  assert.equal(parsed.ok, false);
});
