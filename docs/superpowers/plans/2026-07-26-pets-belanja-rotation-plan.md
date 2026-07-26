# Kolom Belanja Pet — Rotasi & Gaya Kartu: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saran Belanja profil pet berhenti monoton (rotasi harian + jalinan kategori, allowlist spesies eksplisit), badge "Saran" dibuang, dan kartu rail/grid mengikuti gaya kartu Beranda/Katalog.

**Architecture:** Seluruh logika seleksi saran jadi fungsi murni di `lib/pet-shopping.ts` (allowlist spesies → kategori, seed harian FNV-1a berbasis tanggal WIB, rotasi offset per grup, jalinan round-robin). Route `GET /api/member/pets/[id]/shopping` berubah jadi dua query: satu query ringan (id + kategori + stok) untuk seluruh kandidat allowlist, lalu satu query penuh untuk 12 id terpilih. Sisi Flutter hanya menyalin token visual kartu Katalog/rail Beranda ke dua widget Belanja — tidak ada ekstraksi widget dan tidak ada perubahan bentuk API.

**Tech Stack:** Next.js App Router, Prisma (Postgres/Neon), `node:test` + `tsx` untuk test backend; Flutter 3 + `flutter_test` untuk mobile.

## Global Constraints

- `PET_SPECIES` = `["Kucing", "Anjing", "Hamster", "Kelinci", "Ikan"]` — Burung & Reptil DIBUANG.
- Allowlist kategori (exact match, bukan `contains`): Kucing → `Makanan Kucing`, `Snack Kucing`, `Pasir Kucing`; Anjing → `Makanan Anjing`, `Snack Anjing`; Ikan → `Makanan Ikan`, `Obat Ikan`; Hamster → `Makanan Hewan Kecil`, `Perlengkapan Hewan Kecil`; Kelinci → `Makanan Hewan Kecil`, `Perlengkapan Hewan Kecil`.
- `targetSpecies` (jika non-empty) menang mutlak atas allowlist kategori; jika terisi tapi tidak memuat spesies pet → produk dikecualikan.
- Kategori netral DIHAPUS TOTAL — tidak ada query fallback netral, tidak ada tier "netral".
- Seed rotasi = FNV-1a 32-bit atas string `` `${petId}:${tanggalWIB}` ``, `tanggalWIB` format `YYYY-MM-DD` pada UTC+7.
- WIB offset = konstanta tunggal `WIB_OFFSET_MINUTES = 420`.
- Setiap fungsi murni yang bergantung waktu WAJIB menerima `now: Date` sebagai parameter (bukan memanggil `new Date()` di dalam).
- `SUGGESTED_LIMIT = 12`; batas kartu rail = `6`.
- Stok TIDAK PERNAH difilter di SQL — `Product.stock = 0` untuk produk varian; pakai `effectiveStock` dari `lib/product-dosage`.
- Filter stok dijalankan SEBELUM rotasi/jalinan, bukan sesudah.
- Exclusion `usedIds` tetap berlaku; offset rotasi dihitung terhadap pool SETELAH exclusion + filter stok.
- Bentuk JSON respons TIDAK berubah: `{ usedCount, used, manual, suggested }`.
- TIDAK menyentuh: `flutter_app/lib/screens/home_screen.dart`, `flutter_app/lib/screens/products_screen.dart`, `flutter_app/lib/widgets/product_card.dart`, `flutter_app/lib/widgets/compact_commerce_product_card.dart` (hanya diimpor untuk `commerceGridSurfaceTint`), dan search Beranda/Produk.
- Token kartu rail: lebar `150`, `Material(color: cs.surface, borderRadius: 8, clipBehavior: Clip.antiAlias)` + `Container(border: Border.all(color: cs.outlineVariant), boxShadow: BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4)))`, foto 1:1 `BoxFit.cover` full-bleed, padding konten `EdgeInsets.fromLTRB(8, 8, 8, 8)`, nama `SizedBox(height: 31)` + `fontSize: 13, height: 1.25, FontWeight.w600, cs.onSurface`, harga `fontSize: 14, FontWeight.w900, cs.onSurface`.
- Token kartu grid: sama, kecuali lebar mengikuti `Expanded`, padding konten `EdgeInsets.fromLTRB(10, 8, 10, 10)`, nama `SizedBox(height: 34)`, harga `fontSize: 16, FontWeight.w900, cs.onSurface`.
- Grid saran memakai layout manual `Column`/`Row`+`Expanded` — DILARANG `GridView.count` + `childAspectRatio` (regresi overflow text-scale, sudah diperbaiki di commit 88e5b381).
- Harga selalu lewat `formatRupiah()`, JANGAN interpolasi angka mentah.
- Warna selalu token `ColorScheme`/`NataloColors` — DILARANG hex atau `Colors.*` literal (kecuali `Colors.transparent` untuk `Material`).
- Bobot font: pakai `NataloWeight.body`/`.strong` untuk teks non-kartu; kartu memakai `FontWeight.w600`/`.w900` verbatim agar identik Katalog/Beranda.
- Teks placeholder profil: `'Segera hadir'` + `'Momen $petName akan muncul di sini.'` — kata "Belanja" dan "Journey" TIDAK BOLEH muncul lagi di kartu ini.
- Semua commit diakhiri `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## File Structure

| File | Tanggung jawab | Task |
|---|---|---|
| `lib/pet-shopping.ts` | Semua fungsi murni: allowlist spesies, `speciesAllows`, seed FNV-1a, `wibDateKey`, `rotateFrom`, `interleaveGroups`, `selectSuggestionIds` | 1, 2, 3 |
| `tests/pet-shopping.test.ts` | Unit test fungsi murni di atas (ditulis ulang total) | 1, 2, 3 |
| `app/api/member/pets/[id]/shopping/route.ts` | Query ringan kandidat → seleksi murni → query penuh 12 id; limit 12 | 4 |
| `tests/pet-shopping-route.test.ts` | Test helper route yang bisa diuji tanpa DB + invariant rail-prefix | 4 |
| `flutter_app/lib/widgets/pet_shopping_rail.dart` | Rail tanpa badge, kartu gaya rail Beranda, skeleton setinggi rail | 5 |
| `flutter_app/lib/screens/pet_shopping_screen.dart` | Grid saran gaya Katalog + kanal abu; CTA di luar kanal | 6 |
| `flutter_app/lib/screens/pet_profile_screen.dart` | Strip abu di belakang rail; teks placeholder "Momen {nama}" | 7 |
| `flutter_app/test/widgets/pet_shopping_rail_test.dart` | Test rail | 5 |
| `flutter_app/test/screens/pet_shopping_screen_test.dart` | Test grid | 6 |
| `flutter_app/test/screens/pet_profile_belanja_test.dart` | Test profil | 7 |

**Perintah yang dipakai berulang:**

- Backend satu file test: `npx tsx --test tests/pet-shopping.test.ts`
- Backend semua test: `npm test`
- Typecheck: `npx tsc --noEmit`
- Flutter satu file: `cd flutter_app && flutter test test/widgets/pet_shopping_rail_test.dart`
- Flutter analyze: `cd flutter_app && flutter analyze`

---

### Task 1: Allowlist spesies → kategori (buang pencocokan fuzzy & netral)

**Files:**
- Modify: `lib/pet-shopping.ts` (ganti seluruh isi file)
- Test: `tests/pet-shopping.test.ts` (ganti seluruh isi file)

**Interfaces:**
- Consumes: —
- Produces:
  - `export const PET_SPECIES: readonly string[]`
  - `export const SPECIES_CATEGORIES: Readonly<Record<string, readonly string[]>>`
  - `export type ShoppingCandidate = { id: string; targetSpecies: string[]; categoryName: string | null }`
  - `export function speciesAllows(c: ShoppingCandidate, petType: string): boolean`
  - `export function candidateGroup(c: ShoppingCandidate, petType: string): string` — `"target"` kalau lolos via `targetSpecies`, kalau tidak nama kategorinya
  - `export function allowedCategoriesFor(petType: string): readonly string[]`

Catatan penting untuk implementer: fungsi lama `speciesMatchTier` dan `rankShoppingCandidates` DIHAPUS. Route yang memakainya akan diperbaiki di Task 4; sampai Task 4 selesai, `npx tsc --noEmit` akan mengeluh soal route itu — itu diharapkan, jangan "diperbaiki" dengan mempertahankan fungsi lama.

- [ ] **Step 1: Tulis test yang gagal**

Ganti seluruh isi `tests/pet-shopping.test.ts` dengan:

```ts
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
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: FAIL — error import/resolusi karena `PET_SPECIES` masih daftar lama dan `speciesAllows`/`candidateGroup`/`allowedCategoriesFor`/`SPECIES_CATEGORIES` belum ada.

