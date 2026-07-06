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
