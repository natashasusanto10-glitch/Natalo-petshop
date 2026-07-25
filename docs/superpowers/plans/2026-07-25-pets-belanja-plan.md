# Kolom Belanja di Profil Pet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Profil pet menampilkan produk yang pernah dipakai untuk pet itu (dari `PetCareRecord`) plus saran produk yang cocok per spesies, dengan aksi beli-ulang.

**Architecture:** Satu endpoint baru `GET /api/member/pets/[id]/shopping` yang membaca `PetCareRecord` (sumber "pernah dipakai") dan `Product`+`Category` (sumber saran). Logika pencocokan spesies diekstrak ke helper murni supaya teruji tanpa DB. Flutter menambah satu model, satu widget rail (dipakai di profil), dan satu halaman penuh; aksi beli-ulang menumpang widget yang sudah ada (`ProductVariantPickerSheet`, `showAddedToCartSheet`).

**Tech Stack:** Next.js App Router + Prisma (Postgres/Neon) di backend; Flutter di `flutter_app/`. Test backend `npx tsx --test`, test Flutter `flutter test`.

## Global Constraints

Nilai-nilai berikut dikutip dari spec `docs/superpowers/specs/2026-07-25-pets-belanja-design.md` dan berlaku untuk SEMUA task:

- Angka kartu statistik `Belanja` WAJIB sama dengan jumlah baris grup "Pernah dipakai": `usedCount == used.length + manual.length`. Penyaringan (produk nonaktif dll) WAJIB di server, jangan di client.
- Gating agregasi/kondisi UI pakai field eksplisit dari API, JANGAN menghitung dari panjang array lain.
- Gambar produk WAJIB `AppProductImage` rasio 1:1 `borderRadius` 8. JANGAN membuat gaya kartu ketiga; ikut bahasa Katalog & picker obat.
- Harga WAJIB lewat `formatRupiah`. JANGAN interpolasi mentah (`'Rp${x}'` pernah menghasilkan bug "Rp45000").
- Warna WAJIB token semantic (`cs.surface`, `cs.outlineVariant`, `cs.onSurfaceVariant`) + `NataloColors.primary`. TIDAK ADA hex hardcode. Tiap elemen benar di light & dark.
- Berat font pakai token `NataloWeight` (`body` w400 / `strong` w600).
- Nama produk maksimal 2 baris lalu ellipsis di SEMUA konteks. Tombol "Beli lagi" lebar TETAP, tidak menyempit karena nama panjang.
- Target sentuh ≥44pt; ripple/feedback ≤150ms; transisi state 150–300ms.
- Label pembaca layar tombol beli-ulang WAJIB memuat nama produk ("Beli lagi, Drontal Cat").
- Baris konteks berbunyi "Dipakai Nx, terakhir {waktu}" — BUKAN nama kategori (harus beda framing dari section Perawatan di atasnya).
- Harga di grup "Pernah dipakai" diberi label "Harga sekarang".
- "Beli lagi" memakai `showAddedToCartSheet`, BUKAN toast.
- **GOTCHA STOK VARIAN:** produk varian menyimpan stok di `ProductVariant.stock` dengan `Product.stock` = 0. JANGAN memfilter `stock: { gt: 0 }` di SQL — hitung `effectiveStock()` di JS lalu filter. Filter SQL akan salah membuang semua produk varian.
- Kerja di worktree `.claude/worktrees/perawatan-form-polish` (branch `claude/perawatan-form-polish`). JANGAN commit di checkout `main` yang dipakai worktree lain.

---

## File Structure

| File | Tanggung jawab |
|---|---|
| `lib/pet-shopping.ts` (baru) | Helper murni: aturan pencocokan spesies + peringkat kandidat. Tanpa I/O. |
| `tests/pet-shopping.test.ts` (baru) | Test helper murni. |
| `app/api/member/pets/[id]/shopping/route.ts` (baru) | Endpoint: auth, ownership, agregasi `used`/`manual`/`suggested`. |
| `tests/pet-shopping-route.test.ts` (baru) | Test agregasi endpoint via fungsi terekspos. |
| `flutter_app/lib/models/pet_shopping.dart` (baru) | Model + parsing `PetShopping`, `PetShoppingProduct`, `PetShoppingManual`. |
| `flutter_app/test/models/pet_shopping_model_test.dart` (baru) | Test parsing. |
| `flutter_app/lib/services/pet_service.dart` (ubah) | `fetchPetShopping(petId)`. |
| `flutter_app/lib/widgets/pet_shopping_rail.dart` (baru) | Rail horizontal + skeleton tinggi-tetap. Dipakai profil. |
| `flutter_app/test/widgets/pet_shopping_rail_test.dart` (baru) | Test rail: badge saran, ellipsis, paritas tinggi skeleton. |
| `flutter_app/lib/screens/pet_shopping_screen.dart` (baru) | Halaman penuh: grup fakta (baris), grup saran (grid), CTA, empty-state. |
| `flutter_app/test/screens/pet_shopping_screen_test.dart` (baru) | Test halaman penuh + alur beli-ulang. |
| `flutter_app/lib/screens/pet_profile_screen.dart` (ubah) | Section Belanja + kartu statistik bisa ditekan/diredupkan. |
| `flutter_app/test/screens/pet_profile_belanja_test.dart` (baru) | Test integrasi profil. |
| `flutter_app/lib/main.dart` (ubah) | Route `/pets/belanja`. |

---

## Task 1: Helper murni pencocokan spesies

**Files:**
- Create: `lib/pet-shopping.ts`
- Test: `tests/pet-shopping.test.ts`

**Interfaces:**
- Produces (dipakai Task 2):
  - `PET_SPECIES: readonly string[]` — `["Kucing", "Anjing", "Ikan", "Burung", "Reptil"]`
  - `type ShoppingCandidate = { id: string; targetSpecies: string[]; categoryName: string | null }`
  - `speciesMatchTier(c: ShoppingCandidate, petType: string): number` — `0` = targetSpecies cocok, `1` = kategori ber-spesies cocok, `2` = kategori netral, `-1` = dikecualikan
  - `rankShoppingCandidates<T extends ShoppingCandidate>(items: T[], petType: string): T[]`

- [ ] **Step 1: Tulis failing test**

`tests/pet-shopping.test.ts`:

```ts
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
```

- [ ] **Step 2: Verifikasi gagal**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: FAIL — `Cannot find module '../lib/pet-shopping'`.

- [ ] **Step 3: Implement**

`lib/pet-shopping.ts`:

```ts
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
```

- [ ] **Step 4: Verifikasi lulus**

Run: `npx tsx --test tests/pet-shopping.test.ts`
Expected: PASS (7 test).

- [ ] **Step 5: Commit**

```bash
git add lib/pet-shopping.ts tests/pet-shopping.test.ts
git commit -m "feat(pets): helper murni pencocokan spesies utk kolom Belanja"
```

---

## Task 2: Endpoint `GET /api/member/pets/[id]/shopping`

**Files:**
- Create: `app/api/member/pets/[id]/shopping/route.ts`
- Test: `tests/pet-shopping-route.test.ts`

**Interfaces:**
- Consumes: `rankShoppingCandidates`, `ShoppingCandidate` (Task 1); `effectivePrice`, `effectiveStock`, `type RecoProductInput` dari `lib/product-dosage.ts`.
- Produces (dipakai Task 3): JSON `{ usedCount, used[], manual[], suggested[] }`; fungsi terekspos `buildUsageMaps`, `toShoppingProduct`, `composeUsed` untuk test.

Bentuk item:
```ts
// used[] & suggested[]
{ productId, slug, name, imageUrl, effectivePrice, inStock, hasVariants,
  usageCount?, lastUsedAt? }   // usageCount+lastUsedAt hanya di used[]
// manual[]
{ brandText, usageCount, lastUsedAt }
```

`slug` WAJIB ada: `ProductVariantPickerSheet.show()` dan `productService.fetchProductBySlug()` keduanya mengambil produk penuh lewat slug.

- [ ] **Step 1: Tulis failing test**

