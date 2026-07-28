import assert from "node:assert/strict";
import test from "node:test";

import { productSearchWhere } from "../lib/search";

type OrBranch = { OR: Array<Record<string, unknown>> };

function clauses(query: string): OrBranch[] {
  const where = productSearchWhere(query) as { AND?: OrBranch[] } | undefined;
  return where?.AND ?? [];
}

test("query kosong tidak memfilter", () => {
  assert.equal(productSearchWhere(""), undefined);
  assert.equal(productSearchWhere("   "), undefined);
});

test("tiap token dicocokkan ke nama, brand, SKU, dan opsi varian", () => {
  const [first] = clauses("whiskas");
  assert.equal(first.OR.length, 4);
  assert.deepEqual(Object.keys(first.OR[0]), ["name"]);
  assert.deepEqual(Object.keys(first.OR[1]), ["brand"]);
  assert.deepEqual(Object.keys(first.OR[2]), ["variants"]);
  assert.deepEqual(Object.keys(first.OR[3]), ["variants"]);
});

test("multi-kata jadi beberapa klausa AND — urutan bebas", () => {
  assert.equal(clauses("makanan kucing adult").length, 3);
  assert.equal(clauses("adult kucing makanan").length, 3);
});

test("REGRESI: query 1 karakter tetap memfilter, bukan menampilkan semua", () => {
  // Dulu tokenizer membuang token < 2 karakter lalu return undefined, yang
  // di call site diterjemahkan jadi "tanpa filter" — admin mengetik "5" dan
  // melihat SELURUH katalog, seolah pencariannya rusak. Sekarang query
  // mentah dipakai sebagai satu token.
  const result = clauses("5");
  assert.equal(result.length, 1);
  assert.deepEqual(result[0].OR[0], {
    name: { contains: "5", mode: "insensitive" },
  });
});

test("REGRESI: query hanya simbol juga tetap memfilter", () => {
  assert.equal(clauses("+").length, 1);
});
