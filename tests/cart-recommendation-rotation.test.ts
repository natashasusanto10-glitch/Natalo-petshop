import assert from "node:assert/strict";
import test from "node:test";
import { rotateRecommendationPool } from "../lib/cart-recommendation-rotation";

const pool = Array.from({ length: 30 }, (_, index) => ({
  id: `product-${index}`, brandId: `brand-${index % 5}`,
}));

test("rotation changes the selected products, remains stable per visit and spreads brands", () => {
  const first = rotateRecommendationPool(pool, "visit-one", 6);
  assert.deepEqual(first, rotateRecommendationPool(pool, "visit-one", 6));
  assert.notDeepEqual(new Set(first.map(p => p.id)), new Set(rotateRecommendationPool(pool, "visit-two", 6).map(p => p.id)));
  assert.equal(new Set(first.slice(0, 5).map(p => p.brandId)).size, 5);
  assert.equal(new Set(first.map(p => p.id)).size, 6);
});

test("unseeded callers preserve ordering and small pools terminate without duplicates", () => {
  assert.deepEqual(rotateRecommendationPool(pool, "", 3), pool.slice(0, 3));
  assert.equal(rotateRecommendationPool([pool[0], pool[0]], "visit", 10).length, 1);
  assert.deepEqual(rotateRecommendationPool([], "visit", 10), []);
});
