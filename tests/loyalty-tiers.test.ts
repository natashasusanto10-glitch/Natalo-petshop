import assert from "node:assert/strict";
import test from "node:test";
import { LOYALTY_TIERS, loyaltyPointsForDiscount } from "@/lib/loyalty-tiers";

test("loyaltyPointsForDiscount: Rp150.000 -> 200 poin", () => {
  assert.equal(loyaltyPointsForDiscount(150000), 200);
});

test("loyaltyPointsForDiscount: Rp10.000 -> 20 poin", () => {
  assert.equal(loyaltyPointsForDiscount(10000), 20);
});

test("loyaltyPointsForDiscount: nominal non-tier -> null", () => {
  assert.equal(loyaltyPointsForDiscount(12345), null);
});

test("LOYALTY_TIERS: 5 tier dengan discountAmount unik", () => {
  const amounts = LOYALTY_TIERS.map((t) => t.discountAmount);
  assert.equal(amounts.length, 5);
  assert.equal(new Set(amounts).size, 5);
});
