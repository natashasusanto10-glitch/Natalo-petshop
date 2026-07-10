import { test } from "node:test";
import assert from "node:assert/strict";
import { findProductVideoOrphans } from "../lib/product/product-video-gc";

test("findProductVideoOrphans: hanya yang tidak direferensikan", () => {
  const referenced = new Set(["a", "c"]);
  const items = [
    { guid: "a", storageSize: 10 },
    { guid: "b", storageSize: 20 },
    { guid: "c", storageSize: 30 },
    { guid: "d", storageSize: 40 },
  ];
  assert.deepEqual(findProductVideoOrphans(referenced, items), [
    { guid: "b", storageSize: 20 },
    { guid: "d", storageSize: 40 },
  ]);
});

test("findProductVideoOrphans: semua direferensikan → kosong", () => {
  const referenced = new Set(["a", "b"]);
  const items = [
    { guid: "a", storageSize: 1 },
    { guid: "b", storageSize: 2 },
  ];
  assert.deepEqual(findProductVideoOrphans(referenced, items), []);
});
