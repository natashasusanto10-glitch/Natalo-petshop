import assert from "node:assert/strict";
import test from "node:test";
import {
  DEFAULT_NOTIFICATION_PREFS,
  normalizeNotificationPrefs,
} from "@/lib/notification-preferences";

test("normalize fills defaults for missing keys", () => {
  const result = normalizeNotificationPrefs({ feed: true });
  assert.equal(result.feed, true); // explicit value kept
  assert.equal(result.product, DEFAULT_NOTIFICATION_PREFS.product); // false default
  assert.equal(result.order, DEFAULT_NOTIFICATION_PREFS.order); // true default
  assert.equal(result.master, true);
});

test("normalize ignores non-bool and unknown keys", () => {
  const result = normalizeNotificationPrefs({
    feed: "yes",
    bogus: true,
    master: false,
  });
  // "yes" is not a bool → falls back to default (feed=false)
  assert.equal(result.feed, DEFAULT_NOTIFICATION_PREFS.feed);
  assert.equal(result.master, false);
  assert.equal("bogus" in result, false);
});

test("normalize handles null/garbage input", () => {
  assert.deepEqual(normalizeNotificationPrefs(null), DEFAULT_NOTIFICATION_PREFS);
  assert.deepEqual(
    normalizeNotificationPrefs("nope"),
    DEFAULT_NOTIFICATION_PREFS,
  );
});
