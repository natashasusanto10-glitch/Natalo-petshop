import assert from "node:assert/strict";
import test from "node:test";
import {
  buildShareVersion,
  stripEphemeralUrlQuery,
} from "../lib/share/share-version";
import type { FeedPostListItem, FeedListResponse } from "../lib/feed/types";

test("shareVersion stabil dan berubah ketika data preview berubah", () => {
  const first = buildShareVersion(["post-1", "caption", "https://cdn/x.jpg"]);
  assert.equal(
    first,
    buildShareVersion(["post-1", "caption", "https://cdn/x.jpg"]),
  );
  assert.notEqual(
    first,
    buildShareVersion(["post-1", "caption baru", "https://cdn/x.jpg"]),
  );
  assert.match(first, /^[a-zA-Z0-9_-]{12,16}$/);
});

test("signed query media tidak membuat versi berubah", () => {
  assert.equal(
    stripEphemeralUrlQuery("https://cdn.example/x.jpg?token=a&expires=1"),
    "https://cdn.example/x.jpg",
  );
});

test("respons Feed yang diserialisasi selalu membawa shareVersion", () => {
  const item = {
    id: "post-1",
    shareVersion: "preview-token-1",
  } satisfies Pick<FeedPostListItem, "id" | "shareVersion">;

  const response: Pick<FeedListResponse, "nextCursor"> & {
    items: Array<Pick<FeedPostListItem, "id" | "shareVersion">>;
  } = {
    items: [item],
    nextCursor: null,
  };

  assert.equal(response.items[0].shareVersion, "preview-token-1");
});
