import { test } from "node:test";
import assert from "node:assert/strict";

import {
  customerSearchWhere,
  orderSearchWhere,
  reviewSearchWhere,
  voucherSearchWhere,
} from "../lib/admin-search";

test("query kosong tidak memfilter apa pun", () => {
  assert.equal(orderSearchWhere(""), undefined);
  assert.equal(orderSearchWhere("   "), undefined);
  assert.equal(customerSearchWhere(""), undefined);
});

test("pesanan dicari lewat nomor, nama, DAN nomor HP sekaligus", () => {
  const where = orderSearchWhere("budi");
  assert.ok(where);
  const fields = where.AND[0].OR.map((branch) => Object.keys(branch)[0]);
  assert.deepEqual(fields, ["orderNumber", "customerName", "customerPhone"]);
});

test("nomor HP dicari case-sensitive — angka tak punya huruf, ILIKE cuma buang index", () => {
  const where = orderSearchWhere("0812");
  assert.ok(where);
  const phoneBranch = where.AND[0].OR[2] as { customerPhone: { mode?: string } };
  assert.equal(phoneBranch.customerPhone.mode, undefined);
});

test("dua kata jadi dua klausa AND — urutan bebas ('santoso budi' ketemu 'Budi Santoso')", () => {
  const where = orderSearchWhere("santoso budi");
  assert.ok(where);
  assert.equal(where.AND.length, 2);
});

test("nomor pesanan bertanda hubung tetap ketemu lewat potongannya", () => {
  // "INV-20260728-001" dipecah tokenizer jadi inv/20260728/001; ketiganya
  // wajib muncul, jadi mengetik "inv 001" pun masih menyempitkan.
  const where = orderSearchWhere("INV-20260728-001");
  assert.ok(where);
  assert.equal(where.AND.length, 3);
});

test("query satu karakter tidak berubah jadi 'tampilkan semua'", () => {
  // Tokenizer membuang token < 2 huruf. Tanpa fallback ke query mentah,
  // hasilnya undefined → tidak memfilter → admin melihat SELURUH daftar dan
  // mengira kotak carinya rusak.
  const where = orderSearchWhere("5");
  assert.ok(where);
  assert.equal(where.AND.length, 1);
});

test("customer dicari lewat nama, email, HP, dan username", () => {
  const where = customerSearchWhere("nata");
  assert.ok(where);
  const fields = where.AND[0].OR.map((branch) => Object.keys(branch)[0]);
  assert.deepEqual(fields, ["name", "email", "phone", "username"]);
});

test("ulasan ikut mencari lewat nama produk yang diulas", () => {
  const where = reviewSearchWhere("royal canin");
  assert.ok(where);
  const productBranch = where.AND[0].OR.at(-1) as { product?: unknown };
  assert.ok(productBranch.product, "cabang relasi produk hilang");
});

test("voucher dicari lewat kode dan nama", () => {
  const where = voucherSearchWhere("HEMAT10");
  assert.ok(where);
  const fields = where.AND[0].OR.map((branch) => Object.keys(branch)[0]);
  assert.deepEqual(fields, ["code", "name"]);
});

test("hasil selalu berbentuk AND-of-OR, bukan OR telanjang", () => {
  // Kalau ini pernah berubah jadi OR di level atas, pencarian akan MENIMPA
  // filter status: tab "Kedaluwarsa" ikut menampilkan voucher aktif.
  for (const build of [orderSearchWhere, customerSearchWhere, voucherSearchWhere]) {
    const where = build("apa saja");
    assert.ok(where);
    assert.deepEqual(Object.keys(where), ["AND"]);
    for (const clause of where.AND) assert.deepEqual(Object.keys(clause), ["OR"]);
  }
});