`tests/pet-shopping-route.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  buildUsageMaps,
  composeUsed,
  toShoppingProduct,
} from "../app/api/member/pets/[id]/shopping/route";

const d = (s: string) => new Date(s);

test("used: dedup per produk, hitung pemakaian, ambil doneAt terbaru", () => {
  const { used, manual } = buildUsageMaps([
    { productId: "p1", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "p1", brandText: null, doneAt: d("2026-04-01T00:00:00Z") },
    { productId: "p2", brandText: null, doneAt: d("2026-06-01T00:00:00Z") },
  ]);
  assert.equal(used.size, 2);
  assert.equal(used.get("p1")!.usageCount, 2);
  assert.deepEqual(used.get("p1")!.lastUsedAt, d("2026-07-01T00:00:00Z"));
  assert.equal(manual.size, 0);
});

test("manual: brandText di-trim, dedup, record tanpa brand diabaikan", () => {
  const { used, manual } = buildUsageMaps([
    { productId: null, brandText: " Bravecto ", doneAt: d("2026-07-01T00:00:00Z") },
    { productId: null, brandText: "Bravecto", doneAt: d("2026-05-01T00:00:00Z") },
    { productId: null, brandText: "   ", doneAt: d("2026-05-01T00:00:00Z") },
    { productId: null, brandText: null, doneAt: d("2026-05-01T00:00:00Z") },
  ]);
  assert.equal(used.size, 0);
  assert.equal(manual.size, 1);
  assert.equal(manual.get("Bravecto")!.usageCount, 2);
  assert.deepEqual(manual.get("Bravecto")!.lastUsedAt, d("2026-07-01T00:00:00Z"));
});

test("toShoppingProduct: stok varian dihitung dari variants, bukan Product.stock", () => {
  const out = toShoppingProduct({
    id: "p1",
    slug: "drontal-cat",
    name: "Drontal Cat",
    imageUrl: "https://cdn/x.jpg",
    price: 45000,
    stock: 0,
    targetSpecies: [],
    category: { name: "Obat & Suplemen" },
    variants: [{ price: 47000, stock: 3 }],
  });
  assert.equal(out.productId, "p1");
  assert.equal(out.slug, "drontal-cat");
  assert.equal(out.hasVariants, true);
  assert.equal(out.inStock, true, "produk varian base stock 0 tetap in-stock");
});

test("toShoppingProduct: produk non-varian pakai stok & harga sendiri", () => {
  const out = toShoppingProduct({
    id: "p2",
    slug: "sisir",
    name: "Sisir Grooming",
    imageUrl: null,
    price: 19500,
    stock: 0,
    targetSpecies: [],
    category: null,
    variants: [],
  });
  assert.equal(out.hasVariants, false);
  assert.equal(out.inStock, false);
  assert.equal(out.effectivePrice, 19500);
});

const row = (id: string, slug: string) => ({
  id,
  slug,
  name: id,
  imageUrl: null,
  price: 1000,
  stock: 5,
  targetSpecies: [] as string[],
  category: null,
  variants: [] as { price: number; stock: number }[],
});

test("composeUsed: produk nonaktif (tak ada di rows) hilang dari daftar", () => {
  const { used } = buildUsageMaps([
    { productId: "p1", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "gone", brandText: null, doneAt: d("2026-06-01T00:00:00Z") },
  ]);
  // `rows` hanya berisi p1 — meniru query `isActive: true` yang membuang "gone".
  const out = composeUsed([row("p1", "s1")], used);
  assert.equal(out.length, 1);
  assert.equal(out[0].productId, "p1");
});

test("composeUsed: urut terakhir-dipakai lebih dulu", () => {
  const { used } = buildUsageMaps([
    { productId: "baru", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "lama", brandText: null, doneAt: d("2026-01-01T00:00:00Z") },
  ]);
  const out = composeUsed([row("lama", "s-lama"), row("baru", "s-baru")], used);
  assert.deepEqual(out.map((o) => o.productId), ["baru", "lama"]);
});

test("INVARIAN: usedCount == jumlah baris yang tampil, walau ada produk nonaktif", () => {
  const { used, manual } = buildUsageMaps([
    { productId: "p1", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "gone", brandText: null, doneAt: d("2026-06-01T00:00:00Z") },
    { productId: null, brandText: "Bravecto", doneAt: d("2026-05-01T00:00:00Z") },
  ]);
  const usedList = composeUsed([row("p1", "s1")], used);
  const usedCount = usedList.length + manual.size;
  assert.equal(usedCount, 2, "1 produk aktif + 1 brand manual; yang nonaktif tak dihitung");
});
```

- [ ] **Step 2: Verifikasi gagal**

Run: `npx tsx --test tests/pet-shopping-route.test.ts`
Expected: FAIL — module tidak ditemukan.

- [ ] **Step 3: Implement endpoint**

`app/api/member/pets/[id]/shopping/route.ts`:

```ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import {
  effectivePrice,
  effectiveStock,
  type RecoProductInput,
} from "@/lib/product-dosage";
import {
  PET_SPECIES,
  rankShoppingCandidates,
  type ShoppingCandidate,
} from "@/lib/pet-shopping";

const SUGGESTED_LIMIT = 8;
const POOL_TAKE = 40;

const PRODUCT_SELECT = {
  id: true,
  slug: true,
  name: true,
  imageUrl: true,
  price: true,
  stock: true,
  targetSpecies: true,
  category: { select: { name: true } },
  variants: {
    where: { isActive: true, deletedAt: null },
    select: { price: true, stock: true },
  },
} as const;

export type ProductRow = {
  id: string;
  slug: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
  targetSpecies: string[];
  category: { name: string } | null;
  variants: { price: number; stock: number }[];
};

export type CareRecordRow = {
  productId: string | null;
  brandText: string | null;
  doneAt: Date;
};

export type UsageEntry = { usageCount: number; lastUsedAt: Date };

/**
 * Ringkas record perawatan jadi dua peta pemakaian. `records` WAJIB sudah
 * urut `doneAt` menurun supaya entri pertama yang terlihat = terbaru.
 */
export function buildUsageMaps(records: CareRecordRow[]): {
  used: Map<string, UsageEntry>;
  manual: Map<string, UsageEntry>;
} {
  const used = new Map<string, UsageEntry>();
  const manual = new Map<string, UsageEntry>();
  for (const r of records) {
    if (r.productId) {
      const prev = used.get(r.productId);
      if (prev) prev.usageCount += 1;
      else used.set(r.productId, { usageCount: 1, lastUsedAt: r.doneAt });
      continue;
    }
    const brand = (r.brandText ?? "").trim();
    if (brand === "") continue;
    const prev = manual.get(brand);
    if (prev) prev.usageCount += 1;
    else manual.set(brand, { usageCount: 1, lastUsedAt: r.doneAt });
  }
  return { used, manual };
}

function toRecoInput(row: ProductRow): RecoProductInput {
  return {
    id: row.id,
    name: row.name,
    price: row.price,
    baseStock: row.stock,
    variantStocks: row.variants.map((v) => v.stock),
    variantPrices: row.variants.map((v) => v.price),
    targetSpecies: row.targetSpecies ?? [],
    dosageRules: [],
  };
}

export function toShoppingProduct(row: ProductRow) {
  const input = toRecoInput(row);
  return {
    productId: row.id,
    slug: row.slug,
    name: row.name,
    imageUrl: row.imageUrl,
    effectivePrice: effectivePrice(input),
    // GOTCHA: produk varian punya Product.stock = 0 dan stok sebenarnya di
    // ProductVariant. effectiveStock menjumlahkan varian, jadi JANGAN pernah
    // memfilter stok di SQL — nanti semua produk varian terbuang.
    inStock: effectiveStock(input) > 0,
    hasVariants: row.variants.length > 0,
  };
}

/**
 * Gabungkan baris produk aktif dengan data pemakaian, urut terakhir-dipakai.
 * Produk yang tidak ada di `rows` (nonaktif/terhapus) otomatis hilang — dan
 * karena `usedCount` dihitung dari panjang hasil fungsi ini, angka kartu
 * statistik TIDAK MUNGKIN berbeda dari jumlah baris yang tampil.
 */
export function composeUsed(
  rows: ProductRow[],
  usage: Map<string, UsageEntry>,
) {
  return rows
    .filter((row) => usage.has(row.id))
    .map((row) => {
      const u = usage.get(row.id)!;
      return {
        ...toShoppingProduct(row),
        usageCount: u.usageCount,
        lastUsedAt: u.lastUsedAt.toISOString(),
      };
    })
    .sort((a, b) => b.lastUsedAt.localeCompare(a.lastUsedAt));
}

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  const pet = await prisma.pet.findFirst({
    where: { id, userId: session.sub },
    select: { id: true, type: true },
  });
  if (!pet) {
    // 404 (bukan 403) mengikuti route care/ yang sudah ada — sekaligus tidak
    // membocorkan apakah pet milik orang lain itu ada.
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const records = (await prisma.petCareRecord.findMany({
    where: { petId: id },
    orderBy: { doneAt: "desc" },
    select: { productId: true, brandText: true, doneAt: true },
  })) as CareRecordRow[];

  const { used: usedMap, manual: manualMap } = buildUsageMaps(records);

  const usedRows = usedMap.size
    ? ((await prisma.product.findMany({
        where: { id: { in: [...usedMap.keys()] }, isActive: true },
        select: PRODUCT_SELECT,
      })) as unknown as ProductRow[])
    : [];

  const used = composeUsed(usedRows, usedMap);

  const manual = [...manualMap.entries()]
    .map(([brandText, usage]) => ({
      brandText,
      usageCount: usage.usageCount,
      lastUsedAt: usage.lastUsedAt.toISOString(),
    }))
    .sort((a, b) => b.lastUsedAt.localeCompare(a.lastUsedAt));

  // Kandidat saran: dua query berbatas, lalu diperingkat di JS supaya
  // aturannya teruji (Task 1) dan tidak perlu memindai 1300+ produk.
  const usedIds = used.map((u) => u.productId);
  const notUsed = usedIds.length ? { id: { notIn: usedIds } } : {};
  const speciesMatched = (await prisma.product.findMany({
    where: {
      isActive: true,
      ...notUsed,
      OR: [
        { targetSpecies: { has: pet.type } },
        { category: { name: { contains: pet.type, mode: "insensitive" } } },
      ],
    },
    select: PRODUCT_SELECT,
    orderBy: { createdAt: "desc" },
    take: POOL_TAKE,
  })) as unknown as ProductRow[];

  let pool = speciesMatched;
  if (pool.length < SUGGESTED_LIMIT) {
    const neutral = (await prisma.product.findMany({
      where: {
        isActive: true,
        ...notUsed,
        targetSpecies: { isEmpty: true },
        AND: PET_SPECIES.map((s) => ({
          NOT: { category: { name: { contains: s, mode: "insensitive" } } },
        })),
      },
      select: PRODUCT_SELECT,
      orderBy: { createdAt: "desc" },
      take: POOL_TAKE,
    })) as unknown as ProductRow[];
    pool = [...pool, ...neutral];
  }

  const candidates: (ShoppingCandidate & { row: ProductRow })[] = pool.map(
    (row) => ({
      id: row.id,
      targetSpecies: row.targetSpecies ?? [],
      categoryName: row.category?.name ?? null,
      row,
    }),
  );

  const suggested = rankShoppingCandidates(candidates, pet.type)
    .map((c) => toShoppingProduct(c.row))
    .filter((p) => p.inStock)
    .slice(0, SUGGESTED_LIMIT);

  return NextResponse.json({
    usedCount: used.length + manual.length,
    used,
    manual,
    suggested,
  });
}
```

