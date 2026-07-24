import test from "node:test";
import assert from "node:assert/strict";
import {
  AGG_PUSH_THROTTLE_MS,
  buildFollowAggTitle,
  followAggTag,
  shouldRePush,
} from "../lib/social/follow-aggregation";

test("judul agregat: nama terbaru + N-1 lainnya", () => {
  assert.equal(
    buildFollowAggTitle("sinta", 3),
    "sinta dan 2 lainnya mulai mengikuti kamu",
  );
  assert.equal(
    buildFollowAggTitle("budi", 2),
    "budi dan 1 lainnya mulai mengikuti kamu",
  );
});

test("tag agregat stabil per target", () => {
  assert.equal(followAggTag("u1"), "follow-agg-u1");
});

test("throttle: null → push; <5m → skip; tepat 5m & >5m → push", () => {
  const now = new Date("2026-07-24T10:10:00Z");
  assert.equal(shouldRePush(null, now), true);
  assert.equal(
    shouldRePush(new Date(now.getTime() - AGG_PUSH_THROTTLE_MS + 1), now),
    false,
  );
  assert.equal(
    shouldRePush(new Date(now.getTime() - AGG_PUSH_THROTTLE_MS), now),
    true,
  );
  assert.equal(
    shouldRePush(new Date(now.getTime() - AGG_PUSH_THROTTLE_MS - 1), now),
    true,
  );
});
