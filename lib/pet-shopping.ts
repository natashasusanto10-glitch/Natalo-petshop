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

/**
 * Offset WIB dalam menit. Seed rotasi memakai tanggal WIB, BUKAN UTC:
 * server berjalan di UTC, jadi tanggal-UTC akan mengganti isi saran jam
 * 07.00 WIB — di tengah pagi user, yang terbaca sebagai acak.
 */
export const WIB_OFFSET_MINUTES = 420;

/** Kunci tanggal `YYYY-MM-DD` menurut WIB. */
export function wibDateKey(now: Date): string {
  const shifted = new Date(now.getTime() + WIB_OFFSET_MINUTES * 60_000);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  const d = String(shifted.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * FNV-1a 32-bit. Algoritmanya dipatok di spec supaya test dan implementasi
 * tidak bisa bergeser diam-diam; nilainya tidak pernah dipersistensi jadi
 * tidak ada isu kompatibilitas lintas versi.
 */
export function fnv1a32(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    // Math.imul menjaga perkalian tetap di 32-bit (FNV prime 16777619).
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

/** Seed deterministik per (pet, hari WIB). */
export function dailySeed(petId: string, now: Date): number {
  return fnv1a32(`${petId}:${wibDateKey(now)}`);
}

/** Rotasi kiri `offset` posisi dengan wrap-around; input tidak dimutasi. */
export function rotateFrom<T>(items: T[], offset: number): T[] {
  if (items.length === 0) return [];
  const start = ((offset % items.length) + items.length) % items.length;
  return [...items.slice(start), ...items.slice(0, start)];
}

/**
 * Jalin beberapa grup secara round-robin sampai `limit`. Grup yang habis
 * dilewati, jadi grup besar otomatis mengisi sisa slot di akhir. Efeknya:
 * selama masih ada grup lain yang punya stok item, tidak akan pernah ada
 * dua slot berurutan dari grup yang sama — inilah yang membuat grid tidak
 * terbaca "monoton" walau 91% katalog Anjing adalah makanan.
 */
export function interleaveGroups<T>(groups: T[][], limit: number): T[] {
  const out: T[] = [];
  const cursors = groups.map(() => 0);
  let progressed = true;
  while (out.length < limit && progressed) {
    progressed = false;
    for (let g = 0; g < groups.length; g++) {
      if (out.length >= limit) break;
      const cursor = cursors[g];
      if (cursor >= groups[g].length) continue;
      out.push(groups[g][cursor]);
      cursors[g] = cursor + 1;
      progressed = true;
    }
  }
  return out;
}

/**
 * Pilih id produk saran untuk satu pet pada satu hari WIB.
 *
 * Sifat yang dijamin (dan diuji): deterministik dalam satu hari WIB — jadi
 * rail di profil (limit 6) SELALU merupakan prefix dari grid halaman penuh
 * (limit 12), tanpa perlu state atau caching apa pun.
 *
 * PENTING: `candidates` harus SUDAH difilter stok & exclusion oleh pemanggil.
 * Kalau stok difilter setelah fungsi ini, slot akan bocor (12 diminta, <12
 * tampil) — lihat komentar di route.
 */
export function selectSuggestionIds(
  candidates: ShoppingCandidate[],
  opts: { petType: string; petId: string; now: Date; limit: number },
): string[] {
  const { petType, petId, now, limit } = opts;

  const byGroup = new Map<string, ShoppingCandidate[]>();
  for (const c of candidates) {
    if (!speciesAllows(c, petType)) continue;
    const group = candidateGroup(c, petType);
    const bucket = byGroup.get(group);
    if (bucket) bucket.push(c);
    else byGroup.set(group, [c]);
  }

  // "target" dulu (sinyal terkuat), sisanya grup besar dulu; nama sebagai
  // tie-break supaya urutan tak bergantung urutan iterasi Map.
  const ordered = [...byGroup.entries()].sort((a, b) => {
    if (a[0] === "target") return -1;
    if (b[0] === "target") return 1;
    return b[1].length - a[1].length || a[0].localeCompare(b[0]);
  });

  const seed = dailySeed(petId, now);
  const rotated = ordered.map(([, items]) => rotateFrom(items, seed));
  return interleaveGroups(rotated, limit).map((c) => c.id);
}
