/**
 * Helper murni pencocokan produk↔spesies untuk kolom Belanja profil pet
 * (spec docs/superpowers/specs/2026-07-26-pets-belanja-rotation-design.md).
 *
 * Kenapa allowlist eksplisit, bukan `categoryName.includes(petType)`:
 * pencocokan substring membuat setiap kategori baru otomatis ikut tanpa
 * keputusan manusia, dan kategori tanpa nama spesies ("Peralatan Aquarium",
 * "Grooming Tools") lolos sebagai "netral" lalu tampil untuk hewan yang
 * salah. Katalog cuma punya ~20 kategori dan 5 spesies, jadi peta eksplisit
 * murah dan bisa diuji. `targetSpecies` tetap menang kalau admin mengisinya
 * (per 2026-07-26 baru 2 dari 1307 produk).
 */

/** Nilai `Pet.type` yang dipakai app. */
export const PET_SPECIES: readonly string[] = [
  "Kucing",
  "Anjing",
  "Hamster",
  "Kelinci",
  "Ikan",
];

/**
 * Nama kategori (EXACT match) yang relevan per spesies. Hamster & Kelinci
 * berbagi kategori "Hewan Kecil" karena begitulah katalog menamainya.
 */
export const SPECIES_CATEGORIES: Readonly<Record<string, readonly string[]>> = {
  Kucing: ["Makanan Kucing", "Snack Kucing", "Pasir Kucing"],
  Anjing: ["Makanan Anjing", "Snack Anjing"],
  Hamster: ["Makanan Hewan Kecil", "Perlengkapan Hewan Kecil"],
  Kelinci: ["Makanan Hewan Kecil", "Perlengkapan Hewan Kecil"],
  Ikan: ["Makanan Ikan", "Obat Ikan"],
};

export type ShoppingCandidate = {
  id: string;
  targetSpecies: string[];
  categoryName: string | null;
};

/** Kategori yang boleh muncul untuk `petType`; `[]` kalau spesies tak dikenal. */
export function allowedCategoriesFor(petType: string): readonly string[] {
  return SPECIES_CATEGORIES[petType] ?? [];
}

/** Lolos via `targetSpecies` (menang mutlak) atau via allowlist kategori. */
export function speciesAllows(
  c: ShoppingCandidate,
  petType: string,
): boolean {
  if (c.targetSpecies.length > 0) return c.targetSpecies.includes(petType);
  const name = c.categoryName;
  if (name === null) return false;
  return allowedCategoriesFor(petType).includes(name);
}

/**
 * Grup untuk penjalinan: produk ber-`targetSpecies` masuk grup "target"
 * (sinyal terkuat, dapat giliran pertama), sisanya per nama kategori.
 */
export function candidateGroup(
  c: ShoppingCandidate,
  petType: string,
): string {
  if (c.targetSpecies.length > 0 && c.targetSpecies.includes(petType)) {
    return "target";
  }
  return c.categoryName ?? "";
}
