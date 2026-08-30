import { test } from "node:test";
import assert from "node:assert/strict";

import { listCountNotice } from "../lib/admin/list-truncation";

test("daftar kosong tidak memunculkan pesan apa pun (empty state yang bicara)", () => {
  assert.equal(listCountNotice(0, 0, "flag").kind, "empty");
});

test("daftar lengkap cuma menyebut jumlahnya", () => {
  const notice = listCountNotice(12, 12, "flash sale");
  assert.equal(notice.kind, "complete");
  assert.equal(notice.kind === "complete" ? notice.text : "", "12 flash sale");
});

test("daftar terpotong menyebut jumlah tampil, total, DAN yang tersembunyi", () => {
  const notice = listCountNotice(100, 130, "flag");
  assert.equal(notice.kind, "truncated");
  if (notice.kind !== "truncated") return;
  assert.equal(notice.hiddenCount, 30);
  assert.match(notice.text, /Menampilkan 100 dari 130 flag/);
  assert.match(notice.text, /30 lainnya belum tampil/);
});

test("angka ribuan pakai format Indonesia, bukan koma Inggris", () => {
  const notice = listCountNotice(100, 1500, "produk");
  assert.equal(notice.kind, "truncated");
  assert.match(notice.kind === "truncated" ? notice.text : "", /1\.500/);
});

test("total yang tertinggal dari shown tidak melahirkan angka tersembunyi negatif", () => {
  // Bisa terjadi kalau ada baris baru masuk di antara query daftar dan query
  // count. Lebih baik lapor "lengkap" daripada "−3 lainnya belum tampil".
  const notice = listCountNotice(100, 97, "pesanan");
  assert.equal(notice.kind, "complete");
  assert.equal(notice.kind === "complete" ? notice.text : "", "100 pesanan");
});

test("input tidak masuk akal tidak bikin halaman menampilkan NaN", () => {
  assert.equal(listCountNotice(Number.NaN, 50, "voucher").kind, "truncated");
  assert.equal(listCountNotice(-5, -9, "voucher").kind, "empty");
});