- [ ] **Step 3: Tulis implementasi**

Ganti seluruh isi `lib/pet-shopping.ts` dengan:

```ts
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
```

- [ ] **Step 4: Jalankan test, pastikan LULUS**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: PASS — 12 test lulus, 0 gagal.

- [ ] **Step 5: Commit**

```bash
git add lib/pet-shopping.ts tests/pet-shopping.test.ts
git commit -m "$(cat <<'EOF'
feat(pet-shopping): allowlist kategori per spesies, buang fuzzy match & netral

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Seed harian WIB (FNV-1a) + rotasi offset

**Files:**
- Modify: `lib/pet-shopping.ts` (tambah di bawah kode Task 1)
- Test: `tests/pet-shopping.test.ts` (tambah test baru, jangan hapus test Task 1)

**Interfaces:**
- Consumes: file `lib/pet-shopping.ts` dari Task 1 (jangan ubah ekspor yang sudah ada)
- Produces:
  - `export const WIB_OFFSET_MINUTES = 420`
  - `export function wibDateKey(now: Date): string` — `"YYYY-MM-DD"` menurut UTC+7
  - `export function fnv1a32(input: string): number` — unsigned 32-bit
  - `export function dailySeed(petId: string, now: Date): number`
  - `export function rotateFrom<T>(items: T[], offset: number): T[]` — rotasi kiri dengan wrap-around; aman untuk array kosong

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di AKHIR `tests/pet-shopping.test.ts` (dan tambahkan nama-nama baru ke blok `import` di atas file: `WIB_OFFSET_MINUTES`, `dailySeed`, `fnv1a32`, `rotateFrom`, `wibDateKey`):

```ts
test("WIB_OFFSET_MINUTES = 420 (UTC+7)", () => {
  assert.equal(WIB_OFFSET_MINUTES, 420);
});

test("wibDateKey: tengah hari UTC → tanggal WIB yang sama", () => {
  assert.equal(wibDateKey(new Date("2026-07-26T05:00:00Z")), "2026-07-26");
});

test("wibDateKey: 16:59Z masih 26 Juli WIB, 17:01Z sudah 27 Juli WIB", () => {
  // Ini alasan seed TIDAK boleh pakai tanggal UTC: kalau UTC, isi grid
  // berganti jam 07.00 WIB — di tengah pagi user, terasa acak.
  assert.equal(wibDateKey(new Date("2026-07-26T16:59:00Z")), "2026-07-26");
  assert.equal(wibDateKey(new Date("2026-07-26T17:01:00Z")), "2026-07-27");
});

test("wibDateKey: tepat tengah malam WIB masuk hari baru", () => {
  assert.equal(wibDateKey(new Date("2026-07-26T17:00:00Z")), "2026-07-27");
});

test("wibDateKey: bulan & hari selalu 2 digit", () => {
  assert.equal(wibDateKey(new Date("2026-01-05T05:00:00Z")), "2026-01-05");
});

test("fnv1a32: deterministik, unsigned, berbeda untuk input berbeda", () => {
  assert.equal(fnv1a32("abc"), fnv1a32("abc"));
  assert.notEqual(fnv1a32("abc"), fnv1a32("abd"));
  assert.ok(fnv1a32("pet-1:2026-07-26") >= 0);
  assert.ok(Number.isInteger(fnv1a32("pet-1:2026-07-26")));
});

test("dailySeed: sama dalam satu hari WIB, beda antar hari", () => {
  const pagi = new Date("2026-07-26T01:00:00Z"); // 08:00 WIB
  const malam = new Date("2026-07-26T15:00:00Z"); // 22:00 WIB
  const besok = new Date("2026-07-27T01:00:00Z");
  assert.equal(dailySeed("pet-1", pagi), dailySeed("pet-1", malam));
  assert.notEqual(dailySeed("pet-1", pagi), dailySeed("pet-1", besok));
});

test("dailySeed: pet berbeda dapat seed berbeda di hari yang sama", () => {
  const now = new Date("2026-07-26T05:00:00Z");
  assert.notEqual(dailySeed("pet-1", now), dailySeed("pet-2", now));
});

test("rotateFrom: rotasi kiri dengan wrap-around", () => {
  assert.deepEqual(rotateFrom([1, 2, 3, 4, 5], 2), [3, 4, 5, 1, 2]);
  assert.deepEqual(rotateFrom([1, 2, 3], 0), [1, 2, 3]);
});

test("rotateFrom: offset lebih besar dari panjang di-modulo", () => {
  assert.deepEqual(rotateFrom([1, 2, 3], 7), [2, 3, 1]);
});

test("rotateFrom: array kosong tidak melempar (tak ada pembagian nol)", () => {
  assert.deepEqual(rotateFrom([], 5), []);
});

test("rotateFrom: tidak memutasi input", () => {
  const input = [1, 2, 3];
  rotateFrom(input, 1);
  assert.deepEqual(input, [1, 2, 3]);
});
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: FAIL — `wibDateKey`, `fnv1a32`, `dailySeed`, `rotateFrom`, `WIB_OFFSET_MINUTES` belum diekspor.

- [ ] **Step 3: Tulis implementasi**

Tambahkan di AKHIR `lib/pet-shopping.ts`:

```ts
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
```

- [ ] **Step 4: Jalankan test, pastikan LULUS**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: PASS — 24 test lulus (12 dari Task 1 + 12 baru), 0 gagal.

- [ ] **Step 5: Commit**

