import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveInitialPostStatus } from "../lib/feed/post-moderation";

test("customer PHOTO_CAROUSEL auto-approve → ACTIVE + publishedAt di-set", () => {
  const result = resolveInitialPostStatus({
    isAdmin: false,
    kind: "PHOTO_CAROUSEL",
  });
  assert.equal(result.status, "ACTIVE");
  assert.ok(result.publishedAt instanceof Date);
});

test("customer video (COMMUNITY) tetap PENDING_REVIEW + publishedAt null", () => {
  const result = resolveInitialPostStatus({
    isAdmin: false,
    kind: "COMMUNITY",
  });
  assert.equal(result.status, "PENDING_REVIEW");
  assert.equal(result.publishedAt, null);
});

test("admin video → ACTIVE (tak berubah)", () => {
  const result = resolveInitialPostStatus({
    isAdmin: true,
    kind: "VIDEO_ONLY",
  });
  assert.equal(result.status, "ACTIVE");
  assert.ok(result.publishedAt instanceof Date);
});

test("admin PHOTO_CAROUSEL → ACTIVE", () => {
  const result = resolveInitialPostStatus({
    isAdmin: true,
    kind: "PHOTO_CAROUSEL",
  });
  assert.equal(result.status, "ACTIVE");
  assert.ok(result.publishedAt instanceof Date);
});
