import test from "node:test";
import assert from "node:assert/strict";
import {
  PET_SPECIES,
  SPECIES_CATEGORIES,
  allowedCategoriesFor,
  candidateGroup,
  speciesAllows,
} from "../lib/pet-shopping";

const c = (
  id: string,
  categoryName: string | null,
  targetSpecies: string[] = [],
) => ({ id, categoryName, targetSpecies });

test("PET_SPECIES hanya 5 spesies yang benar-benar dipakai", () => {
  assert.deepEqual(
    [...PET_SPECIES],
    ["Kucing", "Anjing", "Hamster", "Kelinci", "Ikan"],
  );
  assert.equal(PET_SPECIES.includes("Burung"), false);
  assert.equal(PET_SPECIES.includes("Reptil"), false);
});

test("allowlist kategori per spesies sesuai katalog produksi", () => {
  assert.deepEqual([...allowedCategoriesFor("Anjing")], [
    "Makanan Anjing",
    "Snack Anjing",
  ]);
  assert.deepEqual([...allowedCategoriesFor("Kucing")], [
    "Makanan Kucing",
    "Snack Kucing",
    "Pasir Kucing",
  ]);
  assert.deepEqual([...allowedCategoriesFor("Ikan")], [
    "Makanan Ikan",
    "Obat Ikan",
  ]);
});

test("Hamster & Kelinci dipetakan ke kategori Hewan Kecil", () => {
  const expected = ["Makanan Hewan Kecil", "Perlengkapan Hewan Kecil"];
  assert.deepEqual([...allowedCategoriesFor("Hamster")], expected);
  assert.deepEqual([...allowedCategoriesFor("Kelinci")], expected);
});

test("spesies tak dikenal (data lama 'Burung') = tanpa kategori apa pun", () => {
  assert.deepEqual([...allowedCategoriesFor("Burung")], []);
  assert.equal(speciesAllows(c("p1", "Makanan Anjing"), "Burung"), false);
});

test("kategori di allowlist = boleh", () => {
  assert.equal(speciesAllows(c("p1", "Makanan Anjing"), "Anjing"), true);
  assert.equal(speciesAllows(c("p2", "Snack Anjing"), "Anjing"), true);
});

test("kategori di luar allowlist = ditolak (netral pun ditolak)", () => {
  assert.equal(speciesAllows(c("p1", "Grooming Tools"), "Anjing"), false);
  assert.equal(speciesAllows(c("p2", "Peralatan Aquarium"), "Anjing"), false);
  assert.equal(speciesAllows(c("p3", "Obat & Suplemen"), "Anjing"), false);
  assert.equal(speciesAllows(c("p4", null), "Anjing"), false);
});

test("kategori spesies LAIN ditolak tanpa perlu blacklist", () => {
  assert.equal(speciesAllows(c("p1", "Makanan Kucing"), "Anjing"), false);
  assert.equal(speciesAllows(c("p2", "Makanan Reptil"), "Anjing"), false);
});

test("targetSpecies cocok menang mutlak walau kategori di luar allowlist", () => {
  assert.equal(
    speciesAllows(c("p1", "Obat & Suplemen", ["Anjing"]), "Anjing"),
    true,
  );
});

test("targetSpecies terisi tapi spesies lain = ditolak walau kategori cocok", () => {
  assert.equal(
    speciesAllows(c("p1", "Makanan Anjing", ["Kucing"]), "Anjing"),
    false,
  );
});

test("pencocokan kategori peka nama persis, bukan substring", () => {
  // "Makanan Anjing Premium" BUKAN kategori yang ada di katalog; exact match
  // mencegah kategori baru bocor tanpa keputusan manusia.
  assert.equal(
    speciesAllows(c("p1", "Makanan Anjing Premium"), "Anjing"),
    false,
  );
});

test("candidateGroup: lolos via targetSpecies → 'target', lewat kategori → nama kategori", () => {
  assert.equal(
    candidateGroup(c("p1", "Obat & Suplemen", ["Anjing"]), "Anjing"),
    "target",
  );
  assert.equal(
    candidateGroup(c("p2", "Snack Anjing"), "Anjing"),
    "Snack Anjing",
  );
});

test("SPECIES_CATEGORIES punya entri untuk setiap PET_SPECIES", () => {
  for (const s of PET_SPECIES) {
    assert.ok(
      SPECIES_CATEGORIES[s] && SPECIES_CATEGORIES[s].length > 0,
      `spesies ${s} wajib punya kategori`,
    );
  }
});
