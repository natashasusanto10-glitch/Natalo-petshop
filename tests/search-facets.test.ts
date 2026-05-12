import assert from "node:assert/strict";
import test from "node:test";
import { buildWeightBuckets, hydrateFacetDistribution } from "@/lib/search-facets";

test("facet distribution hydrates display names from DB labels and drops stale slugs", () => {
  const result = hydrateFacetDistribution(
    {
      "cat-food": 12,
      "dog-food": 8,
      "stale-category": 4,
    },
    new Map([
      ["cat-food", "Cat Food"],
      ["dog-food", "Dog Food"],
    ]),
  );

  assert.deepEqual(result, [
    { slug: "cat-food", name: "Cat Food", count: 12 },
    { slug: "dog-food", name: "Dog Food", count: 8 },
  ]);
});

test("weight buckets aggregate Meilisearch weight_grams distribution", () => {
  const buckets = buildWeightBuckets({
    "500": 3,
    "1000": 2,
    "2500": 4,
    "6000": 1,
  });

  assert.deepEqual(buckets, [
    { label: "< 1 KG", min: 0, max: 999, count: 3 },
    { label: "1 - 5 KG", min: 1000, max: 5000, count: 6 },
    { label: "> 5 KG", min: 5001, max: 999999, count: 1 },
  ]);
});
