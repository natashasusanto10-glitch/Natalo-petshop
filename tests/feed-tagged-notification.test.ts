import test from "node:test";
import assert from "node:assert/strict";
import {
  buildTaggedNotificationTitle,
  derivePrefCategoryForTest,
} from "../lib/feed/notification-center";

test("teks notif tagged sesuai spec", () => {
  assert.equal(
    buildTaggedNotificationTitle("asiong"),
    "asiong menandai Anda dalam postingan",
  );
});

test("feed_tagged ter-gate preferensi kategori feed", () => {
  assert.equal(derivePrefCategoryForTest("feed_tagged"), "feed");
});
