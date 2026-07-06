import assert from "node:assert/strict";
import test from "node:test";
import {
  buildMatchingVoucherPreviews,
  dedupeVouchersById,
  type PublicProductVoucherRow,
} from "@/lib/product-vouchers";

function makeRow(overrides: Partial<PublicProductVoucherRow> = {}): PublicProductVoucherRow {
  return {
    id: "v-general",
    name: null,
    code: "GEN",
    description: null,
    discountPercent: null,
    discountAmount: 20000,
    maxDiscountAmount: null,
    minimumOrder: 200000,
    maxUsage: null,
    usedCount: 0,
    expiresAt: null,
    discountScope: "PRODUCT",
    targetUser: "ALL_MEMBERS",
    newMemberMaxAccountAgeDays: null,
    newMemberRequireNoSuccessfulOrder: false,
    usageLimitPeriod: "LIFETIME",
    usageLimitPerUser: null,
    eligibleUserIds: [],
    eligibleProductIds: [],
    eligibleCategoryIds: [],
    eligibleBrandIds: [],
    ...overrides,
  };
}

const product = {
  id: "p1",
  price: 542000,
  categoryId: null,
  categorySlug: null,
  brandId: "brand-happydog",
};

test("buildMatchingVoucherPreviews: voucher umum + brand sama-sama muncul", () => {
  const general = makeRow({ id: "v-general", discountAmount: 20000, eligibleBrandIds: [] });
  const brand = makeRow({
    id: "v-brand",
    discountAmount: null,
    discountPercent: 10,
    maxDiscountAmount: 50000,
    minimumOrder: 300000,
    eligibleBrandIds: ["brand-happydog"],
  });
  const previews = buildMatchingVoucherPreviews([general, brand], product);
  const ids = previews.map((p) => p.id);
  assert.equal(previews.length, 2);
  assert.ok(ids.includes("v-general"));
  assert.ok(ids.includes("v-brand"));
});

test("buildMatchingVoucherPreviews: voucher brand lain tidak muncul", () => {
  const otherBrand = makeRow({ id: "v-other", eligibleBrandIds: ["brand-lain"] });
  const previews = buildMatchingVoucherPreviews([otherBrand], product);
  assert.equal(previews.length, 0);
});

test("buildMatchingVoucherPreviews: preview brand ditandai isBrandExclusive", () => {
  const brand = makeRow({ id: "v-brand", eligibleBrandIds: ["brand-happydog"] });
  const [preview] = buildMatchingVoucherPreviews([brand], product);
  assert.equal(preview.isBrandExclusive, true);
});

test("dedupeVouchersById: buang id duplikat lintas-list, jaga urutan + instance pertama", () => {
  const a = { id: "a" };
  const b = { id: "b" };
  const b2 = { id: "b" };
  const c = { id: "c" };
  const out = dedupeVouchersById([[a, b], [b2, c]]);
  assert.deepEqual(out.map((v) => v.id), ["a", "b", "c"]);
  assert.equal(out[1], b);
});