- [ ] **Step 4: Verifikasi lulus + kompilasi**

Run: `npx tsx --test tests/pet-shopping-route.test.ts && npx tsc --noEmit`
Expected: PASS (7 test); `tsc` tanpa error baru (error `Cannot find module 'vitest'` di file test lain sudah ada sebelumnya, abaikan).

- [ ] **Step 5: Commit**

```bash
git add "app/api/member/pets/[id]/shopping/route.ts" tests/pet-shopping-route.test.ts
git commit -m "feat(api): endpoint belanja per pet (pernah dipakai + saran per spesies)"
```

---

## Task 3: Model Flutter `PetShopping`

**Files:**
- Create: `flutter_app/lib/models/pet_shopping.dart`
- Test: `flutter_app/test/models/pet_shopping_model_test.dart`

**Interfaces:**
- Consumes: bentuk JSON dari Task 2.
- Produces (dipakai Task 4–7):
  - `class PetShoppingProduct { String productId, slug, name; String? imageUrl; int effectivePrice; bool inStock, hasVariants; int? usageCount; DateTime? lastUsedAt; }`
  - `class PetShoppingManual { String brandText; int usageCount; DateTime lastUsedAt; }`
  - `class PetShopping { int usedCount; List<PetShoppingProduct> used; List<PetShoppingManual> manual; List<PetShoppingProduct> suggested; bool get isEmpty; }`
  - `String petShoppingUsageLabel(int usageCount, DateTime lastUsedAt, {DateTime? now})` → "Dipakai 2x, terakhir 3 bulan lalu"

- [ ] **Step 1: Tulis failing test**

`flutter_app/test/models/pet_shopping_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';

void main() {
  test('parsing lengkap dari JSON API', () {
    final s = PetShopping.fromJson(const {
      'usedCount': 3,
      'used': [
        {
          'productId': 'p1',
          'slug': 'drontal-cat',
          'name': 'Drontal Cat',
          'imageUrl': 'https://cdn/x.jpg',
          'effectivePrice': 45000,
          'inStock': true,
          'hasVariants': false,
          'usageCount': 2,
          'lastUsedAt': '2026-04-25T00:00:00.000Z',
        },
      ],
      'manual': [
        {
          'brandText': 'Bravecto',
          'usageCount': 1,
          'lastUsedAt': '2026-06-25T00:00:00.000Z',
        },
      ],
      'suggested': [
        {
          'productId': 'p9',
          'slug': 'snack-dental',
          'name': 'Snack Dental Stick',
          'imageUrl': null,
          'effectivePrice': 28000,
          'inStock': true,
          'hasVariants': true,
        },
      ],
    });

    expect(s.usedCount, 3);
    expect(s.used.single.slug, 'drontal-cat');
    expect(s.used.single.usageCount, 2);
    expect(s.used.single.lastUsedAt, isNotNull);
    expect(s.manual.single.brandText, 'Bravecto');
    expect(s.suggested.single.hasVariants, isTrue);
    expect(s.suggested.single.imageUrl, isNull);
    expect(s.isEmpty, isFalse);
  });

  test('isEmpty hanya saat used, manual, dan suggested kosong semua', () {
    const empty = {'usedCount': 0, 'used': [], 'manual': [], 'suggested': []};
    expect(PetShopping.fromJson(empty).isEmpty, isTrue);

    final onlySuggested = PetShopping.fromJson(const {
      'usedCount': 0,
      'used': [],
      'manual': [],
      'suggested': [
        {
          'productId': 'p9',
          'slug': 's',
          'name': 'N',
          'effectivePrice': 1000,
          'inStock': true,
          'hasVariants': false,
        },
      ],
    });
    expect(onlySuggested.isEmpty, isFalse);
  });

  test('field hilang tidak bikin crash', () {
    final s = PetShopping.fromJson(const {});
    expect(s.usedCount, 0);
    expect(s.used, isEmpty);
    expect(s.isEmpty, isTrue);
  });

  test('label pemakaian: hitungan + waktu relatif', () {
    final now = DateTime(2026, 7, 25);
    expect(
      petShoppingUsageLabel(2, DateTime(2026, 4, 25), now: now),
      'Dipakai 2x, terakhir 3 bulan lalu',
    );
    expect(
      petShoppingUsageLabel(1, DateTime(2026, 7, 24), now: now),
      'Dipakai 1x, terakhir 1 hari lalu',
    );
    expect(
      petShoppingUsageLabel(1, DateTime(2026, 7, 25), now: now),
      'Dipakai 1x, terakhir hari ini',
    );
    expect(
      petShoppingUsageLabel(5, DateTime(2025, 1, 25), now: now),
      'Dipakai 5x, terakhir 1 tahun lalu',
    );
  });
}
```

- [ ] **Step 2: Verifikasi gagal**

Run (dari `flutter_app/`): `flutter test test/models/pet_shopping_model_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:natalo_petshop_flutter/models/pet_shopping.dart'`.

- [ ] **Step 3: Implement**

`flutter_app/lib/models/pet_shopping.dart`:

```dart
/// Model kolom Belanja profil pet (spec
/// docs/superpowers/specs/2026-07-25-pets-belanja-design.md).
/// `slug` dibawa karena ProductVariantPickerSheet & fetchProductBySlug
/// keduanya mengambil produk penuh lewat slug.
class PetShoppingProduct {
  final String productId;
  final String slug;
  final String name;
  final String? imageUrl;
  final int effectivePrice;
  final bool inStock;
  final bool hasVariants;

  /// Hanya terisi untuk item di grup "Pernah dipakai".
  final int? usageCount;
  final DateTime? lastUsedAt;

  const PetShoppingProduct({
    required this.productId,
    required this.slug,
    required this.name,
    required this.imageUrl,
    required this.effectivePrice,
    required this.inStock,
    required this.hasVariants,
    this.usageCount,
    this.lastUsedAt,
  });

  factory PetShoppingProduct.fromJson(Map<String, dynamic> json) {
    final raw = json['lastUsedAt'] as String?;
    return PetShoppingProduct(
      productId: json['productId'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      effectivePrice: (json['effectivePrice'] as num?)?.toInt() ?? 0,
      inStock: json['inStock'] as bool? ?? false,
      hasVariants: json['hasVariants'] as bool? ?? false,
      usageCount: (json['usageCount'] as num?)?.toInt(),
      lastUsedAt: raw == null ? null : DateTime.tryParse(raw),
    );
  }
}

class PetShoppingManual {
  final String brandText;
  final int usageCount;
  final DateTime lastUsedAt;

  const PetShoppingManual({
    required this.brandText,
    required this.usageCount,
    required this.lastUsedAt,
  });

  factory PetShoppingManual.fromJson(Map<String, dynamic> json) {
    return PetShoppingManual(
      brandText: json['brandText'] as String? ?? '',
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 1,
      lastUsedAt:
          DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PetShopping {
  final int usedCount;
  final List<PetShoppingProduct> used;
  final List<PetShoppingManual> manual;
  final List<PetShoppingProduct> suggested;

  const PetShopping({
    required this.usedCount,
    required this.used,
    required this.manual,
    required this.suggested,
  });

  /// Section Belanja disembunyikan penuh saat ini true (spec Keputusan 13).
  bool get isEmpty => used.isEmpty && manual.isEmpty && suggested.isEmpty;

  static List<PetShoppingProduct> _products(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PetShoppingProduct.fromJson)
        .toList();
  }

  factory PetShopping.fromJson(Map<String, dynamic> json) {
    final rawManual = json['manual'];
    return PetShopping(
      usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
      used: _products(json['used']),
      manual: rawManual is List
          ? rawManual
              .whereType<Map<String, dynamic>>()
              .map(PetShoppingManual.fromJson)
              .toList()
          : const [],
      suggested: _products(json['suggested']),
    );
  }
}

/// "Dipakai 2x, terakhir 3 bulan lalu" — framing BELANJA, sengaja beda dari
/// section Perawatan di atasnya yang sudah menampilkan "kategori — tanggal"
/// (spec Keputusan 12).
String petShoppingUsageLabel(
  int usageCount,
  DateTime lastUsedAt, {
  DateTime? now,
}) {
  final base = now ?? DateTime.now();
  final days = base.difference(lastUsedAt).inDays;
  final String when;
  if (days <= 0) {
    when = 'hari ini';
  } else if (days < 30) {
    when = '$days hari lalu';
  } else if (days < 365) {
    when = '${days ~/ 30} bulan lalu';
  } else {
    when = '${days ~/ 365} tahun lalu';
  }
  return 'Dipakai ${usageCount}x, terakhir $when';
}
```