```bash
git add lib/pet-shopping.ts tests/pet-shopping.test.ts
git commit -m "$(cat <<'EOF'
feat(pet-shopping): seed harian WIB (FNV-1a) + helper rotasi

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Penjalinan kategori + pemilihan saran (fungsi murni utama)

**Files:**
- Modify: `lib/pet-shopping.ts` (tambah di bawah kode Task 2)
- Test: `tests/pet-shopping.test.ts` (tambah test baru)

**Interfaces:**
- Consumes: dari Task 1 `ShoppingCandidate`, `speciesAllows`, `candidateGroup`; dari Task 2 `dailySeed`, `rotateFrom`
- Produces:
  - `export function interleaveGroups<T>(groups: T[][], limit: number): T[]`
  - `export function selectSuggestionIds(candidates: ShoppingCandidate[], opts: { petType: string; petId: string; now: Date; limit: number }): string[]`

Aturan yang harus dipenuhi `selectSuggestionIds`:
1. Buang kandidat yang tidak lolos `speciesAllows`.
2. Kelompokkan sisanya dengan `candidateGroup`, jaga urutan input di dalam grup.
3. Urutkan grup: `"target"` selalu pertama; sisanya menurut ukuran grup DESC, tie-break nama grup ASC (determinisme).
4. Rotasi tiap grup dengan `rotateFrom(grup, dailySeed(petId, now))`.
5. Jalin round-robin (`interleaveGroups`) sampai `limit`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di AKHIR `tests/pet-shopping.test.ts` (tambahkan `interleaveGroups`, `selectSuggestionIds` ke blok `import`):

```ts
test("interleaveGroups: round-robin, tak pernah dua slot berurutan satu grup", () => {
  const out = interleaveGroups([["a1", "a2", "a3"], ["b1", "b2"]], 5);
  assert.deepEqual(out, ["a1", "b1", "a2", "b2", "a3"]);
});

test("interleaveGroups: grup habis dilewati, grup besar mengisi sisa", () => {
  const out = interleaveGroups([["a1", "a2", "a3", "a4"], ["b1"]], 5);
  assert.deepEqual(out, ["a1", "b1", "a2", "a3", "a4"]);
});

test("interleaveGroups: berhenti di limit", () => {
  const out = interleaveGroups([["a1", "a2", "a3"], ["b1", "b2", "b3"]], 3);
  assert.deepEqual(out, ["a1", "b1", "a2"]);
});

test("interleaveGroups: total lebih kecil dari limit → keluarkan semua", () => {
  const out = interleaveGroups([["a1"], ["b1"]], 12);
  assert.deepEqual(out, ["a1", "b1"]);
});

test("interleaveGroups: tanpa grup → kosong", () => {
  assert.deepEqual(interleaveGroups([], 12), []);
});

// ── selectSuggestionIds ──────────────────────────────────────────────

const NOW = new Date("2026-07-26T05:00:00Z");

/** Kandidat sintetis: n produk di satu kategori, id `{prefix}{i}`. */
const many = (prefix: string, categoryName: string, n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `${prefix}${i}`,
    categoryName,
    targetSpecies: [] as string[],
  }));

test("selectSuggestionIds: menjalin kategori, bukan blok satu kategori", () => {
  const out = selectSuggestionIds(
    [...many("m", "Makanan Anjing", 20), ...many("s", "Snack Anjing", 20)],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.equal(out.length, 12);
  // Tak ada dua slot berurutan dari kategori yang sama (m vs s).
  for (let i = 1; i < out.length; i++) {
    assert.notEqual(
      out[i][0],
      out[i - 1][0],
      `slot ${i} dan ${i - 1} dari kategori yang sama: ${out.join(",")}`,
    );
  }
});

test("selectSuggestionIds: kategori kecil tetap kebagian slot", () => {
  // Realita katalog Anjing: 234 makanan vs 21 snack. Tanpa penjalinan,
  // makanan menelan seluruh grid — inilah keluhan 'monoton'.
  const out = selectSuggestionIds(
    [...many("m", "Makanan Anjing", 234), ...many("s", "Snack Anjing", 21)],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.ok(
    out.filter((id) => id.startsWith("s")).length >= 5,
    `snack terlalu sedikit: ${out.join(",")}`,
  );
});

test("selectSuggestionIds: grup 'target' dapat slot pertama", () => {
  const out = selectSuggestionIds(
    [
      ...many("m", "Makanan Anjing", 10),
      { id: "tagged", categoryName: "Obat & Suplemen", targetSpecies: ["Anjing"] },
    ],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.equal(out[0], "tagged");
});

test("selectSuggestionIds: produk spesies lain & netral dibuang", () => {
  const out = selectSuggestionIds(
    [
      { id: "cat", categoryName: "Makanan Kucing", targetSpecies: [] },
      { id: "aqua", categoryName: "Peralatan Aquarium", targetSpecies: [] },
      { id: "groom", categoryName: "Grooming Tools", targetSpecies: [] },
      { id: "dog", categoryName: "Makanan Anjing", targetSpecies: [] },
    ],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.deepEqual(out, ["dog"]);
});

test("selectSuggestionIds: deterministik dalam satu hari WIB", () => {
  const cands = [
    ...many("m", "Makanan Anjing", 50),
    ...many("s", "Snack Anjing", 10),
  ];
  const pagi = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-26T01:00:00Z"),
    limit: 12,
  });
  const malam = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-26T15:00:00Z"),
    limit: 12,
  });
  assert.deepEqual(pagi, malam, "rail & grid dalam sehari WAJIB sama");
});

test("selectSuggestionIds: hari berbeda → isi berputar", () => {
  const cands = [
    ...many("m", "Makanan Anjing", 50),
    ...many("s", "Snack Anjing", 10),
  ];
  const hariIni = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-26T05:00:00Z"),
    limit: 12,
  });
  const besok = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-27T05:00:00Z"),
    limit: 12,
  });
  assert.notDeepEqual(hariIni, besok);
});

test("selectSuggestionIds: 6 pertama = prefix dari 12 (janji rail=prefix grid)", () => {
  const cands = [
    ...many("m", "Makanan Anjing", 50),
    ...many("s", "Snack Anjing", 10),
  ];
  const opts = { petType: "Anjing", petId: "pet-1", now: NOW };
  const dua_belas = selectSuggestionIds(cands, { ...opts, limit: 12 });
  const enam = selectSuggestionIds(cands, { ...opts, limit: 6 });
  assert.deepEqual(enam, dua_belas.slice(0, 6));
});

test("selectSuggestionIds: pool kecil (Hamster 7 produk) tidak dipaksa 12", () => {
  const out = selectSuggestionIds(
    [
      ...many("f", "Makanan Hewan Kecil", 6),
      ...many("p", "Perlengkapan Hewan Kecil", 1),
    ],
    { petType: "Hamster", petId: "pet-9", now: NOW, limit: 12 },
  );
  assert.equal(out.length, 7);
});

test("selectSuggestionIds: kandidat kosong → kosong", () => {
  assert.deepEqual(
    selectSuggestionIds([], {
      petType: "Anjing",
      petId: "pet-1",
      now: NOW,
      limit: 12,
    }),
    [],
  );
});
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: FAIL — `interleaveGroups` dan `selectSuggestionIds` belum ada.

- [ ] **Step 3: Tulis implementasi**

Tambahkan di AKHIR `lib/pet-shopping.ts`:

```ts
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
```

- [ ] **Step 4: Jalankan test, pastikan LULUS**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: PASS — 38 test lulus, 0 gagal.

- [ ] **Step 5: Commit**

