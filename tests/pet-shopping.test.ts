import test from "node:test";
import assert from "node:assert/strict";
import {
  rankShoppingCandidates,
  speciesMatchTier,
} from "../lib/pet-shopping";

const c = (
  id: string,
  categoryName: string | null,
  targetSpecies: string[] = [],
) => ({ id, categoryName, targetSpecies });

test("targetSpecies cocok = tier 0 (prioritas tertinggi)", () => {
  assert.equal(speciesMatchTier(c("p1", "Obat & Suplemen", ["Kucing"]), "Kucing"), 0);
});

test("targetSpecies ditandai spesies LAIN = dikecualikan", () => {
  assert.equal(speciesMatchTier(c("p1", "Obat & Suplemen", ["Anjing"]), "Kucing"), -1);
});

test("nama kategori memuat spesies cocok = tier 1", () => {
  assert.equal(speciesMatchTier(c("p1", "Makanan Kucing"), "Kucing"), 1);
  assert.equal(speciesMatchTier(c("p2", "Snack Kucing"), "Kucing"), 1);
});

test("nama kategori memuat spesies LAIN = dikecualikan", () => {
  assert.equal(speciesMatchTier(c("p1", "Makanan Anjing"), "Kucing"), -1);
  assert.equal(speciesMatchTier(c("p2", "Obat Ikan"), "Kucing"), -1);
});

test("kategori netral = tier 2", () => {
  assert.equal(speciesMatchTier(c("p1", "Grooming Tools"), "Kucing"), 2);
  assert.equal(speciesMatchTier(c("p2", "Obat & Suplemen"), "Kucing"), 2);
  assert.equal(speciesMatchTier(c("p3", null), "Kucing"), 2);
});

test("pencocokan kategori tidak peduli besar-kecil huruf", () => {
  assert.equal(speciesMatchTier(c("p1", "MAKANAN KUCING"), "Kucing"), 1);
  assert.equal(speciesMatchTier(c("p2", "makanan anjing"), "Kucing"), -1);
});

test("rank: buang yang dikecualikan, urut tier, stabil dalam tier", () => {
  const out = rankShoppingCandidates(
    [
      c("neutral1", "Grooming Tools"),
      c("dog", "Makanan Anjing"),
      c("catCat", "Makanan Kucing"),
      c("neutral2", "Obat & Suplemen"),
      c("tagged", "Obat & Suplemen", ["Kucing"]),
    ],
    "Kucing",
  );
  assert.deepEqual(out.map((o) => o.id), [
    "tagged",
    "catCat",
    "neutral1",
    "neutral2",
  ]);
});
