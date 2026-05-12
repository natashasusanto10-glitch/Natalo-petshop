import assert from "node:assert/strict";
import test from "node:test";
import { isTokenVersionFresh } from "@/lib/auth";

test("session token version accepts current customer and admin tokens", () => {
  assert.equal(isTokenVersionFresh({ tv: 2 }, 2), true);
  assert.equal(isTokenVersionFresh({ tv: 3 }, 2), true);
});

test("session token version rejects revoked or older tokens", () => {
  assert.equal(isTokenVersionFresh({ tv: 1 }, 2), false);
  assert.equal(isTokenVersionFresh({}, 1), false);
});
