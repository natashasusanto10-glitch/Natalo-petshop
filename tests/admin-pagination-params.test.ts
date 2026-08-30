import { test } from "node:test";
import assert from "node:assert/strict";

import { parseLimitParam, parsePageParam } from "../lib/admin/pagination";

test("teks omong kosong jatuh ke halaman 1, BUKAN NaN", () => {
  // Regresi langsung: `Math.max(1, parseInt("abc", 10))` menghasilkan NaN,
  // yang membuat Prisma melempar dan halaman admin balas 500.
  assert.equal(parsePageParam("abc"), 1);
  assert.equal(parsePageParam(""), 1);
  assert.equal(parsePageParam("   "), 1);
  assert.equal(parsePageParam(undefined), 1);
  assert.equal(parsePageParam("NaN"), 1);
});

test("nol dan negatif jatuh ke 1 — skip negatif ditolak Prisma", () => {
  assert.equal(parsePageParam("0"), 1);
  assert.equal(parsePageParam("-7"), 1);
});

test("angka wajar dibaca apa adanya", () => {
  assert.equal(parsePageParam("1"), 1);
  assert.equal(parsePageParam("42"), 42);
});

test("angka raksasa tidak lolos jadi skip di luar bilangan aman", () => {
  const page = parsePageParam("9".repeat(30));
  assert.ok(Number.isSafeInteger(page), "halaman harus tetap bilangan bulat aman");
});

test("query string duplikat (?page=2&page=9) memakai yang pertama, tidak melempar", () => {
  assert.equal(parsePageParam(["2", "9"]), 2);
  assert.equal(parsePageParam([]), 1);
});

test("angka berimbuhan dibaca sebagai angkanya, sesuai perilaku lama", () => {
  // parseInt("12abc") = 12. Dipertahankan supaya tautan lama tidak berubah arti.
  assert.equal(parsePageParam("12abc"), 12);
});

test("limit: nilai tak masuk akal pakai default, nilai besar dijepit", () => {
  assert.equal(parseLimitParam(undefined, 24, 100), 24);
  assert.equal(parseLimitParam("abc", 24, 100), 24);
  assert.equal(parseLimitParam("0", 24, 100), 24);
  assert.equal(parseLimitParam("50", 24, 100), 50);
  assert.equal(parseLimitParam("5000", 24, 100), 100);
});
