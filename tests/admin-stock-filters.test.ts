import { test } from "node:test";
import assert from "node:assert/strict";

import {
  LOW_STOCK_LIMIT,
  parseStockFilter,
  parseStockTab,
  productInStockWhere,
  productOutOfStockWhere,
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

test("daftar produk gabungan menilai stok lewat varian, bukan mengeluarkan produk bervarian", () => {
  // Di /admin/products, mengeluarkan produk bervarian berarti mereka lenyap
  // dari tab "Tersedia" MAUPUN "Habis" — hilang sama sekali dari halaman.
  const inStock = productInStockWhere();
  assert.equal(inStock.OR.length, 2);
  assert.equal(inStock.OR[0].hasVariants, false);
  assert.equal(inStock.OR[1].hasVariants, true);
  assert.ok(inStock.OR[1].variants?.some, "cabang varian harus pakai `some`");
});

test("habis untuk produk bervarian berarti TIDAK ADA satu pun varian berstok", () => {
  const outStock = productOutOfStockWhere();
  assert.ok(outStock.OR[1].variants?.none, "cabang varian harus pakai `none`");
});

test("varian terhapus lunak tidak boleh membuat produk tampak masih ada stok", () => {
  // Tanpa `deletedAt: null`, varian yang sudah dihapus tapi stoknya belum nol
  // akan menahan produk di tab "Tersedia" selamanya.
  assert.equal(productInStockWhere().OR[1].variants?.some?.deletedAt, null);
  assert.equal(productOutOfStockWhere().OR[1].variants?.none?.deletedAt, null);
});

test("stok induk 'habis' pakai lte 0, bukan equals 0 — nilai negatif tetap tertangkap", () => {
  assert.deepEqual(productOutOfStockWhere().OR[0].stock, { lte: 0 });
});
