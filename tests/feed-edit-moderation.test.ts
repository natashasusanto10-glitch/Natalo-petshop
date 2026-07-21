import assert from "node:assert/strict";
import test from "node:test";
import { editReTriggersModeration } from "../lib/feed/post-moderation";

test("customer edit video (COMMUNITY) ACTIVE kini TIDAK re-trigger moderation", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: false, status: "ACTIVE", kind: "COMMUNITY" }),
    false,
  );
});

test("customer edit photo/carousel ACTIVE does NOT re-trigger moderation", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: false, status: "ACTIVE", kind: "PHOTO_CAROUSEL" }),
    false,
  );
});

test("admin edit never re-triggers moderation", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: true, status: "ACTIVE", kind: "COMMUNITY" }),
    false,
  );
});

test("non-ACTIVE post edit does not reset status", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: false, status: "PENDING_REVIEW", kind: "COMMUNITY" }),
    false,
  );
});