```bash
git add lib/pet-shopping.ts tests/pet-shopping.test.ts
git commit -m "$(cat <<'EOF'
feat(pet-shopping): penjalinan kategori + pemilihan saran seeded harian

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Route pakai seleksi baru, limit 12, dua query

**Files:**
- Modify: `app/api/member/pets/[id]/shopping/route.ts`
- Test: `tests/pet-shopping-route.test.ts` (tambah test, jangan hapus yang ada)

**Interfaces:**
- Consumes: `selectSuggestionIds`, `ShoppingCandidate` dari `lib/pet-shopping` (Task 1–3)
- Produces:
  - `export const SUGGESTED_LIMIT = 12`
  - `export type StockRow = { id: string; stock: number; targetSpecies: string[]; category: { name: string } | null; variants: { stock: number }[] }`
  - `export function toStockCandidate(row: StockRow): ShoppingCandidate & { inStock: boolean }`
  - `export function inStockCandidates(rows: StockRow[]): ShoppingCandidate[]`
  - `export function orderRowsByIds(rows: ProductRow[], ids: string[]): ProductRow[]`
  - Yang sudah ada dan TIDAK berubah: `buildUsageMaps`, `toShoppingProduct`, `composeUsed`, `PRODUCT_SELECT`, `ProductRow`, `CareRecordRow`, `UsageEntry`

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di AKHIR `tests/pet-shopping-route.test.ts`, dan tambahkan ke blok `import` di atas file: `SUGGESTED_LIMIT`, `inStockCandidates`, `orderRowsByIds`, `toStockCandidate`:

```ts
test("SUGGESTED_LIMIT = 12 (grid), rail memakai 6 pertama", () => {
  assert.equal(SUGGESTED_LIMIT, 12);
});

test("toStockCandidate: produk varian base stock 0 tetap in-stock", () => {
  const out = toStockCandidate({
    id: "p1",
    stock: 0,
    targetSpecies: [],
    category: { name: "Makanan Anjing" },
    variants: [{ stock: 4 }],
  });
  assert.equal(out.inStock, true, "stok varian WAJIB dijumlahkan");
  assert.equal(out.categoryName, "Makanan Anjing");
  assert.deepEqual(out.targetSpecies, []);
});

test("toStockCandidate: produk tanpa kategori → categoryName null", () => {
  const out = toStockCandidate({
    id: "p2",
    stock: 3,
    targetSpecies: [],
    category: null,
    variants: [],
  });
  assert.equal(out.categoryName, null);
  assert.equal(out.inStock, true);
});

test("inStockCandidates: item habis dibuang SEBELUM seleksi", () => {
  // Kalau filter stok terjadi SESUDAH seleksi, permintaan 12 slot bisa
  // menghasilkan 7 kartu — slot bocor tanpa sebab yang terlihat user.
  const out = inStockCandidates([
    {
      id: "ada",
      stock: 2,
      targetSpecies: [],
      category: { name: "Makanan Anjing" },
      variants: [],
    },
    {
      id: "habis",
      stock: 0,
      targetSpecies: [],
      category: { name: "Makanan Anjing" },
      variants: [],
    },
    {
      id: "varian-habis",
      stock: 0,
      targetSpecies: [],
      category: { name: "Snack Anjing" },
      variants: [{ stock: 0 }],
    },
  ]);
  assert.deepEqual(out.map((c) => c.id), ["ada"]);
});

test("orderRowsByIds: urutan hasil mengikuti urutan id, bukan urutan DB", () => {
  const row = (id: string): ProductRow => ({
    id,
    slug: id,
    name: id,
    imageUrl: null,
    price: 1000,
    stock: 5,
    targetSpecies: [],
    category: { name: "Makanan Anjing" },
    variants: [],
  });
  const out = orderRowsByIds([row("c"), row("a"), row("b")], ["b", "c", "a"]);
  assert.deepEqual(out.map((r) => r.id), ["b", "c", "a"]);
});

test("orderRowsByIds: id tanpa baris (produk hilang) dilewati diam-diam", () => {
  const row = (id: string): ProductRow => ({
    id,
    slug: id,
    name: id,
    imageUrl: null,
    price: 1000,
    stock: 5,
    targetSpecies: [],
    category: null,
    variants: [],
  });
  const out = orderRowsByIds([row("a")], ["a", "hilang"]);
  assert.deepEqual(out.map((r) => r.id), ["a"]);
});
```

Tambahkan juga `ProductRow` ke blok `import type` file test (`import type { ProductRow } from "../app/api/member/pets/[id]/shopping/route";`) jika belum ada.

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `npx tsx --test tests/pet-shopping-route.test.ts`
Expected: FAIL — `SUGGESTED_LIMIT`/`toStockCandidate`/`inStockCandidates`/`orderRowsByIds` belum diekspor, dan route masih mengimpor `rankShoppingCandidates` yang sudah dihapus di Task 1.

- [ ] **Step 3: Tulis implementasi**

Di `app/api/member/pets/[id]/shopping/route.ts`:

**(a)** Ganti blok import dari `lib/pet-shopping` (yang mengimpor `PET_SPECIES`, `rankShoppingCandidates`, `ShoppingCandidate`) menjadi:

```ts
import {
  allowedCategoriesFor,
  selectSuggestionIds,
  type ShoppingCandidate,
} from "@/lib/pet-shopping";
```

**(b)** Ganti dua konstanta `const SUGGESTED_LIMIT = 8;` dan `const POOL_TAKE = 40;` menjadi:

```ts
/** Slot grid halaman penuh; rail profil memakai 6 pertama dari urutan sama. */
export const SUGGESTED_LIMIT = 12;

/**
 * Kolom minimal untuk menghitung stok efektif + grup kategori. Query ringan
 * ini boleh menyapu seluruh kandidat spesies (≤380 baris di katalog per
 * 2026-07-26) karena payload per baris sangat kecil; baris PENUH hanya
 * diambil untuk 12 id yang benar-benar terpilih.
 */
