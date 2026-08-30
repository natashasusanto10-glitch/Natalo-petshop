import { test } from "node:test";
import assert from "node:assert/strict";

import {
  LOYALTY_VOUCHER_WHERE,
  NON_LOYALTY_VOUCHER_WHERE,
  nonLoyaltyCategory,
  tallyVoucherCategories,
} from "../lib/admin/voucher-categories";
import { isLoyaltyClaimVoucher } from "../lib/voucher-kind";

type Row = { kind: string | null; userId: string | null; code: string };

/**
 * Penilai kecil untuk BENTUK klausa yang kita pakai. Gunanya membuktikan bahwa
 * terjemahan SQL-nya mengungkapkan aturan yang sama dengan
 * `isLoyaltyClaimVoucher()` — bukan untuk mengetes Prisma.
 */
function matchesLoyaltyWhere(row: Row): boolean {
  return LOYALTY_VOUCHER_WHERE.OR.some((branch) => {
    if ("kind" in branch) return row.kind === branch.kind;
    if ("userId" in branch) return row.userId !== null;
    return row.code.startsWith(branch.code.startsWith);
  });
}

function matchesNonLoyaltyWhere(row: Row): boolean {
  return (
    row.kind !== NON_LOYALTY_VOUCHER_WHERE.kind.not &&
    row.userId === null &&
    !row.code.startsWith(NON_LOYALTY_VOUCHER_WHERE.NOT.code.startsWith)
  );
}

const MATRIX: Row[] = [];
for (const kind of ["PRODUCT_DISCOUNT", "FREE_SHIPPING", "LOYALTY_CLAIM", "MANUAL_PRIVATE", null]) {
  for (const userId of ["user_1", null]) {
    for (const code of ["HEMAT10", "POIN-ABC", "POINTLESS"]) {
      MATRIX.push({ kind, userId, code });
    }
  }
}

test("klausa loyalty SQL sepakat dengan isLoyaltyClaimVoucher untuk semua bentuk voucher", () => {
  for (const row of MATRIX) {
    assert.equal(
      matchesLoyaltyWhere(row),
      isLoyaltyClaimVoucher(row),
      `beda untuk ${JSON.stringify(row)}`,
    );
  }
});

test("klausa non-loyalty adalah kebalikan PERSIS — tidak ada voucher yang terhitung dua kali atau hilang", () => {
  for (const row of MATRIX) {
    assert.equal(
      matchesNonLoyaltyWhere(row),
      !matchesLoyaltyWhere(row),
      `tumpang tindih/bolong untuk ${JSON.stringify(row)}`,
    );
  }
});

test("kode 'POINTLESS' TIDAK dianggap loyalty — awalannya 'POIN-' termasuk tanda hubung", () => {
  const row: Row = { kind: "PRODUCT_DISCOUNT", userId: null, code: "POINTLESS" };
  assert.equal(matchesLoyaltyWhere(row), false);
  assert.equal(isLoyaltyClaimVoucher(row), false);
});

test("urutan cabang kategori sama dengan rantai if/else lama", () => {
  assert.equal(nonLoyaltyCategory("FREE_SHIPPING", "SELLER_MANUAL"), "FREE_SHIPPING");
  assert.equal(nonLoyaltyCategory("MANUAL_PRIVATE", "CUSTOMER"), "MANUAL_PRIVATE");
  assert.equal(nonLoyaltyCategory("PRODUCT_DISCOUNT", "SELLER_MANUAL"), "MANUAL_PRIVATE");
  assert.equal(nonLoyaltyCategory("PRODUCT_DISCOUNT", "CUSTOMER"), "PRODUCT_DISCOUNT");
  assert.equal(nonLoyaltyCategory(null, null), "PRODUCT_DISCOUNT");
});

test("tally menjumlahkan groupBy dan menaruh loyalty apa adanya", () => {
  const counts = tallyVoucherCategories(120, [
    { kind: "PRODUCT_DISCOUNT", sourceType: "CUSTOMER", _count: 4 },
    { kind: "FREE_SHIPPING", sourceType: "CUSTOMER", _count: 3 },
    { kind: "MANUAL_PRIVATE", sourceType: "SELLER_MANUAL", _count: 2 },
    { kind: "PRODUCT_DISCOUNT", sourceType: "SELLER_MANUAL", _count: 1 },
  ]);
  assert.deepEqual(counts, {
    PRODUCT_DISCOUNT: 4,
    FREE_SHIPPING: 3,
    LOYALTY_CLAIM: 120,
    MANUAL_PRIVATE: 3,
  });
});

test("tanpa satu pun voucher non-loyalty, angka lain nol — bukan NaN", () => {
  assert.deepEqual(tallyVoucherCategories(0, []), {
    PRODUCT_DISCOUNT: 0,
    FREE_SHIPPING: 0,
    LOYALTY_CLAIM: 0,
    MANUAL_PRIVATE: 0,
  });
});
