/**
 * Tests untuk `formatVoucherBrandName` -- pure function yang format nama
 * brand voucher jadi label display ("Khusus {brand}" / "{brand} & N brand
 * lain"). `loadBrandNamesByIds` tidak di-test di sini karena cuma thin
 * Prisma wrapper (pola sama dengan buildVoucherListItems vs
 * listUserVouchers di lib/voucher-list.ts).
 */
import assert from "node:assert/strict";
import test from "node:test";
import { formatVoucherBrandName } from "@/lib/voucher-eligibility";

test("formatVoucherBrandName: eligibleBrandIds kosong -> null", () => {
  const result = formatVoucherBrandName([], new Map());
  assert.equal(result, null);
});

test("formatVoucherBrandName: 1 brand -> nama brand apa adanya", () => {
  const brandNamesById = new Map([["brand-1", "Wolly+"]]);
  const result = formatVoucherBrandName(["brand-1"], brandNamesById);
  assert.equal(result, "Wolly+");
});

test("formatVoucherBrandName: 2 brand -> '{pertama} & 1 brand lain'", () => {
  const brandNamesById = new Map([
    ["brand-1", "Wolly+"],
    ["brand-2", "Happy Dog"],
  ]);
  const result = formatVoucherBrandName(["brand-1", "brand-2"], brandNamesById);
  assert.equal(result, "Wolly+ & 1 brand lain");
});

test("formatVoucherBrandName: 3 brand -> '{pertama} & 2 brand lain'", () => {
  const brandNamesById = new Map([
    ["brand-1", "Wolly+"],
    ["brand-2", "Happy Dog"],
    ["brand-3", "Royal Canin"],
  ]);
  const result = formatVoucherBrandName(
    ["brand-1", "brand-2", "brand-3"],
    brandNamesById,
  );
  assert.equal(result, "Wolly+ & 2 brand lain");
});

test("formatVoucherBrandName: brandId tidak ketemu di map -> di-skip, bukan crash", () => {
  const brandNamesById = new Map([["brand-1", "Wolly+"]]);
  // brand-2 dihapus/tidak aktif tapi masih nyantol di eligibleBrandIds lama.
  const result = formatVoucherBrandName(["brand-1", "brand-2"], brandNamesById);
  assert.equal(result, "Wolly+");
});

import {
  voucherHasScope,
  cartMatchesVoucherScope,
} from "@/lib/voucher-eligibility";

function scope(overrides: Partial<{
  eligibleProductIds: string[];
  eligibleCategoryIds: string[];
  eligibleBrandIds: string[];
}> = {}) {
  return {
    eligibleProductIds: [],
    eligibleCategoryIds: [],
    eligibleBrandIds: [],
    ...overrides,
  };
}

test("voucherHasScope: semua eligible*Ids kosong -> false", () => {
  assert.equal(voucherHasScope(scope()), false);
});

test("voucherHasScope: eligibleBrandIds terisi -> true", () => {
  assert.equal(voucherHasScope(scope({ eligibleBrandIds: ["brand-hpi"] })), true);
});

test("cartMatchesVoucherScope: voucher tanpa scope -> true (berlaku semua produk)", () => {
  assert.equal(
    cartMatchesVoucherScope(scope(), [{ id: "p1", brandId: "b1" }]),
    true,
  );
});

test("cartMatchesVoucherScope: brand-scoped, keranjang tanpa brand cocok -> false", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleBrandIds: ["brand-hpi"] }), [
      { id: "p1", brandId: "brand-lain" },
    ]),
    false,
  );
});

test("cartMatchesVoucherScope: brand-scoped, ada produk brand cocok -> true", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleBrandIds: ["brand-hpi"] }), [
      { id: "p1", brandId: "brand-lain" },
      { id: "p2", brandId: "brand-hpi" },
    ]),
    true,
  );
});

test("cartMatchesVoucherScope: kategori-scoped cocok via categorySlug -> true", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleCategoryIds: ["kucing"] }), [
      { id: "p1", categoryId: null, categorySlug: "kucing" },
    ]),
    true,
  );
});

test("cartMatchesVoucherScope: keranjang kosong + voucher scoped -> false", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleBrandIds: ["brand-hpi"] }), []),
    false,
  );
});
