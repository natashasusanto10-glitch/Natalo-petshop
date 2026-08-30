import { test } from "node:test";
import assert from "node:assert/strict";

import {
  importedProductIsActive,
  LOW_STOCK_LIMIT,
  parseStockFilter,
  parseStockTab,
  productStockWhere,
  stockTone,
  variantStockWhere,
} from "../lib/admin/stock-filters";

test("filter habis pakai lte 0, bukan equals 0 — stok negatif tetap tertangkap", () => {
  assert.deepEqual(productStockWhere("habis").stock, { lte: 0 });
});

test("filter menipis tidak ikut menyerap yang sudah habis", () => {
  assert.deepEqual(productStockWhere("menipis").stock, {
    gt: 0,
    lte: LOW_STOCK_LIMIT,
  });
});

test("filter semua tidak menyebut stok sama sekali", () => {
  // Dashboard memakai `{ ...productStockWhere("semua"), stock: {...} }`.
  // Kalau "semua" ikut membawa kunci stock, spread itu diam-diam saling timpa.
  assert.equal("stock" in productStockWhere("semua"), false);
  assert.equal("stock" in variantStockWhere("semua"), false);
});

test("filter produk TIDAK mengecualikan produk bervarian", () => {
  // `Product.stock` adalah agregat terpelihara (jumlah stok varian aktif),
  // jadi mengecualikan produk bervarian justru menyembunyikan mereka dari
  // daftar stok tanpa alasan.
  for (const filter of ["semua", "menipis", "habis"] as const) {
    assert.equal("hasVariants" in productStockWhere(filter), false);
  }
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

test("impor: produk bervarian dinilai lewat variannya kalau variannya ikut dikirim", () => {
  // Importer satu-satunya jalur tulis yang TIDAK menghitung ulang agregat stok
  // induk, jadi payload dengan stok induk 0 akan menonaktifkan produk.
  assert.equal(
    importedProductIsActive({
      hasVariants: true,
      stock: 0,
      variants: [{ stock: 0 }, { stock: 12 }],
    }),
    true,
  );
  assert.equal(
    importedProductIsActive({ hasVariants: true, stock: 0, variants: [{ stock: 0 }] }),
    false,
  );
});

test("impor: tanpa varian dalam payload, penilaian kembali ke stok induk seperti dulu", () => {
  // Penting: `hasVariants: true` dengan array varian KOSONG itu sah — importer
  // punya cabang `prod.variants.length > 0`. Menilainya lewat varian akan
  // menonaktifkan produk yang sebelumnya aktif; itu regresi, bukan perbaikan.
  assert.equal(
    importedProductIsActive({ hasVariants: true, stock: 7, variants: [] }),
    true,
  );
  assert.equal(
    importedProductIsActive({ hasVariants: false, stock: 3, variants: [] }),
    true,
  );
  assert.equal(
    importedProductIsActive({ hasVariants: false, stock: 0, variants: [] }),
    false,
  );
});
