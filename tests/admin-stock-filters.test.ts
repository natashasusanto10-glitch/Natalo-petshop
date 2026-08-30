import { test } from "node:test";
import assert from "node:assert/strict";

import {
  LOW_STOCK_LIMIT,
  parseStockFilter,
  parseStockTab,
  productStockWhere,
  stockTone,
  variantStockWhere,
} from "../lib/admin/stock-filters";

test("baris berbasis stok induk SELALU membatasi hasVariants:false", () => {
  // Ini penjaga bug utamanya: form admin menulis stok induk = 0 untuk produk
  // bervarian, jadi tanpa batas ini query "habis" menyapu seluruh produk
  // bervarian betapa pun penuh gudangnya.
  for (const filter of ["semua", "menipis", "habis"] as const) {
    assert.equal(productStockWhere(filter).hasVariants, false, `bocor di ${filter}`);
  }
});

test("filter habis berarti tepat nol, bukan 'kurang dari satu'", () => {
  assert.deepEqual(productStockWhere("habis").stock, { equals: 0 });
});

test("filter menipis tidak ikut menyerap yang sudah habis", () => {
  assert.deepEqual(productStockWhere("menipis").stock, {
    gt: 0,
    lte: LOW_STOCK_LIMIT,
  });
});

test("filter semua tidak menyebut stok sama sekali", () => {
  assert.equal("stock" in productStockWhere("semua"), false);
  assert.equal("stock" in variantStockWhere("semua"), false);
});

test("varian terhapus lunak dan varian dari produk nonaktif tidak ikut terhitung", () => {
  const where = variantStockWhere("habis");
  assert.equal(where.deletedAt, null);
  assert.equal(where.isActive, true);
  assert.deepEqual(where.product, { isActive: true });
});

test("parameter URL asing jatuh ke default yang aman, bukan melempar", () => {
  assert.equal(parseStockFilter(undefined), "semua");
  assert.equal(parseStockFilter("'; DROP TABLE"), "semua");
  assert.equal(parseStockFilter("menipis"), "menipis");
  assert.equal(parseStockTab(undefined), "produk");
  assert.equal(parseStockTab("varian"), "varian");
  assert.equal(parseStockTab("apa pun"), "produk");
});

test("label stok: nol habis, batas ambang masih menipis, di atasnya tersedia", () => {
  assert.equal(stockTone(0).label, "Habis");
  assert.equal(stockTone(1).label, "Menipis");
  assert.equal(stockTone(LOW_STOCK_LIMIT).label, "Menipis");
  assert.equal(stockTone(LOW_STOCK_LIMIT + 1).label, "Tersedia");
});

test("stok negatif diperlakukan habis, tidak menyamar jadi tersedia", () => {
  assert.equal(stockTone(-3).label, "Habis");
});
