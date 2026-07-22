import assert from "node:assert/strict";
import test from "node:test";
import {
  buildShareVersion,
  stripEphemeralUrlQuery,
} from "../lib/share/share-version";

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
