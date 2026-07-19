import { test } from "node:test";
import assert from "node:assert/strict";
import { feedNotificationThumbnail } from "../lib/feed/notification-thumbnail";

test("video: pakai thumbnailUrl", () => {
  assert.equal(
    feedNotificationThumbnail({ thumbnailUrl: "https://cdn/v.jpg", media: [] }),
    "https://cdn/v.jpg",
  );
});

test("foto: thumbnailUrl null → media pertama", () => {
  assert.equal(
    feedNotificationThumbnail({
      thumbnailUrl: null,
      media: [{ url: "https://cdn/a.jpg" }, { url: "https://cdn/b.jpg" }],
    }),
    "https://cdn/a.jpg",
  );
});

test("tanpa thumbnail & tanpa media → null", () => {
  assert.equal(feedNotificationThumbnail({ thumbnailUrl: null, media: [] }), null);
  assert.equal(feedNotificationThumbnail({ thumbnailUrl: null }), null);
});