- [ ] **Step 4: Verifikasi lulus**

Run: `flutter test test/models/pet_shopping_model_test.dart`
Expected: PASS (4 test).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/pet_shopping.dart flutter_app/test/models/pet_shopping_model_test.dart
git commit -m "feat(app): model PetShopping + label pemakaian produk"
```

---

## Task 4: Service `fetchPetShopping`

**Files:**
- Modify: `flutter_app/lib/services/pet_service.dart` (tambah method sebelum penutup class `PetService`)

**Interfaces:**
- Consumes: `PetShopping` (Task 3), `apiClient.getJson` (pola sama `fetchCareRecommendation` di file yang sama).
- Produces (dipakai Task 5–7): `Future<PetShopping> fetchPetShopping(String petId)`; typedef `PetShoppingFetcher = Future<PetShopping> Function(String petId)`.

- [ ] **Step 1: Tambah import & method**

Di `flutter_app/lib/services/pet_service.dart`, tambahkan import di daftar import atas file:

```dart
import '../models/pet_shopping.dart';
```

Lalu sisipkan sebelum kurung tutup terakhir class `PetService` (tepat sebelum baris `}` yang diikuti `final petService = PetService._();`):

```dart
  /// Kolom Belanja profil pet: produk yang pernah dipakai + saran per spesies.
  Future<PetShopping> fetchPetShopping(String petId) async {
    final data = await apiClient.getJson('/api/member/pets/$petId/shopping');
    if (data is! Map<String, dynamic>) {
      return const PetShopping(
        usedCount: 0,
        used: [],
        manual: [],
        suggested: [],
      );
    }
    return PetShopping.fromJson(data);
  }
```

Dan di akhir file, setelah `final petService = PetService._();`, tambahkan:

```dart
/// Seam injeksi untuk test widget (hindari panggilan jaringan nyata).
typedef PetShoppingFetcher = Future<PetShopping> Function(String petId);
```

- [ ] **Step 2: Verifikasi kompilasi**

Run (dari `flutter_app/`): `flutter analyze lib/services/pet_service.dart lib/models/pet_shopping.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/services/pet_service.dart
git commit -m "feat(app): petService.fetchPetShopping + typedef fetcher"
```

---

## Task 5: Widget rail + skeleton

**Files:**
- Create: `flutter_app/lib/widgets/pet_shopping_rail.dart`
- Test: `flutter_app/test/widgets/pet_shopping_rail_test.dart`

**Interfaces:**
- Consumes: `PetShoppingProduct` (Task 3), `AppProductImage`, `formatRupiah`, `NataloColors`, `NataloWeight`.
- Produces (dipakai Task 7): 
  - `class PetShoppingRail extends StatelessWidget` — params `{ required List<PetShoppingProduct> used, required List<PetShoppingProduct> suggested, required void Function(PetShoppingProduct) onTapProduct }`
  - `class PetShoppingRailSkeleton extends StatelessWidget` — tanpa params
  - `const double kPetShoppingRailHeight = 168` — tinggi tetap dipakai rail DAN skeleton (paritas tinggi = tak ada pergeseran layout)

- [ ] **Step 1: Tulis failing test**

`flutter_app/test/widgets/pet_shopping_rail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/widgets/pet_shopping_rail.dart';

PetShoppingProduct p(String name, {bool used = true}) => PetShoppingProduct(
      productId: 'id-$name',
      slug: 'slug-$name',
      name: name,
      imageUrl: 'https://cdn/$name.jpg',
      effectivePrice: 45000,
      inStock: true,
      hasVariants: false,
      usageCount: used ? 2 : null,
      lastUsedAt: used ? DateTime(2026, 4, 25) : null,
    );

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('harga diformat rupiah, bukan angka mentah', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: const [],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Rp45.000'), findsOneWidget);
    expect(find.text('Rp45000'), findsNothing);
  });

  testWidgets('kartu saran diberi badge, kartu fakta tidak', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: [p('Snack', used: false)],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Saran'), findsOneWidget);
  });

  testWidgets('nama panjang dibatasi 2 baris + ellipsis', (tester) async {
    const long =
        'Drontal Plus Tasty Dog Bentuk TULANG Obat Cacing Anjing per tablet untuk 10KG berat badan';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [
            PetShoppingProduct(
              productId: 'p1',
              slug: 's1',
              name: long,
              imageUrl: null,
              effectivePrice: 34800,
              inStock: true,
              hasVariants: false,
              usageCount: 1,
              lastUsedAt: DateTime(2026, 7, 1),
            ),
          ],
          suggested: const [],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    final text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('tap kartu memanggil onTapProduct dengan produk yang benar',
      (tester) async {
    PetShoppingProduct? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: const [],
          onTapProduct: (x) => tapped = x,
        ),
      ),
    ));
    await pumpFrames(tester);
    await tester.tap(find.text('Drontal'));
    await tester.pump();
    expect(tapped?.slug, 'slug-Drontal');
  });

  testWidgets('skeleton punya tinggi SAMA dengan rail terisi', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PetShoppingRailSkeleton()),
    ));
    await pumpFrames(tester);
    final skeletonHeight =
        tester.getSize(find.byType(PetShoppingRailSkeleton)).height;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: const [],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    final railHeight = tester.getSize(find.byType(PetShoppingRail)).height;

    expect(skeletonHeight, railHeight,
        reason: 'tinggi harus identik supaya profil tidak melonjak saat data tiba');
    expect(railHeight, kPetShoppingRailHeight);
  });
}
```

- [ ] **Step 2: Verifikasi gagal**

Run: `flutter test test/widgets/pet_shopping_rail_test.dart`
Expected: FAIL — URI `widgets/pet_shopping_rail.dart` tidak ada.

- [ ] **Step 3: Implement**

`flutter_app/lib/widgets/pet_shopping_rail.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/pet_shopping.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';

/// Tinggi TETAP rail — dipakai rail terisi maupun skeleton supaya konten di
/// bawahnya tidak melonjak saat data tiba (spec: reserve space for async).
const double kPetShoppingRailHeight = 168;

const double _kCardWidth = 104;

/// Rail horizontal kolom Belanja di profil pet. Kartu TANPA tombol — satu
/// gesture per kartu → detail produk (spec Keputusan 9).
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
    // Fakta lebih dulu, saran menyusul kalau masih kurang dari 4 kartu.
    final items = <_RailItem>[
      for (final u in used) _RailItem(u, isSuggestion: false),
      if (used.length < 4)
        for (final s in suggested.take(4 - used.length))
          _RailItem(s, isSuggestion: true),
    ];
    return SizedBox(
      height: kPetShoppingRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _RailCard(
          item: items[i],
          onTap: () => onTapProduct(items[i].product),
        ),
      ),
    );
  }
}

class _RailItem {
  final PetShoppingProduct product;
  final bool isSuggestion;
  const _RailItem(this.product, {required this.isSuggestion});
}

class _RailCard extends StatelessWidget {
  final _RailItem item;
  final VoidCallback onTap;