const STOCK_SELECT = {
  id: true,
  stock: true,
  targetSpecies: true,
  category: { select: { name: true } },
  variants: {
    where: { isActive: true, deletedAt: null },
    select: { stock: true },
  },
} as const;
```

**(c)** Tambahkan helper berikut tepat SEBELUM `export async function GET(`:

```ts
export type StockRow = {
  id: string;
  stock: number;
  targetSpecies: string[];
  category: { name: string } | null;
  variants: { stock: number }[];
};

/** Kandidat + status stok efektif (base + semua varian aktif). */
export function toStockCandidate(
  row: StockRow,
): ShoppingCandidate & { inStock: boolean } {
  const variantTotal = row.variants.reduce((sum, v) => sum + v.stock, 0);
  return {
    id: row.id,
    targetSpecies: row.targetSpecies ?? [],
    categoryName: row.category?.name ?? null,
    // GOTCHA: produk varian punya Product.stock = 0 dan stok sebenarnya di
    // ProductVariant, jadi stok TIDAK BOLEH difilter di SQL.
    inStock: row.stock + variantTotal > 0,
  };
}

/**
 * Buang produk habis SEBELUM seleksi. Urutannya penting: kalau filter stok
 * terjadi setelah `selectSuggestionIds`, permintaan 12 slot bisa berakhir
 * jadi 7 kartu karena sebagian tersaring — slot bocor tanpa sebab terlihat.
 */
export function inStockCandidates(rows: StockRow[]): ShoppingCandidate[] {
  return rows
    .map(toStockCandidate)
    .filter((c) => c.inStock)
    .map(({ id, targetSpecies, categoryName }) => ({
      id,
      targetSpecies,
      categoryName,
    }));
}

/** Susun baris penuh mengikuti urutan `ids` (urutan DB tidak dijamin). */
export function orderRowsByIds(
  rows: ProductRow[],
  ids: string[],
): ProductRow[] {
  const byId = new Map(rows.map((r) => [r.id, r]));
  return ids
    .map((id) => byId.get(id))
    .filter((r): r is ProductRow => r !== undefined);
}
```

**(d)** Ganti SELURUH blok kandidat saran — dari komentar `// Kandidat saran: dua query berbatas, ...` sampai baris `.slice(0, SUGGESTED_LIMIT);` (yakni deklarasi `usedIds`, `notUsed`, `speciesMatched`, `pool`, blok `if (pool.length < SUGGESTED_LIMIT)`, `candidates`, dan `suggested`) — dengan:

```ts
  // Kandidat saran: satu query RINGAN untuk seluruh kategori allowlist,
  // seleksi murni (allowlist + rotasi harian + penjalinan) di JS, lalu satu
  // query PENUH untuk 12 id terpilih. Pola ini menggantikan pool
  // "40 produk terbaru" yang lama — pool itu membuat 200+ produk lain tak
  // pernah punya kesempatan tampil, jadi rotasi apa pun tak akan terasa.
  const usedIds = used.map((u) => u.productId);
  const notUsed = usedIds.length ? { id: { notIn: usedIds } } : {};
  const allowedCategories = [...allowedCategoriesFor(pet.type)];

  const stockRows =
    allowedCategories.length === 0
      ? ((await prisma.product.findMany({
          where: {
            isActive: true,
            ...notUsed,
            targetSpecies: { has: pet.type },
          },
          select: STOCK_SELECT,
          orderBy: [{ createdAt: "desc" }, { id: "asc" }],
        })) as unknown as StockRow[])
      : ((await prisma.product.findMany({
          where: {
            isActive: true,
            ...notUsed,
            OR: [
              { targetSpecies: { has: pet.type } },
              { category: { name: { in: allowedCategories } } },
            ],
          },
          select: STOCK_SELECT,
          // Urutan dasar deterministik — id sebagai tie-break supaya rotasi
          // harian tidak bergeser hanya karena dua produk lahir bersamaan.
          orderBy: [{ createdAt: "desc" }, { id: "asc" }],
        })) as unknown as StockRow[]);

  const suggestedIds = selectSuggestionIds(inStockCandidates(stockRows), {
    petType: pet.type,
    petId: pet.id,
    now: new Date(),
    limit: SUGGESTED_LIMIT,
  });

  const suggestedRows = suggestedIds.length
    ? ((await prisma.product.findMany({
        where: { id: { in: suggestedIds } },
        select: PRODUCT_SELECT,
      })) as unknown as ProductRow[])
    : [];

  const suggested = orderRowsByIds(suggestedRows, suggestedIds).map(
    toShoppingProduct,
  );
```

- [ ] **Step 4: Jalankan test & typecheck, pastikan LULUS**

Run: `npx tsx --test tests/pet-shopping-route.test.ts`
Expected: PASS — semua test lama + 6 test baru lulus, 0 gagal.

Run: `npx tsc --noEmit`
Expected: keluar tanpa output (0 error). Tidak boleh ada sisa referensi ke `rankShoppingCandidates`, `speciesMatchTier`, atau `POOL_TAKE`.

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: PASS — 38 test, memastikan Task 1–3 tidak rusak.

- [ ] **Step 5: Commit**

```bash
git add app/api/member/pets/\[id\]/shopping/route.ts tests/pet-shopping-route.test.ts
git commit -m "$(cat <<'EOF'
feat(api): saran Belanja pakai rotasi harian + jalinan kategori, limit 12

Buang pool '40 produk terbaru' yang membuat 200+ produk tak pernah tampil.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Rail Flutter — buang badge "Saran", kartu gaya rail Beranda

**Files:**
- Modify: `flutter_app/lib/widgets/pet_shopping_rail.dart` (ganti seluruh isi file)
- Test: `flutter_app/test/widgets/pet_shopping_rail_test.dart` (ganti seluruh isi file)

**Interfaces:**
- Consumes: `PetShoppingProduct` dari `models/pet_shopping.dart` (tidak berubah)
- Produces:
  - `const double kPetShoppingRailHeight` (nilai baru `234`)
  - `const int kPetShoppingRailMaxCards = 6`
  - `class PetShoppingRail` — konstruktor TIDAK berubah: `{required List<PetShoppingProduct> used, required List<PetShoppingProduct> suggested, required void Function(PetShoppingProduct) onTapProduct}`
  - `class PetShoppingRailSkeleton` — konstruktor tanpa argumen (tidak berubah)

- [ ] **Step 1: Tulis test yang gagal**

Ganti seluruh isi `flutter_app/test/widgets/pet_shopping_rail_test.dart` dengan:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/widgets/app_product_image.dart';
import 'package:natalo_petshop_flutter/widgets/pet_shopping_rail.dart';

/// GOTCHA REPO: `imageUrl` WAJIB null di widget test. `AppProductImage`
/// dengan URL http merender `Shimmer` yang beranimasi tanpa henti, sehingga
/// `pumpAndSettle` menggantung selamanya. Assertion `fit`/ukuran tetap sah
/// karena keduanya properti widget, bukan hasil unduhan.
PetShoppingProduct p(String name, {int price = 45000, String? slug}) =>
    PetShoppingProduct(
      productId: name,
      slug: slug ?? name.toLowerCase(),
      name: name,
      imageUrl: null,
      effectivePrice: price,
      inStock: true,
      hasVariants: false,
    );

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('badge "Saran" TIDAK pernah dirender', (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (_) {},
    )));
    expect(find.text('Saran'), findsNothing);
  });

  testWidgets('label semantik kartu = nama produk saja, tanpa "saran produk"',
      (tester) async {
    // Finder berbasis semantics WAJIB didahului ensureSemantics (konvensi
    // repo: lihat test/widgets/order_tracking_timeline_test.dart).
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (_) {},
    )));
    expect(
      find.bySemanticsLabel(RegExp('saran produk')),
      findsNothing,
      reason: 'klaim per-produk dibuang (spec Keputusan 1)',
    );
    expect(find.bySemanticsLabel('Kaniva Dog'), findsOneWidget);
  });

  testWidgets('rail menampilkan maksimal 6 kartu', (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [for (var i = 0; i < 20; i++) p('Produk $i')],
      onTapProduct: (_) {},
    )));
    expect(kPetShoppingRailMaxCards, 6);
    // Rail horizontal me-lazy-build; hitung dari itemCount ListView.
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.semanticChildCount, 6);
  });

  testWidgets('used tampil dulu, saran mengisi sisa sampai 6', (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: [p('Terpakai A'), p('Terpakai B')],
      suggested: [for (var i = 0; i < 20; i++) p('Saran $i')],
      onTapProduct: (_) {},
    )));
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.semanticChildCount, 6);
    expect(find.text('Terpakai A'), findsOneWidget);
    expect(find.text('Terpakai B'), findsOneWidget);
  });

  testWidgets('kartu: foto 1:1 cover, nama 13/w600, harga 14/w900 diformat',
      (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog', price: 335000)],
      onTapProduct: (_) {},
    )));

    final img = tester.widget<AppProductImage>(find.byType(AppProductImage));
    expect(img.fit, BoxFit.cover);

    final nama = tester.widget<Text>(find.text('Kaniva Dog'));
    expect(nama.style!.fontSize, 13);
    expect(nama.style!.fontWeight, FontWeight.w600);

    expect(find.text('Rp335.000'), findsOneWidget);
    final harga = tester.widget<Text>(find.text('Rp335.000'));
    expect(harga.style!.fontSize, 14);
    expect(harga.style!.fontWeight, FontWeight.w900);
  });

  testWidgets('kartu lebar 150 (identik rail Terlaris Beranda)',
      (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (_) {},
    )));
    final size = tester.getSize(find.byType(AppProductImage));
    // Foto full-bleed → lebarnya = lebar kartu.
    expect(size.width, 150);
    expect(size.height, 150, reason: 'foto WAJIB 1:1');
  });

  testWidgets('tap kartu memanggil onTapProduct dengan produk yang benar',
      (tester) async {
    PetShoppingProduct? tapped;
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (x) => tapped = x,
    )));
    await tester.tap(find.text('Kaniva Dog'));
    await tester.pump();
    expect(tapped?.name, 'Kaniva Dog');
  });

  testWidgets('skeleton tinggi IDENTIK rail terisi (anti layout-jump)',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox(
      width: 400,
      child: PetShoppingRailSkeleton(),
    )));
    final skeleton = tester.getSize(find.byType(PetShoppingRailSkeleton));
    expect(skeleton.height, kPetShoppingRailHeight);
  });

  testWidgets('rail terisi setinggi kPetShoppingRailHeight', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      child: PetShoppingRail(
        used: const [],
        suggested: [p('Kaniva Dog')],
        onTapProduct: (_) {},
      ),
    )));
    final rail = tester.getSize(find.byType(PetShoppingRail));
    expect(rail.height, kPetShoppingRailHeight);
  });

  testWidgets('kartu tidak overflow pada text scale 1.3', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: PetShoppingRail(
                used: const [],
                suggested: [
                  p('Nama Produk Yang Panjang Sekali Untuk Menguji Dua Baris'),
                ],
                onTapProduct: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/widgets/pet_shopping_rail_test.dart`
Expected: FAIL — `kPetShoppingRailMaxCards` belum ada (compile error), dan badge "Saran" masih dirender.

- [ ] **Step 3: Tulis implementasi**

Ganti seluruh isi `flutter_app/lib/widgets/pet_shopping_rail.dart` dengan:

```dart
import 'package:flutter/material.dart';

import '../models/pet_shopping.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';

/// Lebar kartu — identik rail "Terlaris" Beranda (`_MiniProductCard`).
const double _kCardWidth = 150;

/// Maksimal kartu di rail profil (spec Keputusan 4). Saran yang tampil di
/// sini adalah 6 PERTAMA dari urutan `suggested` yang sama dengan grid
/// halaman penuh — server sudah menjamin urutan itu stabil sehari.
const int kPetShoppingRailMaxCards = 6;

/// Tinggi TETAP rail — dipakai rail terisi maupun skeleton supaya konten di
/// bawahnya tidak melonjak saat data tiba.
///
/// Rinciannya: foto 1:1 (150) + padding atas konten (8) + tinggi nama
/// dipaku (31) + jarak (8) + baris harga (≈19) + padding bawah (8) +
/// cadangan border/shadow (10) = 234. Kalau anatomi kartu berubah, angka
/// ini WAJIB dihitung ulang bersamaan — kalau tidak, skeleton→data akan
/// terlihat melonjak.
const double kPetShoppingRailHeight = 234;

/// Tinggi nama dipaku 2 baris supaya baris harga antar-kartu sejajar —
/// sama dengan kartu Beranda mode `compact`.
const double _kNameHeight = 31;

/// Rail horizontal kolom Belanja di profil pet. Kartu TANPA tombol dan TANPA
/// badge — satu gesture per kartu → detail produk.
class PetShoppingRail extends StatelessWidget {
  final List<PetShoppingProduct> used;
  final List<PetShoppingProduct> suggested;
  final void Function(PetShoppingProduct product) onTapProduct;

  const PetShoppingRail({
    super.key,
    required this.used,
    required this.suggested,
    required this.onTapProduct,
  });

  @override
  Widget build(BuildContext context) {
    // Fakta lebih dulu, saran mengisi sisa slot.
    final items = <PetShoppingProduct>[
      ...used.take(kPetShoppingRailMaxCards),
      if (used.length < kPetShoppingRailMaxCards)
        ...suggested.take(kPetShoppingRailMaxCards - used.length),
    ];
    return SizedBox(
      height: kPetShoppingRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _RailCard(
          product: items[i],
          onTap: () => onTapProduct(items[i]),
        ),
      ),
    );
  }
}

/// Kartu rail — token disamakan dengan kartu Beranda/Katalog: kartu putih
/// radius 8 + border tipis + shadow halus, foto 1:1 full-bleed `cover`.
/// TANPA badge diskon/hemat/rating: DTO Belanja tidak membawa datanya, dan
/// menampilkan klaim yang tidak didukung data adalah justru yang dihindari.
class _RailCard extends StatelessWidget {
  final PetShoppingProduct product;
  final VoidCallback onTap;

  const _RailCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: product.name,
      child: SizedBox(
        width: _kCardWidth,
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppProductImage(
                    imageUrl: product.imageUrl,
                    width: _kCardWidth,
                    height: _kCardWidth,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _kNameHeight,
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatRupiah(product.effectivePrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder selagi fetch — anatomi & tinggi identik dengan [PetShoppingRail].
class PetShoppingRailSkeleton extends StatelessWidget {
  const PetShoppingRailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return SizedBox(
      height: kPetShoppingRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, __) => SizedBox(
          width: _kCardWidth,
          child: Material(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: _kCardWidth,
                    height: _kCardWidth,
                    color: cs.surfaceContainerHighest,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _kNameHeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(_kCardWidth - 16, 9),
                              const SizedBox(height: 5),
                              bar((_kCardWidth - 16) * 0.6, 9),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        bar((_kCardWidth - 16) * 0.5, 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Jalankan test & analyze, pastikan LULUS**

Run: `cd flutter_app && flutter test test/widgets/pet_shopping_rail_test.dart`
Expected: PASS — 10 test lulus.

Run: `cd flutter_app && flutter analyze`
Expected: "No issues found!" (atau tanpa isu baru pada file yang disentuh; import `natalo_colors.dart`/`natalo_text.dart` yang tak lagi terpakai HARUS sudah dihapus dari file rail).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/pet_shopping_rail.dart flutter_app/test/widgets/pet_shopping_rail_test.dart
git commit -m "$(cat <<'EOF'
feat(app): rail Belanja tanpa badge Saran, kartu gaya rail Beranda (6 kartu)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Grid halaman Belanja — gaya kartu Katalog + kanal abu

**Files:**
- Modify: `flutter_app/lib/screens/pet_shopping_screen.dart` (ganti `_SuggestionCard`; ubah blok grup saran di `build`)
- Test: `flutter_app/test/screens/pet_shopping_screen_test.dart` (tambah test baru, jangan hapus yang ada)

**Interfaces:**
- Consumes: `commerceGridSurfaceTint(BuildContext)` dari `widgets/compact_commerce_product_card.dart`; `PetShoppingProduct`
- Produces: tidak ada API publik baru — `PetShoppingScreen`, `openPetShoppingProduct`, `PetShoppingArgs` tetap sama

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan test berikut di dalam `void main() { ... }` pada `flutter_app/test/screens/pet_shopping_screen_test.dart`. File ini SUDAH punya helper `used(name)`, `suggestion(name)`, `wrap(data)`, dan `pumpFrames(tester)` — pakai itu, jangan buat duplikatnya.

Dua aturan WAJIB di file ini (keduanya sudah tercermin pada helper yang ada):

1. `imageUrl` selalu `null`. `AppProductImage` dengan URL http merender `Shimmer` yang beranimasi tanpa henti → `pumpAndSettle` MENGGANTUNG selamanya. Assertion `fit`/ukuran tetap sah karena keduanya properti widget, bukan hasil unduhan.
2. Pakai `await pumpFrames(tester)`, BUKAN `pumpAndSettle()`, dengan alasan yang sama.

Tambahkan satu helper baru ini saja di atas `void main()`:

```dart
PetShopping dataWithSuggestions(int n) => PetShopping(
      usedCount: 0,
      used: const [],
      manual: const [],
      suggested: [for (var i = 0; i < n; i++) suggestion('Produk $i')],
    );
```

Test baru (tambahkan `import 'package:natalo_petshop_flutter/widgets/compact_commerce_product_card.dart' show commerceGridSurfaceTint;` dan `import 'package:natalo_petshop_flutter/widgets/app_product_image.dart';` ke blok import jika belum ada). Semuanya memakai `pumpFrames`, bukan `pumpAndSettle`:

```dart
  testWidgets('grid saran: kartu tanpa badge "Saran"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(4),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Saran'), findsNothing);
  });

  testWidgets('grid saran: nama 13/w600 tinggi dipaku, harga 16/w900',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => PetShopping(
          usedCount: 0,
          used: const [],
          manual: const [],
          suggested: [
            PetShoppingProduct(
              productId: 'id-kaniva',
              slug: 'kaniva',
              name: 'Kaniva Dog',
              imageUrl: null,
              effectivePrice: 335000,
              inStock: true,
              hasVariants: false,
            ),
          ],
        ),
      ),
    ));
    await pumpFrames(tester);

    final nama = tester.widget<Text>(find.text('Kaniva Dog'));
    expect(nama.style!.fontSize, 13);
    expect(nama.style!.fontWeight, FontWeight.w600);

    expect(find.text('Rp335.000'), findsOneWidget);
    final harga = tester.widget<Text>(find.text('Rp335.000'));
    expect(harga.style!.fontSize, 16);
    expect(harga.style!.fontWeight, FontWeight.w900);
  });

  testWidgets('grid saran: foto 1:1 BoxFit.cover full-bleed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(2),
      ),
    ));
    await pumpFrames(tester);
    final imgs = tester
        .widgetList<AppProductImage>(find.byType(AppProductImage))
        .toList();
    expect(imgs, isNotEmpty);
    for (final img in imgs) {
      expect(img.fit, BoxFit.cover);
    }
    final size = tester.getSize(find.byType(AppProductImage).first);
    expect(size.width, closeTo(size.height, 0.5), reason: 'foto WAJIB 1:1');
  });

  testWidgets('grid saran duduk di atas kanal abu (ala Beranda/Katalog)',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return PetShoppingScreen(
          petId: 'pet-1',
          petName: 'Didi',
          fetcher: (_) async => dataWithSuggestions(4),
        );
      }),
    ));
    await pumpFrames(tester);

    final expected = commerceGridSurfaceTint(ctx);
    final tinted = tester.widgetList<Container>(find.byType(Container)).where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == expected,
        );
    expect(tinted, isNotEmpty,
        reason: 'kartu putih butuh kanal abu supaya terbaca sebagai kartu');
  });

  testWidgets('grid saran menampilkan 12 kartu tanpa overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(12),
      ),
    ));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Produk 0'), findsOneWidget);
    expect(find.text('Produk 11'), findsOneWidget);
  });

  testWidgets('grid saran ganjil: kartu terakhir tidak melebar penuh',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(3),
      ),
    ));
    await pumpFrames(tester);

    final w0 = tester.getSize(find.text('Produk 0')).width;
    final w2 = tester.getSize(find.text('Produk 2')).width;
    expect(w2, closeTo(w0, 1.0),
        reason: 'kartu ganjil terakhir tetap selebar 1 kolom');
  });

  testWidgets('grid saran tidak overflow pada text scale 1.3', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: PetShoppingScreen(
          petId: 'pet-1',
          petName: 'Didi',
          fetcher: (_) async => PetShopping(
            usedCount: 0,
            used: const [],
            manual: const [],
            suggested: [
              for (var i = 0; i < 6; i++)
                suggestion('Nama Produk Panjang Sekali Nomor $i'),
            ],
          ),
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CTA "Jelajahi produk lain" tetap ada di bawah grid',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(2),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Jelajahi produk lain'), findsOneWidget);
  });
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/screens/pet_shopping_screen_test.dart`
Expected: FAIL — nama masih 12px, harga masih 12px `onSurfaceVariant`, dan tidak ada `Container` berwarna kanal abu.

- [ ] **Step 3: Tulis implementasi**

**(a)** Tambahkan import ini ke `flutter_app/lib/screens/pet_shopping_screen.dart`:

```dart
import '../widgets/compact_commerce_product_card.dart'
    show commerceGridSurfaceTint;
