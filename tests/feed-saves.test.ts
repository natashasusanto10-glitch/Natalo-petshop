import assert from "node:assert/strict";
import test from "node:test";
import { orderFeedItemsByPostIds } from "../lib/feed/queries";
import type { FeedPostListItem } from "../lib/feed/types";

test("saved feed items retain bookmark order and omit unavailable posts", () => {
  const item = (id: string) => ({ id }) as FeedPostListItem;
  const items = [item("older"), item("newest"), item("middle")];

  const ordered = orderFeedItemsByPostIds(
    ["newest", "removed", "middle", "older"],
    items,
  );

  assert.deepEqual(
    ordered.map((post) => post.id),
    ["newest", "middle", "older"],
  );
});