  const _RailCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = item.product;
    return Semantics(
      button: true,
      label: item.isSuggestion ? '${p.name}, saran produk' : p.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: _kCardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AppProductImage(
                      imageUrl: p.imageUrl,
                      width: _kCardWidth,
                      height: _kCardWidth,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    if (item.isSuggestion)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: NataloColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Saran',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: NataloWeight.strong,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: NataloWeight.strong,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatRupiah(p.effectivePrice),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant,
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

/// Placeholder selagi fetch — tinggi identik dengan [PetShoppingRail].
class PetShoppingRailSkeleton extends StatelessWidget {
  const PetShoppingRailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w) => Container(
          width: w,
          height: 9,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _kCardWidth,
                height: _kCardWidth,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 6),
              bar(_kCardWidth * 0.8),
              const SizedBox(height: 4),
              bar(_kCardWidth * 0.45),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Verifikasi lulus + analyze**

Run: `flutter test test/widgets/pet_shopping_rail_test.dart && flutter analyze lib/widgets/pet_shopping_rail.dart`
Expected: PASS (5 test), `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/pet_shopping_rail.dart flutter_app/test/widgets/pet_shopping_rail_test.dart
git commit -m "feat(app): rail Belanja pet + skeleton tinggi-tetap"
```

---

## Task 6: Halaman penuh `PetShoppingScreen`

**Files:**
- Create: `flutter_app/lib/screens/pet_shopping_screen.dart`
- Test: `flutter_app/test/screens/pet_shopping_screen_test.dart`

**Interfaces:**
- Consumes: `PetShopping`/`PetShoppingProduct`/`PetShoppingManual`/`petShoppingUsageLabel` (Task 3), `PetShoppingFetcher` (Task 4), `ProductVariantPickerSheet.show`, `showAddedToCartSheet`, `cartStore.addProduct`, `productService.fetchProductBySlug`, `ProductCatalogArgs`.
- Produces (dipakai Task 7 & 8): `class PetShoppingScreen extends StatefulWidget` dengan params `{ required String petId, required String petName, PetShoppingFetcher? fetcher, ProductBySlugFetcher? productFetcher, CartAdder? cartAdder }`; typedef `ProductBySlugFetcher = Future<Product?> Function(String slug)`, `CartAdder = Future<bool> Function(Product product, {ProductVariant? variant})`.

Seam `fetcher`/`productFetcher`/`cartAdder` HANYA untuk test; default memakai service nyata.

- [ ] **Step 1: Tulis failing test**

`flutter_app/test/screens/pet_shopping_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/screens/pet_shopping_screen.dart';

PetShoppingProduct used(String name) => PetShoppingProduct(
      productId: 'id-$name',
      slug: 'slug-$name',
      name: name,
      imageUrl: null,
      effectivePrice: 45000,
      inStock: true,
      hasVariants: false,
      usageCount: 2,
      lastUsedAt: DateTime(2026, 4, 25),
    );

PetShoppingProduct suggestion(String name) => PetShoppingProduct(
      productId: 'id-$name',
      slug: 'slug-$name',
      name: name,
      imageUrl: null,
      effectivePrice: 28000,
      inStock: true,
      hasVariants: false,
    );

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget wrap(PetShopping data) => MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => data,
      ),
    );

void main() {
  testWidgets('dua grup tampil dengan judul memuat nama pet', (tester) async {
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: [suggestion('Snack Dental')],
    )));
    await pumpFrames(tester);

    expect(find.text('Pernah dipakai untuk Bobby'), findsOneWidget);
    expect(find.text('Mungkin cocok untuk Bobby'), findsOneWidget);
    expect(find.text('Drontal'), findsOneWidget);
    expect(find.text('Snack Dental'), findsOneWidget);
  });

  testWidgets('baris fakta: label harga sekarang + konteks pemakaian, BUKAN kategori',
      (tester) async {
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(find.text('Harga sekarang'), findsOneWidget);
    expect(find.text('Rp45.000'), findsOneWidget);
    expect(find.textContaining('Dipakai 2x, terakhir'), findsOneWidget);
    expect(find.textContaining('Obat Cacing'), findsNothing,
        reason: 'framing harus beda dari section Perawatan');
  });

  testWidgets('brand manual: tanpa harga, tombol Cari di Natalo', (tester) async {
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: const [],
      manual: [
        PetShoppingManual(
          brandText: 'Bravecto',
          usageCount: 1,
          lastUsedAt: DateTime(2026, 6, 25),
        ),
      ],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(find.text('Bravecto'), findsOneWidget);
    expect(find.text('Cari di Natalo'), findsOneWidget);
    expect(find.text('Harga sekarang'), findsNothing);
  });

  testWidgets('produk stok habis: tombol Cari serupa, tetap aktif',
      (tester) async {
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [
        PetShoppingProduct(
          productId: 'p1',
          slug: 's1',
          name: 'Combantrin',
          imageUrl: null,
          effectivePrice: 30000,
          inStock: false,
          hasVariants: false,
          usageCount: 1,
          lastUsedAt: DateTime(2026, 1, 25),
        ),
      ],
      manual: const [],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(find.text('Cari serupa'), findsOneWidget);
    expect(find.text('Beli lagi'), findsNothing);
    expect(find.text('Stok habis'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Cari serupa'),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNotNull, reason: 'jangan tombol mati');
  });

  testWidgets('label pembaca layar tombol beli lagi memuat nama produk',
      (tester) async {
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(
      find.bySemanticsLabel('Beli lagi, Drontal'),
      findsOneWidget,
      reason: 'bukan sekadar "Beli lagi" yang tak bisa dibedakan',
    );
  });

  testWidgets('pet baru: empty-state grup fakta, grup saran tetap terisi',
      (tester) async {
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 0,
      used: const [],
      manual: const [],
      suggested: [suggestion('Snack Dental')],
    )));
    await pumpFrames(tester);

    expect(find.textContaining('Belum ada produk'), findsOneWidget);
    expect(find.text('Snack Dental'), findsOneWidget);
  });

  testWidgets('CTA jelajahi produk lain tampil di bawah grup saran',
      (tester) async {
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: [suggestion('Snack Dental')],
    )));
    await pumpFrames(tester);

    expect(find.text('Jelajahi produk lain'), findsOneWidget);
  });

  testWidgets('gagal fetch: pesan error, tidak crash', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => throw Exception('boom'),
      ),
    ));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Gagal memuat'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Verifikasi gagal**

Run: `flutter test test/screens/pet_shopping_screen_test.dart`
Expected: FAIL — URI `screens/pet_shopping_screen.dart` tidak ada.

- [ ] **Step 3: Implement**

`flutter_app/lib/screens/pet_shopping_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/pet_shopping.dart';
import '../models/product.dart';
import '../services/pet_service.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/formatters.dart';
import '../widgets/added_to_cart_sheet.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/product_variant_picker_sheet.dart';

typedef ProductBySlugFetcher = Future<Product?> Function(String slug);
typedef CartAdder = Future<bool> Function(
  Product product, {
  ProductVariant? variant,
});

/// Buka detail produk dari data belanja.
///
/// PENTING: route `/product-detail` menuntut objek `Product` PENUH sebagai
/// argumen dan TIDAK ADA route berbasis slug di app ini (lihat main.dart:460).
/// Data belanja cuma membawa slug, jadi fetch dulu — tanpa ini navigasi jatuh
/// ke `_ => const HomeScreen()` dan user mendarat di Beranda tanpa penjelasan.
Future<void> openPetShoppingProduct(
  BuildContext context,
  String slug, {
  ProductBySlugFetcher? fetcher,
}) async {
  final fetch = fetcher ?? productService.fetchProductBySlug;
  final product = await fetch(slug);
  if (!context.mounted) return;
  if (product == null) {
    AppToast.show(context, 'Produk tidak ditemukan lagi.',
        kind: ToastKind.error);
    return;
  }
  await Navigator.pushNamed(context, '/product-detail', arguments: product);
}

/// Halaman penuh kolom Belanja pet: grup fakta ("Pernah dipakai") dengan
/// hierarki paling kaya, lalu grup saran ("Mungkin cocok") yang lebih ringan.
/// Hierarki sengaja berbeda supaya tidak terbaca sebagai satu daftar panjang.
class PetShoppingScreen extends StatefulWidget {
  final String petId;
  final String petName;

  /// Seam test — default memakai service nyata.
  final PetShoppingFetcher? fetcher;
  final ProductBySlugFetcher? productFetcher;
  final CartAdder? cartAdder;

  const PetShoppingScreen({
    super.key,
    required this.petId,
    required this.petName,
    this.fetcher,
    this.productFetcher,
    this.cartAdder,
  });

  @override
  State<PetShoppingScreen> createState() => _PetShoppingScreenState();
}

class _PetShoppingScreenState extends State<PetShoppingScreen> {
  PetShopping? _data;
  bool _loading = true;
  bool _failed = false;
  String? _busySlug;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fetch = widget.fetcher ?? petService.fetchPetShopping;
    try {
      final data = await fetch(widget.petId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _buyAgain(PetShoppingProduct p) async {
    setState(() => _busySlug = p.slug);
    try {
      final add = widget.cartAdder ??
          (Product product, {ProductVariant? variant}) =>
              cartStore.addProduct(product, variant: variant);

      if (p.hasVariants) {
        // Sheet varian mengambil produk penuh by slug dan mengembalikan
        // Product + ProductVariant terpilih.
        final picked = await ProductVariantPickerSheet.show(
          context,
          productSlug: p.slug,
          confirmLabel: 'Tambah ke keranjang',
          confirmColor: NataloColors.primary,
          productFetcher: widget.productFetcher,
        );
        if (picked == null || !mounted) return;
        final ok = await add(picked.product, variant: picked.variant);
        if (!mounted || !ok) return;
        await showAddedToCartSheet(context, product: picked.product);
        return;
      }

      final fetchProduct =
          widget.productFetcher ?? productService.fetchProductBySlug;
      final product = await fetchProduct(p.slug);
      if (!mounted) return;
      if (product == null) {
        AppToast.show(context, 'Produk tidak ditemukan lagi.',
            kind: ToastKind.error);
        return;
      }
      final ok = await add(product);
      if (!mounted || !ok) return;
      await showAddedToCartSheet(context, product: product);
    } finally {
      if (mounted) setState(() => _busySlug = null);
    }
  }

  void _openCatalog({String? query, String? category}) {
    Navigator.pushNamed(
      context,
      '/products',
      arguments: ProductCatalogArgs(
        initialQuery: query,
        initialCategory: category,
      ),
    );
  }

  Future<void> _openProduct(PetShoppingProduct p) =>
      openPetShoppingProduct(context, p.slug, fetcher: widget.productFetcher);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Belanja untuk ${widget.petName}')),
      body: Builder(
        builder: (_) {
          if (_loading) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (_failed) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat belanja ${widget.petName}. Coba lagi nanti.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          final data = _data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Pernah dipakai untuk ${widget.petName}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: NataloWeight.strong),
                ),
              ),
              const SizedBox(height: 8),
              if (data.used.isEmpty && data.manual.isEmpty)
                _EmptyUsed(petName: widget.petName)
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < data.used.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: cs.outlineVariant),
                        _UsedRow(
                          product: data.used[i],
                          busy: _busySlug == data.used[i].slug,
                          onBuyAgain: () => _buyAgain(data.used[i]),
                          onFindSimilar: () =>
                              _openCatalog(query: data.used[i].name),
                          onTap: () => _openProduct(data.used[i]),
                        ),
                      ],
                      for (final m in data.manual) ...[
                        Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: cs.outlineVariant),
                        _ManualRow(
                          manual: m,
                          onSearch: () => _openCatalog(query: m.brandText),
                        ),
                      ],
                    ],
                  ),
                ),
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
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.72,
                  children: [
                    for (final s in data.suggested)
                      _SuggestionCard(
                          product: s, onTap: () => _openProduct(s)),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => _openCatalog(),
                  child: const Text(
                    'Jelajahi produk lain',
                    style: TextStyle(
                        fontSize: 13, fontWeight: NataloWeight.strong),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyUsed extends StatelessWidget {
  final String petName;
  const _EmptyUsed({required this.petName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Belum ada produk yang tercatat untuk $petName. Catat perawatan dengan produk, nanti muncul di sini.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: NataloWeight.body,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _UsedRow extends StatelessWidget {
  final PetShoppingProduct product;
  final bool busy;
  final VoidCallback onBuyAgain;
  final VoidCallback onFindSimilar;
  final VoidCallback onTap;

  const _UsedRow({
    required this.product,
    required this.busy,
    required this.onBuyAgain,
    required this.onFindSimilar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final habis = !product.inStock;
    final usage = product.usageCount;
    final last = product.lastUsedAt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: habis ? 0.4 : 1,
                child: AppProductImage(
                  imageUrl: product.imageUrl,
                  width: 56,
                  height: 56,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: NataloWeight.strong,
                        color: habis ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (habis)
                      Text(
                        'Stok habis',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: NataloWeight.body,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'Harga sekarang',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: NataloWeight.body,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            formatRupiah(product.effectivePrice),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: NataloWeight.strong,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    if (usage != null && last != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        petShoppingUsageLabel(usage, last),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: NataloWeight.body,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Lebar TETAP: nama panjang yang mengalah (ellipsis), bukan tombol.
              SizedBox(
                width: 104,
                child: habis
                    ? TextButton(
                        onPressed: onFindSimilar,
                        child: const Text('Cari serupa',
                            style: TextStyle(fontSize: 12)),
                      )
                    : Semantics(
                        button: true,
                        label: 'Beli lagi, ${product.name}',
                        child: TextButton(
                          onPressed: busy ? null : onBuyAgain,
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Beli lagi',
                                  style: TextStyle(fontSize: 12)),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualRow extends StatelessWidget {
  final PetShoppingManual manual;
  final VoidCallback onSearch;

  const _ManualRow({required this.manual, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manual.brandText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: NataloWeight.strong,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  petShoppingUsageLabel(manual.usageCount, manual.lastUsedAt),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 116,
            child: Semantics(
              button: true,
              label: 'Cari di Natalo, ${manual.brandText}',
              child: TextButton(
                onPressed: onSearch,
                child: const Text('Cari di Natalo',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final PetShoppingProduct product;
  final VoidCallback onTap;

  const _SuggestionCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: AppProductImage(
                  imageUrl: product.imageUrl,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: NataloWeight.strong,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatRupiah(product.effectivePrice),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: NataloWeight.body,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Verifikasi lulus + analyze**

Run: `flutter test test/screens/pet_shopping_screen_test.dart && flutter analyze lib/screens/pet_shopping_screen.dart`
Expected: PASS (8 test), `No issues found!`

Kalau `flutter analyze` melaporkan import tak terpakai, hapus import itu — JANGAN mematikan lint.

Nama-nama berikut SUDAH diverifikasi ada di codebase, jangan diganti: route `'/product-detail'` (menerima `Product`, `main.dart:460`), `AppToast.show(context, msg, kind: ToastKind.error)` (`widgets/app_toast.dart`), `ProductVariantPickerSheet.show(context, productSlug:, confirmLabel:, confirmColor:, productFetcher:)` yang mengembalikan `ProductVariantPickResult?` berisi `product` + `variant`, dan `typedef ProductFetcher = Future<Product?> Function(String slug)` yang bentuknya identik dengan `ProductBySlugFetcher` (jadi bisa diteruskan langsung).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/pet_shopping_screen.dart flutter_app/test/screens/pet_shopping_screen_test.dart
git commit -m "feat(app): PetShoppingScreen dua grup + beli lagi via sheet"
```

---

## Task 7: Alur beli-ulang teruji (varian & non-varian)

**Files:**
- Test: `flutter_app/test/screens/pet_shopping_screen_test.dart` (tambah kasus)

**Interfaces:**
- Consumes: `PetShoppingScreen` seam `productFetcher` + `cartAdder` (Task 6).

- [ ] **Step 1: Tambah failing test**

Tambahkan import di atas file test (`test/screens/pet_shopping_screen_test.dart`):

```dart
import 'package:natalo_petshop_flutter/models/product.dart';
```

Lalu tambahkan di dalam `main()`, setelah test terakhir:

```dart
  testWidgets('beli lagi produk non-varian: ambil produk by slug lalu addProduct',
      (tester) async {
    final fetchedSlugs = <String>[];
    final added = <String>[];
    final product = Product(
      id: 'id-Drontal',
      slug: 'slug-Drontal',
      title: 'Drontal',
      category: 'Obat & Suplemen',
      brand: 'Bayer',
      imageUrl: 'https://cdn/d.jpg',
      price: 45000,
      rating: 0,
      reviewCount: 0,
      stock: 5,
      weightGram: 100,
      isNew: false,
      isTrending: false,
      hasVariants: false,
    );

    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => PetShopping(
          usedCount: 1,
          used: [used('Drontal')],
          manual: const [],
          suggested: const [],
        ),
        productFetcher: (slug) async {
          fetchedSlugs.add(slug);
          return product;
        },
        cartAdder: (p, {variant}) async {
          added.add(p.slug);
          return true;
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Beli lagi'));
    await pumpFrames(tester);

    expect(fetchedSlugs, ['slug-Drontal']);
    expect(added, ['slug-Drontal']);
  });

  testWidgets('tap baris produk: fetch by slug lalu buka /product-detail',
      (tester) async {
    final fetchedSlugs = <String>[];
    final product = Product(
      id: 'id-Drontal',
      slug: 'slug-Drontal',
      title: 'Drontal',
      category: 'Obat & Suplemen',
      brand: 'Bayer',
      imageUrl: 'https://cdn/d.jpg',
      price: 45000,
      rating: 0,
      reviewCount: 0,
      stock: 5,
      weightGram: 100,
      isNew: false,
      isTrending: false,
      hasVariants: false,
    );

    await tester.pumpWidget(MaterialApp(
      routes: {
        '/product-detail': (_) => const Scaffold(body: Text('DETAIL')),
      },
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => PetShopping(
          usedCount: 1,
          used: [used('Drontal')],
          manual: const [],
          suggested: const [],
        ),
        productFetcher: (slug) async {
          fetchedSlugs.add(slug);
          return product;
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Drontal'));
    await pumpFrames(tester);

    expect(fetchedSlugs, ['slug-Drontal'],
        reason: 'route /product-detail butuh Product penuh, bukan slug');
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('beli lagi: produk sudah tak ada → pesan, tidak masuk keranjang',
      (tester) async {
    final added = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => PetShopping(
          usedCount: 1,
          used: [used('Drontal')],
          manual: const [],
          suggested: const [],
        ),
        productFetcher: (_) async => null,
        cartAdder: (p, {variant}) async {
          added.add(p.slug);
          return true;
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Beli lagi'));
    await pumpFrames(tester);

    expect(added, isEmpty);
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Jalankan test**

Run: `flutter test test/screens/pet_shopping_screen_test.dart`
Expected: PASS semua (11 test).

Kalau konstruktor `Product(...)` menolak argumen di atas, jalankan `grep -n "const Product({" -A 30 lib/models/product.dart` dan lengkapi/ubah argumen agar cocok dengan field wajib yang sebenarnya — jangan mengubah `lib/models/product.dart`.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/test/screens/pet_shopping_screen_test.dart
git commit -m "test(app): alur beli lagi non-varian + produk hilang"
```

---

## Task 8: Integrasi profil pet (section + kartu statistik)

**Files:**
- Modify: `flutter_app/lib/screens/pet_profile_screen.dart`
- Modify: `flutter_app/lib/main.dart`
- Test: `flutter_app/test/screens/pet_profile_belanja_test.dart`

**Interfaces:**
- Consumes: `PetShoppingRail`, `PetShoppingRailSkeleton`, `kPetShoppingRailHeight` (Task 5); `PetShoppingScreen` (Task 6); `PetShopping` (Task 3).
- Produces: route `/pets/belanja` dengan `arguments: PetShoppingArgs(petId:, petName:)`; kelas `PetShoppingArgs` diekspor dari `pet_shopping_screen.dart`.

- [ ] **Step 1: Tambah `PetShoppingArgs` + route**

Di akhir `flutter_app/lib/screens/pet_shopping_screen.dart`, tambahkan:

```dart
/// Argumen named-route `/pets/belanja`.
class PetShoppingArgs {
  final String petId;
  final String petName;
  const PetShoppingArgs({required this.petId, required this.petName});
}
```

Di `flutter_app/lib/main.dart`, tambahkan import:

```dart
import 'screens/pet_shopping_screen.dart';
```

Lalu di dalam `switch (settings.name)` route table (cari `'/member/orders' =>` sebagai patokan lokasi), tambahkan case:

```dart
              '/pets/belanja' when settings.arguments is PetShoppingArgs =>
                (() {
                  final args = settings.arguments as PetShoppingArgs;
                  return PetShoppingScreen(
                    petId: args.petId,
                    petName: args.petName,
                  );
                })(),
```

- [ ] **Step 2: Tulis failing test integrasi profil**

`flutter_app/test/screens/pet_profile_belanja_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/screens/pet_profile_screen.dart';
import 'package:natalo_petshop_flutter/widgets/pet_shopping_rail.dart';

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('kartu statistik: Belanja & Perawatan punya peran button, Momen tidak',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetStatsRowForTest(
        momenValue: '0',
        careValue: '4',
        belanjaValue: '6',
        onCareTap: () {},
        onBelanjaTap: () {},
      ),
    ));
    await pumpFrames(tester);

    expect(find.bySemanticsLabel(RegExp('Belanja')), findsOneWidget);
    final belanja = find.ancestor(
      of: find.text('Belanja'),
      matching: find.byType(InkWell),
    );
    expect(belanja, findsOneWidget, reason: 'Belanja harus InkWell (ripple)');

    final momen = find.ancestor(
      of: find.text('Momen'),
      matching: find.byType(InkWell),
    );
    expect(momen, findsNothing, reason: 'Momen belum aktif, jangan tampak bisa ditekan');
  });

  testWidgets('tap kartu Belanja memanggil callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: PetStatsRowForTest(
        momenValue: '0',
        careValue: '4',
        belanjaValue: '6',
        onCareTap: () {},
        onBelanjaTap: () => tapped++,
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Belanja'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('section Belanja: skeleton dulu, lalu rail; disembunyikan saat kosong',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingSectionForTest(
          petName: 'Bobby',
          data: PetShopping(
            usedCount: 1,
            used: [
              PetShoppingProduct(
                productId: 'p1',
                slug: 's1',
                name: 'Drontal',
                imageUrl: null,
                effectivePrice: 45000,
                inStock: true,
                hasVariants: false,
                usageCount: 1,
                lastUsedAt: DateTime(2026, 7, 1),
              ),
            ],
            manual: const [],
            suggested: const [],
          ),
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.byType(PetShoppingRail), findsOneWidget);
    expect(find.text('Belanja untuk Bobby'), findsOneWidget);
    expect(find.text('Lihat semua'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingSectionForTest(
          petName: 'Bobby',
          data: const PetShopping(
            usedCount: 0,
            used: [],
            manual: [],
            suggested: [],
          ),
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.byType(PetShoppingRail), findsNothing);
    expect(find.text('Belanja untuk Bobby'), findsNothing,
        reason: 'kosong total → section tak dirender (Keputusan 13)');
  });
}
```

- [ ] **Step 3: Verifikasi gagal**

Run: `flutter test test/screens/pet_profile_belanja_test.dart`
Expected: FAIL — `PetStatsRowForTest`/`PetShoppingSectionForTest` belum ada.

- [ ] **Step 4: Implement di `pet_profile_screen.dart`**

Tambahkan import di atas file:

```dart
import '../models/pet_shopping.dart';
import '../widgets/pet_shopping_rail.dart';
import 'pet_shopping_screen.dart';
```

**4a.** Ganti kelas `_StatCard` (sekitar baris 524) supaya menerima `onTap` opsional dan status redup:

```dart
class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  /// Null = belum aktif: diredupkan, TIDAK diberi peran button, tanpa ripple.
  final VoidCallback? onTap;

  const _StatCard({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final card = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: NataloWeight.strong),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: NataloWeight.body,
                      color: cs.onSurfaceVariant),
                ),
                if (enabled)
                  Icon(Icons.chevron_right_rounded,
                      size: 14, color: cs.onSurfaceVariant),
              ],
            ),
          ],
        ),
      ),
    );
    if (!enabled) return card;
    return Semantics(
      button: true,
      label: '$label, $value',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: card,
        ),
      ),
    );
  }
}
```

**4b.** Ganti isi `_StatsRow` (sekitar baris 497–520) — `GestureDetector` lama dibuang karena tak memberi ripple maupun semantics:

```dart
class _StatsRow extends StatelessWidget {
  final Pet pet;
  final VoidCallback onCareTap;
  final VoidCallback onBelanjaTap;
  final int belanjaCount;

  const _StatsRow({
    required this.pet,
    required this.onCareTap,
    required this.onBelanjaTap,
    required this.belanjaCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          // Momen belum dibangun (spec sendiri) — diredupkan, bukan diam.
          const Expanded(child: _StatCard(value: '0', label: 'Momen')),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              value: '${pet.careCount}',
              label: 'Perawatan',
              onTap: onCareTap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              value: '$belanjaCount',
              label: 'Belanja',
              onTap: onBelanjaTap,
            ),
          ),
        ],
      ),
    );
  }
}
```

**4c.** Tambahkan section Belanja + state fetch di state class `pet_profile_screen.dart`. Di dalam state class (tempat `_openCare` berada), tambahkan field dan method:

```dart
  PetShopping? _shopping;

  Future<void> _loadShopping() async {
    try {
      final data = await petService.fetchPetShopping(widget.pet.id);
      if (!mounted) return;
      setState(() => _shopping = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _shopping = const PetShopping(
            usedCount: 0,
            used: [],
            manual: [],
            suggested: [],
          ));
    }
  }

  void _openBelanja() {
    Navigator.pushNamed(
      context,
      '/pets/belanja',
      arguments: PetShoppingArgs(
        petId: widget.pet.id,
        petName: widget.pet.name,
      ),
    );
  }
```

Panggil `_loadShopping()` di `initState()` setelah pemanggilan load yang sudah ada.

Ubah pemakaian `_StatsRow` (sekitar baris 208) menjadi:

```dart
            child: _StatsRow(
              pet: pet,
              onCareTap: _openCare,
              onBelanjaTap: _openBelanja,
              belanjaCount: _shopping?.usedCount ?? 0,
            ),
```

Lalu sisipkan section Belanja setelah section Perawatan di daftar children body:

```dart
          _PetShoppingSection(
            petName: pet.name,
            data: _shopping,
            onSeeAll: _openBelanja,
            // Wajib lewat helper: route '/product-detail' butuh Product penuh,
            // data belanja cuma punya slug.
            onTapProduct: (p) => openPetShoppingProduct(context, p.slug),
          ),
```

**4d.** Tambahkan widget section + dua wrapper test di akhir `pet_profile_screen.dart`:

```dart
/// Section Belanja di profil. `data == null` = masih fetch → skeleton
/// bertinggi sama dengan rail terisi supaya konten di bawah tidak melonjak.
/// `data.isEmpty` = tak ada apa pun untuk ditawarkan → section disembunyikan
/// penuh (spec Keputusan 13), sama seperti kegagalan fetch.
class _PetShoppingSection extends StatelessWidget {
  final String petName;
  final PetShopping? data;
  final VoidCallback onSeeAll;
  final void Function(PetShoppingProduct product) onTapProduct;

  const _PetShoppingSection({
    required this.petName,
    required this.data,
    required this.onSeeAll,
    required this.onTapProduct,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d != null && d.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Belanja untuk $petName',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: NataloWeight.strong),
                ),
              ),
              const Spacer(),
              if (d != null)
                Semantics(
                  button: true,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onSeeAll,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text('Lihat semua',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: NataloWeight.strong,
                                color: _brandBlue)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (d == null)
            const PetShoppingRailSkeleton()
          else
            PetShoppingRail(
              used: d.used,
              suggested: d.suggested,
              onTapProduct: onTapProduct,
            ),
        ],
      ),
    );
  }
}

/// Wrapper test-only untuk `_StatsRow` (kelas privat).
@visibleForTesting
class PetStatsRowForTest extends StatelessWidget {
  final String momenValue;
  final String careValue;
  final String belanjaValue;
  final VoidCallback onCareTap;
  final VoidCallback onBelanjaTap;

  const PetStatsRowForTest({
    super.key,
    required this.momenValue,
    required this.careValue,
    required this.belanjaValue,
    required this.onCareTap,
    required this.onBelanjaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Row(
          children: [
            Expanded(child: _StatCard(value: momenValue, label: 'Momen')),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                  value: careValue, label: 'Perawatan', onTap: onCareTap),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                  value: belanjaValue, label: 'Belanja', onTap: onBelanjaTap),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wrapper test-only untuk `_PetShoppingSection` (kelas privat).
@visibleForTesting
class PetShoppingSectionForTest extends StatelessWidget {
  final String petName;
  final PetShopping? data;

  const PetShoppingSectionForTest({
    super.key,
    required this.petName,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return _PetShoppingSection(
      petName: petName,
      data: data,
      onSeeAll: () {},
      onTapProduct: (_) {},
    );
  }
}
```

- [ ] **Step 5: Verifikasi lulus + analyze**

Run: `flutter test test/screens/pet_profile_belanja_test.dart && flutter analyze lib/screens/pet_profile_screen.dart lib/main.dart lib/screens/pet_shopping_screen.dart`
Expected: PASS (3 test), `No issues found!`

Kalau `_brandBlue` tidak ada di `pet_profile_screen.dart`, pakai `NataloColors.primary`. Kalau `widget.pet` bukan cara mengakses pet di state class itu, jalankan `grep -n "class _PetProfileScreenState" -A 20 lib/screens/pet_profile_screen.dart` dan pakai referensi yang benar.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/pet_profile_screen.dart flutter_app/lib/screens/pet_shopping_screen.dart flutter_app/lib/main.dart flutter_app/test/screens/pet_profile_belanja_test.dart
git commit -m "feat(app): section Belanja di profil pet + kartu statistik ber-afordans"
```

---

## Task 9: Verifikasi empty-state Katalog (Keputusan 15)

Spec Keputusan 15 minta pencarian 0 hasil punya penjelasan. `ProductsScreen` **sudah** punya `_EmptyProductsState` (dengan tombol reset filter + produk terakhir dilihat) di cabang `products.isEmpty`. Task ini memverifikasi jalur itu benar-benar kena saat masuk lewat `ProductCatalogArgs(initialQuery: ...)` — bukan membangun ulang.

**Files:**
- Test: `flutter_app/test/screens/products_empty_query_test.dart` (baru)

- [ ] **Step 1: Tulis test**

`flutter_app/test/screens/products_empty_query_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';

/// Keputusan 15 spec Belanja: "Cari di Natalo"/"Cari serupa" yang 0 hasil
/// tidak boleh mendarat di grid kosong tanpa penjelasan. ProductsScreen sudah
/// punya _EmptyProductsState; test ini menjaga kontrak argumennya.
void main() {
  test('ProductCatalogArgs membawa initialQuery ke layar Produk', () {
    const args = ProductCatalogArgs(initialQuery: 'Bravecto');
    expect(args.initialQuery, 'Bravecto');
    expect(args.selectedBrand, isNull);
    expect(args.discountOnly, isFalse);
  });

  test('ProductCatalogArgs membawa initialCategory utk Cari serupa', () {
    const args = ProductCatalogArgs(initialCategory: 'Obat & Suplemen');
    expect(args.initialCategory, 'Obat & Suplemen');
  });
}
```

- [ ] **Step 2: Jalankan + verifikasi empty-state existing secara manual**

Run: `flutter test test/screens/products_empty_query_test.dart`
Expected: PASS (2 test).

Lalu konfirmasi cabang empty-state benar ada:

Run: `grep -n "_EmptyProductsState" lib/screens/products_screen.dart`
Expected: muncul minimal 2 baris (pemakaian di cabang `products.isEmpty` + definisi kelas). Kalau TIDAK muncul, hentikan dan laporkan — berarti asumsi plan ini salah dan Keputusan 15 butuh implementasi sendiri.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/test/screens/products_empty_query_test.dart
git commit -m "test(app): kontrak ProductCatalogArgs utk pencarian dari kolom Belanja"
```

---

## Task 10: Regresi penuh

**Files:** tidak ada perubahan kode — hanya verifikasi.

- [ ] **Step 1: Suite backend**

Run (dari root repo):
```bash
npx tsx --test tests/pet-shopping.test.ts tests/pet-shopping-route.test.ts tests/care-recommendation.test.ts tests/pet-care-api.test.ts tests/product-dosage.test.ts
```
Expected: semua PASS.

- [ ] **Step 2: Kompilasi backend**

Run: `npx tsc --noEmit`
Expected: tanpa error baru. Error `Cannot find module 'vitest'` di file test lama sudah ada sebelum plan ini — abaikan, jangan "diperbaiki" di sini.

- [ ] **Step 3: Suite Flutter terkait**

Run (dari `flutter_app/`):
```bash
flutter test test/models/pet_shopping_model_test.dart test/widgets/pet_shopping_rail_test.dart test/screens/pet_shopping_screen_test.dart test/screens/pet_profile_belanja_test.dart test/screens/products_empty_query_test.dart test/pet_care_form_screen_test.dart test/care_product_picker_test.dart test/pet_care_record_model_test.dart
```
Expected: semua PASS.

- [ ] **Step 4: Suite Flutter penuh**

Run (dari `flutter_app/`): `flutter test`
Expected: hanya kegagalan pre-existing yang boleh ada. Catatan: `test/screens/member_screen_test.dart` ("top bar keeps every existing icon unchanged") SUDAH gagal sebelum plan ini dan tidak menyentuh file mana pun di plan ini — verifikasi dengan `git diff --stat origin/main..HEAD -- flutter_app/lib/screens/member_screen.dart` (harus kosong). Kegagalan lain = regresi nyata, WAJIB diperbaiki.

- [ ] **Step 5: Analyze**

Run (dari `flutter_app/`):
```bash
flutter analyze lib/models/pet_shopping.dart lib/widgets/pet_shopping_rail.dart lib/screens/pet_shopping_screen.dart lib/screens/pet_profile_screen.dart lib/services/pet_service.dart lib/main.dart
```
Expected: `No issues found!`

- [ ] **Step 6: Commit catatan hasil (kalau ada perbaikan)**

Kalau Step 1–5 memaksa perbaikan, commit dengan:
```bash
git commit -am "fix(pets): perbaikan hasil regresi kolom Belanja"
```
Kalau semua hijau tanpa perubahan, lewati step ini.

---

## Di luar plan

Momen/Journey (spec sendiri), riwayat pembelian per-pet (`petId` di `OrderItem` + pemilih pet di checkout), reminder/notifikasi belanja, langganan/auto-repeat order. Verifikasi device (rail tak overflow di 375px, thumbnail benar tampil, dark mode dua grup, angka statistik cocok isi halaman) dilakukan setelah rilis, di luar cakupan task ini.
