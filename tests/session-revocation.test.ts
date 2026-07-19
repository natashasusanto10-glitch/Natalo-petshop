import assert from "node:assert/strict";
import test from "node:test";
import { tokenFingerprint, extractBearerToken } from "@/lib/auth";

test("tokenFingerprint is a deterministic sha256 hex, never the raw token", () => {
  const jwt = "header.payload.signature";
  const fp = tokenFingerprint(jwt);
  assert.match(fp, /^[0-9a-f]{64}$/);
  assert.equal(tokenFingerprint(jwt), fp); // deterministic
  assert.notEqual(fp, jwt); // raw JWT never stored
});

test("different tokens produce different fingerprints", () => {
  assert.notEqual(tokenFingerprint("a.b.c"), tokenFingerprint("a.b.d"));
});

test("extractBearerToken parses Bearer scheme case-insensitively", () => {
  assert.equal(extractBearerToken("Bearer abc.def"), "abc.def");
  assert.equal(extractBearerToken("bearer xyz"), "xyz");
  assert.equal(extractBearerToken("Bearer   spaced"), "spaced");
});

test("extractBearerToken returns null for missing / malformed headers", () => {
  assert.equal(extractBearerToken(null), null);
  assert.equal(extractBearerToken(undefined), null);
  assert.equal(extractBearerToken(""), null);
  assert.equal(extractBearerToken("Basic abc"), null);
  assert.equal(extractBearerToken("Bearer"), null);
  assert.equal(extractBearerToken("Bearer "), null);
});
