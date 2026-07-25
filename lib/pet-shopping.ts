/**
 * Helper murni pencocokan produk↔spesies untuk kolom Belanja profil pet
 * (spec docs/superpowers/specs/2026-07-25-pets-belanja-design.md).
 *
 * Kenapa nama kategori jadi sumber utama: `targetSpecies` cuma terisi di 2
 * dari 1304 produk aktif, sedangkan nama kategori sudah mengandung spesies
 * ("Makanan Kucing", "Obat Ikan"). Jadi fallback inilah yang menopang fitur
 * hari ini; `targetSpecies` tetap menang kalau admin sudah mengisinya.
 */

/** Nilai `Pet.type` yang dipakai app. */
export const PET_SPECIES: readonly string[] = [
  "Kucing",
  "Anjing",
  "Ikan",
  "Burung",
  "Reptil",
];

export type ShoppingCandidate = {
  id: string;
  targetSpecies: string[];
  categoryName: string | null;
};

function mentions(haystack: string, species: string): boolean {
  return haystack.toLowerCase().includes(species.toLowerCase());
}

/**
 * Tingkat kecocokan: 0 = targetSpecies cocok, 1 = kategori ber-spesies cocok,
 * 2 = kategori netral, -1 = dikecualikan (ditandai/berkategori spesies LAIN).
 */
export function speciesMatchTier(
  c: ShoppingCandidate,
  petType: string,
): number {
  if (c.targetSpecies.length > 0) {
    return c.targetSpecies.includes(petType) ? 0 : -1;
  }
  const name = c.categoryName ?? "";
  if (name === "") return 2;
  if (mentions(name, petType)) return 1;
  for (const other of PET_SPECIES) {
    if (other !== petType && mentions(name, other)) return -1;
  }
  return 2;
}

/** Buang kandidat tak relevan, urut menurut tier, stabil di dalam tier. */
export function rankShoppingCandidates<T extends ShoppingCandidate>(
  items: T[],
  petType: string,
): T[] {
  return items
    .map((item, index) => ({ item, index, tier: speciesMatchTier(item, petType) }))
    .filter((e) => e.tier >= 0)
    .sort((a, b) => (a.tier - b.tier) || (a.index - b.index))
    .map((e) => e.item);
}
