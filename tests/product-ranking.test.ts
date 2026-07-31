import test from "node:test";
import assert from "node:assert/strict";
import {
  productRankWhere,
  discountOnlyWhere,
  computeTrendingRanking,
  withAnd,
  toAndArray,
  wibDateKey,
  type TrendingRow,
} from "../lib/product-ranking";

function order(id: string, createdAt: string, userId: string | null = null) {
  return {
    id,
    userId,
    customerEmail: null,
    customerPhone: null,
    createdAt: new Date(createdAt),
  };
}

test("toAndArray normalizes undefined / single / array", () => {
  assert.deepEqual(toAndArray(undefined), []);
  assert.deepEqual(toAndArray({ isActive: true }), [{ isActive: true }]);
  assert.deepEqual(toAndArray([{ isActive: true }]), [{ isActive: true }]);
});

test("withAnd appends without dropping existing AND", () => {
  const result = withAnd({ isActive: true, AND: [{ stock: { gt: 0 } }] }, { price: { gt: 0 } });
  assert.equal(result.isActive, true);
  assert.deepEqual(result.AND, [{ stock: { gt: 0 } }, { price: { gt: 0 } }]);
});

test("productRankWhere requires sellable price+stock for both variant shapes", () => {
  const result = productRankWhere({ isActive: true });
  const and = toAndArray(result.AND);
  assert.equal(and.length, 1);
  const or = (and[0] as { OR: unknown[] }).OR;
  assert.equal(or.length, 2);
  assert.deepEqual(or[0], { hasVariants: false, price: { gt: 0 }, stock: { gt: 0 } });
});

test("discountOnlyWhere matches active flash sale OR active promo toko", () => {
  const now = new Date("2026-07-19T00:00:00.000Z");
  const where = discountOnlyWhere(now);
  const or = (where as { OR: Array<Record<string, unknown>> }).OR;
  assert.equal(or.length, 2);
  // Flash sale branch: discountPrice set AND flashSaleEndsAt in the future
  assert.deepEqual(or[0], {
    AND: [{ discountPrice: { not: null } }, { flashSaleEndsAt: { gt: now } }],
  });
  // Promo Toko branch: an active discount item whose window contains `now`
  const promo = or[1] as { discountItems: { some: Record<string, unknown> } };
  assert.equal(promo.discountItems.some.isItemActive, true);
  assert.deepEqual(promo.discountItems.some.discount, {
    isActive: true,
    startsAt: { lte: now },
    endsAt: { gt: now },
  });
});

test("wibDateKey shifts UTC into WIB before taking the date", () => {
  // 2026-07-19T18:00Z is 2026-07-20 01:00 WIB → next day
  assert.equal(wibDateKey(new Date("2026-07-19T18:00:00.000Z")), "2026-07-20");
  assert.equal(wibDateKey(new Date("2026-07-19T02:00:00.000Z")), "2026-07-19");
});

test("computeTrendingRanking drops products bought on fewer than 2 distinct days", () => {
  const rows: TrendingRow[] = [
    // p1: 2 distinct WIB days, 2 buyers → qualifies
    { productId: "p1", quantity: 3, order: order("o1", "2026-07-10T03:00:00.000Z", "u1") },
    { productId: "p1", quantity: 2, order: order("o2", "2026-07-11T03:00:00.000Z", "u2") },
    // p2: high volume but a single day → filtered out
    { productId: "p2", quantity: 50, order: order("o3", "2026-07-10T03:00:00.000Z", "u3") },
  ];
  assert.deepEqual(computeTrendingRanking(rows), ["p1"]);
});

test("computeTrendingRanking ranks by score: sold*0.5 + buyers*0.3 + days*0.2", () => {
  const rows: TrendingRow[] = [
    // low: 2 sold, 2 buyers, 2 days → 1.0 + 0.6 + 0.4 = 2.0
    { productId: "low", quantity: 1, order: order("o1", "2026-07-10T03:00:00.000Z", "u1") },
    { productId: "low", quantity: 1, order: order("o2", "2026-07-11T03:00:00.000Z", "u2") },
    // high: 10 sold, 2 buyers, 2 days → 5.0 + 0.6 + 0.4 = 6.0
    { productId: "high", quantity: 5, order: order("o3", "2026-07-10T03:00:00.000Z", "u4") },
    { productId: "high", quantity: 5, order: order("o4", "2026-07-11T03:00:00.000Z", "u5") },
  ];
  assert.deepEqual(computeTrendingRanking(rows), ["high", "low"]);
});

test("computeTrendingRanking counts guest orders by email/phone, not as one buyer", () => {
  const rows: TrendingRow[] = [
    {
      productId: "p1",
      quantity: 1,
      order: { id: "o1", userId: null, customerEmail: "a@x.com", customerPhone: null, createdAt: new Date("2026-07-10T03:00:00.000Z") },
    },
    {
      productId: "p1",
      quantity: 1,
      order: { id: "o2", userId: null, customerEmail: "b@x.com", customerPhone: null, createdAt: new Date("2026-07-11T03:00:00.000Z") },
    },
  ];
  assert.deepEqual(computeTrendingRanking(rows), ["p1"]);
});

test("computeTrendingRanking applies skip/take after ranking", () => {
  const rows: TrendingRow[] = [];
  for (const [id, qty] of [["a", 30], ["b", 20], ["c", 10]] as const) {
    rows.push({ productId: id, quantity: qty, order: order(`${id}1`, "2026-07-10T03:00:00.000Z", `${id}u1`) });
    rows.push({ productId: id, quantity: qty, order: order(`${id}2`, "2026-07-11T03:00:00.000Z", `${id}u2`) });
  }
  assert.deepEqual(computeTrendingRanking(rows), ["a", "b", "c"]);
  assert.deepEqual(computeTrendingRanking(rows, { take: 2 }), ["a", "b"]);
  assert.deepEqual(computeTrendingRanking(rows, { skip: 1, take: 1 }), ["b"]);
});