```

**(b)** Di dalam `build`, ganti blok grup saran — dari `if (data.suggested.isNotEmpty) ...[` sampai `],` penutupnya (yaitu header "Mungkin cocok", `SizedBox(height: 10)`, dan `Column` berisi baris-baris `_SuggestionCard`) — dengan:

```dart
              if (data.suggested.isNotEmpty) ...[
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(
                    'Mungkin cocok untuk ${widget.petName}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: NataloWeight.strong,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Kanal abu di belakang grid — kartu putih hanya terbaca
                // sebagai "kartu" kalau latarnya lebih gelap sedikit. Token
                // dan helper sama dengan grid Beranda/Katalog/Keranjang.
                Container(
                  decoration: BoxDecoration(
                    color: commerceGridSurfaceTint(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(6),
                  // Bukan GridView.count(childAspectRatio: ...) — rasio tetap
                  // overflow saat text scale sistem membesar (kartu berisi
                  // gambar 1:1 + nama 2 baris + harga). Baris manual biar
                  // tiap kartu tinggi mengikuti kontennya sendiri.
                  child: Column(
                    children: [
                      for (var i = 0; i < data.suggested.length; i += 2)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: i + 2 < data.suggested.length ? 6 : 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _SuggestionCard(
                                  product: data.suggested[i],
                                  onTap: () => _openProduct(data.suggested[i]),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: i + 1 < data.suggested.length
                                    ? _SuggestionCard(
                                        product: data.suggested[i + 1],
                                        onTap: () =>
                                            _openProduct(data.suggested[i + 1]),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
```

**(c)** Ganti seluruh kelas `_SuggestionCard` dengan:

```dart
/// Kartu saran — token disamakan dengan kartu grid Katalog
/// (`_ProductsPageProductCard`): kartu putih radius 8 + border + shadow
/// halus, foto 1:1 full-bleed `cover`, nama 13/w600 tinggi dipaku 34, harga
/// 16/w900. TANPA badge diskon/hemat/brand/rating: DTO Belanja tidak membawa
/// datanya.
class _SuggestionCard extends StatelessWidget {
  final PetShoppingProduct product;
  final VoidCallback onTap;

  const _SuggestionCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: product.name,
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: AppProductImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tinggi nama dipaku 34 (2 baris) — sama Katalog —
                      // supaya baris harga antar-kartu sebaris tetap sejajar.
                      SizedBox(
                        height: 34,
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatRupiah(product.effectivePrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Jalankan test & analyze, pastikan LULUS**

Run: `cd flutter_app && flutter test test/screens/pet_shopping_screen_test.dart`
Expected: PASS — semua test lama + 8 test baru lulus.

Run: `cd flutter_app && flutter analyze`
Expected: "No issues found!" atau tanpa isu baru.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/pet_shopping_screen.dart flutter_app/test/screens/pet_shopping_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(app): grid saran Belanja pakai gaya kartu Katalog + kanal abu

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Profil pet — strip abu di belakang rail + placeholder "Momen {nama}"

**Files:**
- Modify: `flutter_app/lib/screens/pet_profile_screen.dart` (`_PetShoppingSection`, `_ComingSoonCard`)
- Test: `flutter_app/test/screens/pet_profile_belanja_test.dart` (tambah test baru, jangan hapus yang ada)

**Interfaces:**
- Consumes: `commerceGridSurfaceTint(BuildContext)`; `PetShoppingRail`, `PetShoppingRailSkeleton` (Task 5); wrapper test `PetShoppingSectionForTest` yang sudah ada
- Produces: tidak ada API publik baru

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan test berikut di dalam `void main() { ... }` pada `flutter_app/test/screens/pet_profile_belanja_test.dart` (tambahkan import `compact_commerce_product_card.dart show commerceGridSurfaceTint` bila belum ada):

```dart
  testWidgets('rail Belanja di profil duduk di atas strip abu',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return SingleChildScrollView(
            // PetShoppingSectionForTest HANYA menerima petName & data —
            // callback-nya sudah di-hardcode no-op di dalam wrapper, jadi
            // JANGAN kirim onSeeAll/onTapProduct (compile error).
            child: PetShoppingSectionForTest(
              petName: 'Didi',
              data: PetShopping(
                usedCount: 0,
                used: const [],
                manual: const [],
                suggested: [
                  PetShoppingProduct(
                    productId: 'p1',
                    slug: 'kaniva',
                    name: 'Kaniva Dog',
                    // imageUrl null: URL http memicu Shimmer yang tak pernah
                    // settle di widget test (gotcha repo).
                    imageUrl: null,
                    effectivePrice: 335000,
                    inStock: true,
                    hasVariants: false,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    ));
    await tester.pump();

    final expected = commerceGridSurfaceTint(ctx);
    final tinted = tester.widgetList<Container>(find.byType(Container)).where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == expected,
        );
    expect(tinted, isNotEmpty,
        reason:
            'di halaman profil berlatar putih, kartu putih tanpa kanal abu '
            'tidak terbaca sebagai kartu');
  });

  testWidgets('placeholder Segera hadir menyebut Momen + nama pet',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PetComingSoonCardForTest(petName: 'Didi')),
    ));
    expect(find.text('Segera hadir'), findsOneWidget);
    expect(find.text('Momen Didi akan muncul di sini.'), findsOneWidget);
  });

  testWidgets('placeholder TIDAK lagi menyebut Belanja/Journey',
      (tester) async {
    // Belanja sudah live tepat di atas kartu ini — menjanjikannya
    // "segera hadir" saling bertentangan dengan UI di atasnya.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PetComingSoonCardForTest(petName: 'Didi')),
    ));
    expect(find.textContaining('Belanja'), findsNothing);
    expect(find.textContaining('Journey'), findsNothing);
  });
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/screens/pet_profile_belanja_test.dart`
Expected: FAIL — `PetComingSoonCardForTest` belum ada (compile error) dan belum ada `Container` berwarna kanal abu.

- [ ] **Step 3: Tulis implementasi**

**(a)** Tambahkan import ke `flutter_app/lib/screens/pet_profile_screen.dart`:

```dart
import '../widgets/compact_commerce_product_card.dart'
    show commerceGridSurfaceTint;
```

**(b)** Di `_PetShoppingSection.build`, ganti blok `if (d == null) ... else if ... else ...` (tiga cabang rail/skeleton/hint) dengan versi yang membungkus rail & skeleton dalam strip abu:

```dart
          if (d == null)
            Container(
              decoration: BoxDecoration(
                color: commerceGridSurfaceTint(context),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(6),
              child: const PetShoppingRailSkeleton(),
            )
          else if (d.used.isNotEmpty || d.suggested.isNotEmpty)
            // Kanal abu sama dengan grid Beranda/Katalog — di halaman profil
            // yang berlatar putih, kartu putih tanpa kanal ini tidak terbaca
            // sebagai kartu. Padding 6 = gap grid Katalog.
            Container(
              decoration: BoxDecoration(
                color: commerceGridSurfaceTint(context),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(6),
              child: PetShoppingRail(
                used: d.used,
                suggested: d.suggested,
                onTapProduct: onTapProduct,
              ),
            )
          else
            Text(
              'Lihat semua produk manual',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
```

**(c)** Di `_ComingSoonCard.build`, ganti teks deskripsi:

```dart
            Text(
              'Momen $petName akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
```

**(d)** Tambahkan wrapper test-only di AKHIR `flutter_app/lib/screens/pet_profile_screen.dart` (mengikuti pola `PetShoppingSectionForTest` yang sudah ada di file itu):

```dart
/// Wrapper test-only untuk `_ComingSoonCard` (kelas privat).
@visibleForTesting
class PetComingSoonCardForTest extends StatelessWidget {
  final String petName;
  const PetComingSoonCardForTest({super.key, required this.petName});

  @override
  Widget build(BuildContext context) => _ComingSoonCard(petName: petName);
}
```

- [ ] **Step 4: Jalankan test & analyze, pastikan LULUS**

Run: `cd flutter_app && flutter test test/screens/pet_profile_belanja_test.dart`
Expected: PASS — semua test lama + 3 test baru lulus.

Run: `cd flutter_app && flutter analyze`
Expected: "No issues found!" atau tanpa isu baru.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/pet_profile_screen.dart flutter_app/test/screens/pet_profile_belanja_test.dart
git commit -m "$(cat <<'EOF'
feat(app): strip abu di belakang rail Belanja + placeholder Momen {nama}

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Regresi penuh

**Files:**
- Tidak ada file produksi yang diubah. Kalau ada test lain yang merah karena perubahan Task 1–7, perbaiki test tersebut (atau kode yang benar-benar rusak) di task ini.

**Interfaces:**
- Consumes: seluruh hasil Task 1–7
- Produces: bukti hijau untuk seluruh suite

- [ ] **Step 1: Jalankan seluruh test backend**

Run: `npm test`
Expected: PASS. Perhatikan khusus `tests/pet-shopping.test.ts` (38 test) dan `tests/pet-shopping-route.test.ts`.

- [ ] **Step 2: Jalankan typecheck**

Run: `npx tsc --noEmit`
Expected: 0 error. Tidak boleh ada sisa referensi `rankShoppingCandidates`, `speciesMatchTier`, `POOL_TAKE`.

- [ ] **Step 3: Pastikan tak ada sisa istilah/nilai lama**

Run:

```bash
grep -rn "rankShoppingCandidates\|speciesMatchTier\|POOL_TAKE" lib app tests || echo "CLEAN"
```

Expected: `CLEAN`.

Run:

```bash
grep -rn "Reptil\|Burung" lib/pet-shopping.ts || echo "CLEAN"
```

Expected: `CLEAN` (spesies itu tidak boleh lagi muncul di helper).

- [ ] **Step 4: Jalankan seluruh test Flutter**

Run: `cd flutter_app && flutter test`
Expected: PASS untuk semua file, KECUALI `test/screens/member_screen_test.dart` yang sudah merah di `origin/main` sebelum branch ini (kegagalan pre-existing, TIDAK terkait). Verifikasi klaim itu sebelum mengabaikannya:

```bash
cd flutter_app && git stash list >/dev/null; git -C .. show origin/main --stat >/dev/null; flutter test test/screens/member_screen_test.dart
```

Kalau file lain merah, itu regresi milik branch ini dan WAJIB diperbaiki di task ini.

- [ ] **Step 5: Jalankan analyze**

Run: `cd flutter_app && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit (hanya kalau ada perbaikan di Step 1–5)**

```bash
git add -A
git commit -m "$(cat <<'EOF'
test: regresi penuh kolom Belanja rotasi (backend + Flutter)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

Kalau tak ada yang perlu diperbaiki, lewati commit dan laporkan hasil suite.
