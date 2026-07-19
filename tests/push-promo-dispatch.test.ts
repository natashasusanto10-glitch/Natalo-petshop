import { test } from "node:test";
import assert from "node:assert/strict";
import { claimSucceeded } from "../lib/push-promo";

test("claimSucceeded: count 1 → true (baris berhasil diklaim)", () => {
  assert.equal(claimSucceeded(1), true);
});

test("claimSucceeded: count 0 → false (sudah diklaim proses lain)", () => {
  assert.equal(claimSucceeded(0), false);
});
