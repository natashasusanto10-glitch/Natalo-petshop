import test from "node:test";
import assert from "node:assert/strict";
import { computeDiscountPercent } from "../components/ProductCard";

test("normal markdown rounds up, min 1", () => {
  assert.equal(computeDiscountPercent(100000, 90000), 10);
  assert.equal(computeDiscountPercent(100000, 99900), 1); // <1% floors to 1
});

test("no markdown or zero price yields 0", () => {
  assert.equal(computeDiscountPercent(100000, 100000), 0);
  assert.equal(computeDiscountPercent(0, 0), 0);
});
