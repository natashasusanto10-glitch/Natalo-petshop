import assert from "node:assert/strict";
import test from "node:test";

import {
  normalizeSearchText,
  tokenizeSearchQuery,
  tokenizedSearchWhere,
} from "../lib/search-tokens";

// Helper mungil: bangun cabang OR seperti pemakaian nyata di admin.
const nameOnly = (token: string) => [
  { name: { contains: token, mode: "insensitive" as const } },
];

test("normalizeSearchText melipat huruf besar, aksen, dan tanda baca", () => {
  assert.equal(normalizeSearchText("Royal Canin"), "royal canin");
  assert.equal(normalizeSearchText("CAFÉ"), "cafe");
  assert.equal(normalizeSearchText("Whiskas® Adult 1.2kg"), "whiskas adult 1 2kg");
  assert.equal(normalizeSearchText("   "), "");
});

test("tokenizeSearchQuery membuang token < 2 karakter", () => {
  assert.deepEqual(tokenizeSearchQuery("royal canin"), ["royal", "canin"]);
  assert.deepEqual(tokenizeSearchQuery("a b cd"), ["cd"]);
  assert.deepEqual(tokenizeSearchQuery("5"), []);
  assert.deepEqual(tokenizeSearchQuery(""), []);
});

test("query kosong tidak menghasilkan filter", () => {
  assert.equal(tokenizedSearchWhere("", nameOnly), undefined);
  assert.equal(tokenizedSearchWhere("   ", nameOnly), undefined);
});

test("tiap token jadi satu klausa AND — urutan kata bebas", () => {
  const where = tokenizedSearchWhere("canin royal", nameOnly);
  assert.deepEqual(where, {
    AND: [
      { OR: [{ name: { contains: "canin", mode: "insensitive" } }] },
      { OR: [{ name: { contains: "royal", mode: "insensitive" } }] },
    ],
  });
});

test("token dicocokkan ke SEMUA field yang diberikan", () => {
  const where = tokenizedSearchWhere("budi", (token) => [
    { customerName: { contains: token, mode: "insensitive" as const } },
    { orderNumber: { contains: token, mode: "insensitive" as const } },
  ]);
  assert.equal(where?.AND.length, 1);
  assert.deepEqual(where?.AND[0].OR, [
    { customerName: { contains: "budi", mode: "insensitive" } },
    { orderNumber: { contains: "budi", mode: "insensitive" } },
  ]);
});

test("query satu karakter jatuh ke query mentah, bukan tanpa filter", () => {
  // Regresi: tanpa fallback ini, tokenisasi menghasilkan [] → where
  // undefined → daftar admin tampil UTUH walau admin sedang mencari.
  const where = tokenizedSearchWhere("5", nameOnly);
  assert.deepEqual(where, {
    AND: [{ OR: [{ name: { contains: "5", mode: "insensitive" } }] }],
  });
});

test("query simbol-saja juga jatuh ke query mentah", () => {
  const where = tokenizedSearchWhere("#", nameOnly);
  assert.deepEqual(where, {
    AND: [{ OR: [{ name: { contains: "#", mode: "insensitive" } }] }],
  });
});

test("nomor pesanan bertanda hubung dipecah jadi token yang dapat dicocokkan", () => {
  const where = tokenizedSearchWhere("INV-20260728-001", nameOnly);
  assert.deepEqual(
    where?.AND.map((clause) => clause.OR[0].name.contains),
    ["inv", "20260728", "001"],
  );
});
