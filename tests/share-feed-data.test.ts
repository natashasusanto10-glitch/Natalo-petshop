import assert from "node:assert/strict";
import test from "node:test";

import { PUBLIC_SHARE_FEED_POST_WHERE } from "@/lib/share/feed-share-data";

test("public share Feed query always restricts to active, non-deleted posts", () => {
  assert.equal(PUBLIC_SHARE_FEED_POST_WHERE.status, "ACTIVE");
  assert.equal(PUBLIC_SHARE_FEED_POST_WHERE.deletedAt, null);
  assert.equal(PUBLIC_SHARE_FEED_POST_WHERE.encodingStatus, "ready");
});
