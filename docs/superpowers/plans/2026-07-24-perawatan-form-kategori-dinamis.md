# Perawatan Form Dinamis per Kategori + Rekomendasi Obat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ubah form "Catat Perawatan" agar kolomnya menyesuaikan kategori, catat berat badan pet lewat form obat, dan sambungkan Obat Cacing/Kutu ke katalog Natalo dengan rekomendasi produk + saran dosis dari data yang diisi admin.

**Architecture:** Tiga lapis. (1) Backend Next.js/Prisma: kolom baru nullable di `PetCareRecord`, `Product`, `Pet` + tabel `PetWeightLog`, endpoint rekomendasi produk, dan fungsi ekstraksi dosis AI di admin. (2) Logika murni di `lib/product-dosage.ts` (pemilihan/pengurutan produk, pencocokan rentang berat) diuji TDD. (3) Flutter: model diperluas, `pet_service` dapat method baru, form jadi dinamis per kategori dengan widget pemilih produk + kartu dosis. Semua field baru opsional → backward-compatible dengan data Tahap 3 yang sudah ada.

**Tech Stack:** Next.js (App Router) + Prisma + PostgreSQL (Neon), `@anthropic-ai/sdk` (model `claude-sonnet-4-5`), Flutter/Dart, Vitest (backend), flutter_test.

## Global Constraints

- Semua field baru **opsional/nullable** — record & produk lama harus tetap valid tanpa migrasi data. Backward-compatible dengan Tahap 3 ([spec Tahap 3](../specs/2026-07-24-anabulku-tahap3-perawatan-design.md)).
- **Tidak ada pemanggilan AI dari app Flutter.** AI hanya di admin web (ekstraksi dosis), hasil disimpan ke produk, app cuma membaca.
- Data dosis yang tampil ke user **selalu hasil yang sudah disetujui admin** — ekstraksi AI tidak pernah auto-simpan.
- Istilah label generik untuk tempat medis = **"Dokter Hewan"**, bukan "Klinik".
- Label kategori kelima **tetap "Periksa Dokter"** (tidak diganti).
- Model AI: `claude-sonnet-4-5` (samakan dengan `lib/ai/generate-product-description.ts`). Key dari `process.env.ANTHROPIC_API_KEY`.
- `kPetTypes` (sumber kebenaran spesies) = `['Kucing','Anjing','Ikan','Burung','Reptil','Lainnya']` — WAJIB sinkron Flutter (`flutter_app/lib/models/pet.dart`) ↔ backend.
- **GOTCHA stok varian:** produk dengan varian menyimpan stok di `ProductVariant.stock` (base `Product.stock` = 0). "Stok tersedia" = `Product.stock > 0` ATAU ada varian `stock > 0`. Harga tampil = harga varian termurah bila ada varian, else `Product.price`.
- **GOTCHA fillColor global (Flutter):** TextField di atas permukaan berwarna → `filled:false` + fill transparan (lihat memory `global-input-theme-white-fill-gotcha`).
- Kategori care valid = `grooming | deworm | flea | vaccine | vet | other` (`CARE_CATEGORIES` di `lib/pet-care-api.ts`).
- Commit setiap task selesai. `bun test` (backend) & `flutter analyze` + `flutter test` (app) hijau sebelum commit task yang menyentuh masing-masing sisi.

---

## File Structure

**Backend (Next.js / Prisma):**
- `prisma/schema.prisma` — modify: `PetCareRecord` (+7 kolom), `Product` (+3 kolom), `Pet` (+`weightKg`), model baru `PetWeightLog`.
- `lib/pet-care-api.ts` — modify: perluas `validateCarePayload` + tipe payload.
- `lib/product-dosage.ts` — create: tipe `DosageRule`, `pickDosageForWeight()`, `effectiveStock()`, `effectivePrice()`, `sortRecommendedProducts()`. Logika murni, tanpa I/O.
- `lib/ai/extract-dosage-rules.ts` — create: fungsi AI ekstraksi dosis terstruktur.
- `app/api/products/care-recommendation/route.ts` — create: endpoint rekomendasi produk.
- `app/api/member/pets/[id]/care/route.ts` — modify: POST thread field baru + sync berat.
- `app/api/admin/products/[id]/extract-dosage/route.ts` — create: endpoint admin panggil ekstraksi AI (draft, tak simpan).
- Admin product form (lihat Task 11) — modify: UI kategori obat + tombol ekstrak dosis.

**Backend tests:**
- `tests/product-dosage.test.ts`, `tests/pet-care-api.test.ts` (extend), `tests/care-recommendation.test.ts`.

**Flutter:**
- `flutter_app/lib/models/pet.dart` — modify: +`weightKg`.
- `flutter_app/lib/models/pet_care_record.dart` — modify: +field baru + `CareProduct`/`DosageRule`.
- `flutter_app/lib/services/pet_service.dart` — modify: `createCare` diperluas + `fetchCareRecommendation`.
- `flutter_app/lib/screens/pet_care_form_screen.dart` — modify: form dinamis per kategori.
- `flutter_app/lib/widgets/care_product_picker.dart` — create: widget pemilih produk + kartu dosis.

**Flutter tests:**
- `flutter_app/test/pet_care_form_screen_test.dart` (extend/create), `flutter_app/test/care_product_picker_test.dart`.

---

## Task 1: Prisma schema — kolom & tabel baru

**Files:**
- Modify: `prisma/schema.prisma` (model `PetCareRecord` ~1136, `Product` ~393, `Pet` model, +model baru `PetWeightLog`)

**Interfaces:**
- Produces: kolom DB `PetCareRecord.productId/brandText/dosageNote/weightKg/place/vaccineName/complaint`, `Product.careCategory/targetSpecies/dosageRules`, `Pet.weightKg`, tabel `PetWeightLog(id, petId, weightKg, recordedAt, careRecordId?)`.

- [ ] **Step 1: Tambah kolom ke `PetCareRecord`**

Di `model PetCareRecord`, sebelum `createdAt`:

```prisma
  productId   String?
  brandText   String?
  dosageNote  String?
  weightKg    Float?
  place       String?
  vaccineName String?
  complaint   String?
```

- [ ] **Step 2: Tambah kolom ke `Product`**

Di `model Product`, setelah `weightGram`:

```prisma
  careCategory  String?  // 'deworm' | 'flea' | null
  targetSpecies String[] @default([]) // subset kPetTypes; [] = semua spesies
  dosageRules   Json?    // DosageRule[] — lihat lib/product-dosage.ts
```

- [ ] **Step 3: Tambah `weightKg` ke `Pet` + relasi weight log**

Di `model Pet`, tambah field (jaga agar tidak bentrok dengan field lain):

```prisma
  weightKg   Float?
  weightLogs PetWeightLog[]
```

- [ ] **Step 4: Tambah model `PetWeightLog`**

Setelah `model PetCareRecord`:

```prisma
model PetWeightLog {
  id           String   @id @default(cuid())
  petId        String
  pet          Pet      @relation(fields: [petId], references: [id], onDelete: Cascade)
  weightKg     Float
  recordedAt   DateTime @default(now())
  careRecordId String?  // asal record perawatan (opsional)

  @@index([petId, recordedAt])
}
```

- [ ] **Step 5: Buat migration**

Run: `bunx prisma migrate dev --name pet_care_dynamic_fields`
Expected: migration baru dibuat di `prisma/migrations/`, `bunx prisma generate` sukses, tidak ada error kolom.

- [ ] **Step 6: Commit**

```bash
git add prisma/schema.prisma prisma/migrations
git commit -m "feat(db): add pet care dynamic fields, product dosage columns, pet weight log"
```

---

## Task 2: `lib/product-dosage.ts` — pencocokan dosis (pure logic, TDD)

**Files:**
- Create: `lib/product-dosage.ts`
- Test: `tests/product-dosage.test.ts`

**Interfaces:**
- Produces:
  - `type DosageRule = { minKg: number; maxKg: number | null; instruction: string }`
  - `pickDosageForWeight(rules: DosageRule[] | null | undefined, weightKg: number | null | undefined): DosageRule | null`
  - `parseDosageRules(raw: unknown): DosageRule[]` — validasi JSON dari DB/AI jadi array bersih (buang entri invalid).

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest";
import { pickDosageForWeight, parseDosageRules } from "@/lib/product-dosage";

describe("pickDosageForWeight", () => {
  const rules = [
    { minKg: 0, maxKg: 5, instruction: "1/2 tablet" },
    { minKg: 5, maxKg: 10, instruction: "1 tablet" },
    { minKg: 10, maxKg: null, instruction: "2 tablet" },
  ];
  it("picks the rule whose range includes the weight (upper bound exclusive)", () => {
    expect(pickDosageForWeight(rules, 4.5)?.instruction).toBe("1/2 tablet");
    expect(pickDosageForWeight(rules, 5)?.instruction).toBe("1 tablet");
    expect(pickDosageForWeight(rules, 25)?.instruction).toBe("2 tablet");
  });
  it("returns null when weight or rules missing", () => {
    expect(pickDosageForWeight(rules, null)).toBeNull();
    expect(pickDosageForWeight(null, 4.5)).toBeNull();
    expect(pickDosageForWeight([], 4.5)).toBeNull();
  });
  it("returns null when no range matches", () => {
    expect(pickDosageForWeight([{ minKg: 10, maxKg: 20, instruction: "x" }], 4)).toBeNull();
  });
});

describe("parseDosageRules", () => {
  it("keeps valid entries and drops malformed ones", () => {
    const raw = [
      { minKg: 0, maxKg: 5, instruction: "a" },
      { minKg: "bad", maxKg: 5, instruction: "b" },
      { minKg: 5, maxKg: null, instruction: "" },
      { minKg: 5, maxKg: null, instruction: "c" },
    ];
    const out = parseDosageRules(raw);
    expect(out).toEqual([
      { minKg: 0, maxKg: 5, instruction: "a" },
      { minKg: 5, maxKg: null, instruction: "c" },
    ]);
  });
  it("returns [] for non-array", () => {
    expect(parseDosageRules(null)).toEqual([]);
    expect(parseDosageRules("nope")).toEqual([]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test tests/product-dosage.test.ts`
Expected: FAIL — module `@/lib/product-dosage` not found.

- [ ] **Step 3: Write minimal implementation**

```typescript
export type DosageRule = {
  minKg: number;
  maxKg: number | null;
  instruction: string;
};

export function parseDosageRules(raw: unknown): DosageRule[] {
  if (!Array.isArray(raw)) return [];
  const out: DosageRule[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const { minKg, maxKg, instruction } = item as Record<string, unknown>;
    if (typeof minKg !== "number" || Number.isNaN(minKg)) continue;
    if (!(maxKg === null || (typeof maxKg === "number" && !Number.isNaN(maxKg)))) continue;
    if (typeof instruction !== "string" || !instruction.trim()) continue;
    out.push({ minKg, maxKg: maxKg as number | null, instruction: instruction.trim() });
  }
  return out;
}

export function pickDosageForWeight(
  rules: DosageRule[] | null | undefined,
  weightKg: number | null | undefined,
): DosageRule | null {
  if (!rules || rules.length === 0) return null;
  if (weightKg === null || weightKg === undefined || Number.isNaN(weightKg)) return null;
  for (const r of rules) {
    const underMax = r.maxKg === null || weightKg < r.maxKg;
    if (weightKg >= r.minKg && underMax) return r;
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test tests/product-dosage.test.ts`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add lib/product-dosage.ts tests/product-dosage.test.ts
git commit -m "feat(dosage): dosage-rule parsing and weight matching"
```

---

## Task 3: `lib/product-dosage.ts` — pengurutan rekomendasi (pure logic, TDD)

**Files:**
- Modify: `lib/product-dosage.ts`
- Test: `tests/product-dosage.test.ts` (extend)

**Interfaces:**
- Consumes: `DosageRule`, `parseDosageRules` (Task 2).
- Produces:
  - `type RecoProductInput = { id: string; name: string; price: number; baseStock: number; variantStocks: number[]; variantPrices: number[]; targetSpecies: string[]; dosageRules: DosageRule[] }`
  - `effectiveStock(p): number`
  - `effectivePrice(p): number`
  - `matchesRecommendation(p, species, weightKg): boolean`
  - `sortRecommendedProducts(products, species, weightKg): RecoProductInput[]` — filter yang cocok, urut: in-stock dulu, lalu harga efektif termurah, lalu nama.

- [ ] **Step 1: Write the failing test**

```typescript
import { sortRecommendedProducts, effectiveStock, effectivePrice } from "@/lib/product-dosage";

const base = (over: Partial<any> = {}) => ({
  id: "p", name: "P", price: 50000, baseStock: 0, variantStocks: [], variantPrices: [],
  targetSpecies: ["Anjing"], dosageRules: [{ minKg: 0, maxKg: 10, instruction: "1/2 tablet" }],
  ...over,
});

describe("effectiveStock/effectivePrice", () => {
  it("uses variant totals when variants exist", () => {
    expect(effectiveStock(base({ baseStock: 0, variantStocks: [0, 3] }))).toBe(3);
    expect(effectivePrice(base({ price: 50000, variantPrices: [15000, 20000] }))).toBe(15000);
  });
  it("falls back to base when no variants", () => {
    expect(effectiveStock(base({ baseStock: 7 }))).toBe(7);
    expect(effectivePrice(base({ price: 45000 }))).toBe(45000);
  });
});

describe("sortRecommendedProducts", () => {
  it("filters by species+weight and orders in-stock then cheapest", () => {
    const products = [
      base({ id: "cat", targetSpecies: ["Kucing"] }),                 // wrong species
      base({ id: "heavy", dosageRules: [{ minKg: 20, maxKg: null, instruction: "x" }] }), // weight out of range
      base({ id: "pricey", price: 68000, baseStock: 5 }),
      base({ id: "cheap-oos", price: 15000, baseStock: 0 }),          // matches but out of stock
      base({ id: "cheap-in", price: 45000, baseStock: 2 }),
    ];
    const out = sortRecommendedProducts(products, "Anjing", 4.5).map((p) => p.id);
    expect(out).toEqual(["cheap-in", "pricey", "cheap-oos"]);
  });
  it("treats empty targetSpecies as matching any species", () => {
    const out = sortRecommendedProducts([base({ id: "any", targetSpecies: [] })], "Reptil", 4.5);
    expect(out.map((p) => p.id)).toEqual(["any"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test tests/product-dosage.test.ts`
Expected: FAIL — `sortRecommendedProducts` is not a function.

- [ ] **Step 3: Write minimal implementation (append to `lib/product-dosage.ts`)**

```typescript
export type RecoProductInput = {
  id: string;
  name: string;
  price: number;
  baseStock: number;
  variantStocks: number[];
  variantPrices: number[];
  targetSpecies: string[];
  dosageRules: DosageRule[];
};

export function effectiveStock(p: RecoProductInput): number {
  if (p.variantStocks.length > 0) return p.variantStocks.reduce((a, b) => a + b, 0);
  return p.baseStock;
}

export function effectivePrice(p: RecoProductInput): number {
  if (p.variantPrices.length > 0) return Math.min(...p.variantPrices);
  return p.price;
}

export function matchesRecommendation(
  p: RecoProductInput,
  species: string,
  weightKg: number,
): boolean {
  const speciesOk = p.targetSpecies.length === 0 || p.targetSpecies.includes(species);
  if (!speciesOk) return false;
  return pickDosageForWeight(p.dosageRules, weightKg) !== null;
}

export function sortRecommendedProducts(
  products: RecoProductInput[],
  species: string,
  weightKg: number,
): RecoProductInput[] {
  return products
    .filter((p) => matchesRecommendation(p, species, weightKg))
    .sort((a, b) => {
      const aIn = effectiveStock(a) > 0 ? 1 : 0;
      const bIn = effectiveStock(b) > 0 ? 1 : 0;
      if (aIn !== bIn) return bIn - aIn;
      const pd = effectivePrice(a) - effectivePrice(b);
      if (pd !== 0) return pd;
      return a.name.localeCompare(b.name);
    });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test tests/product-dosage.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/product-dosage.ts tests/product-dosage.test.ts
git commit -m "feat(dosage): recommendation filtering and ordering"
```

---

## Task 4: Perluas `validateCarePayload`

**Files:**
- Modify: `lib/pet-care-api.ts:12-64`
- Test: `tests/pet-care-api.test.ts` (extend)

**Interfaces:**
- Consumes: `CARE_CATEGORIES` (existing).
- Produces: `ValidatedCarePayload` bertambah `productId/brandText/dosageNote/weightKg/place/vaccineName/complaint` (semua `| null`). Existing fields tak berubah.

- [ ] **Step 1: Write the failing test (append to `tests/pet-care-api.test.ts`)**

```typescript
import { validateCarePayload } from "@/lib/pet-care-api";

describe("validateCarePayload — new optional fields", () => {
  const okBase = { category: "deworm", doneAt: "2026-07-24T00:00:00.000Z" };

  it("accepts and normalizes new fields", () => {
    const r = validateCarePayload({
      ...okBase, weightKg: 4.5, productId: "prod1", place: "  Natalo  ",
      vaccineName: "", complaint: "  Gatal  ",
    });
    expect("data" in r).toBe(true);
    if ("data" in r) {
      expect(r.data.weightKg).toBe(4.5);
      expect(r.data.productId).toBe("prod1");
      expect(r.data.place).toBe("Natalo");        // trimmed
      expect(r.data.vaccineName).toBeNull();       // empty -> null
      expect(r.data.complaint).toBe("Gatal");
    }
  });

  it("rejects negative or absurd weight", () => {
    expect("error" in validateCarePayload({ ...okBase, weightKg: -1 })).toBe(true);
    expect("error" in validateCarePayload({ ...okBase, weightKg: 999 })).toBe(true);
  });

  it("keeps working with no new fields (Tahap 3 payload)", () => {
    const r = validateCarePayload({ category: "grooming", doneAt: okBase.doneAt });
    expect("data" in r).toBe(true);
    if ("data" in r) expect(r.data.weightKg).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test tests/pet-care-api.test.ts`
Expected: FAIL — `r.data.weightKg` undefined / property missing.

- [ ] **Step 3: Implement — extend type and validator**

Ganti `ValidatedCarePayload` dan bagian akhir `validateCarePayload`:

```typescript
export type ValidatedCarePayload = {
  category: string;
  doneAt: Date;
  note: string | null;
  nextDueAt: Date | null;
  productId: string | null;
  brandText: string | null;
  dosageNote: string | null;
  weightKg: number | null;
  place: string | null;
  vaccineName: string | null;
  complaint: string | null;
};
```

Di dalam `validateCarePayload`, setelah blok `nextDueAt` dan sebelum `return`, tambah:

```typescript
  const b = body as Record<string, unknown>;
  const str = (v: unknown): string | null => {
    if (typeof v !== "string") return null;
    const t = v.trim();
    return t ? t : null;
  };

  let weightKg: number | null = null;
  if (b.weightKg !== undefined && b.weightKg !== null && b.weightKg !== "") {
    const w = typeof b.weightKg === "number" ? b.weightKg : Number(b.weightKg);
    if (Number.isNaN(w) || w <= 0 || w > 200) {
      return { error: "Berat badan tidak valid." };
    }
    weightKg = w;
  }
```

Lalu perluas objek `return`:

```typescript
  return {
    data: {
      category,
      doneAt: parsedDone,
      note: trimmedNote || null,
      nextDueAt: parsedNext,
      productId: str(b.productId),
      brandText: str(b.brandText),
      dosageNote: str(b.dosageNote),
      weightKg,
      place: str(b.place),
      vaccineName: str(b.vaccineName),
      complaint: str(b.complaint),
    },
  };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test tests/pet-care-api.test.ts`
Expected: PASS (new + existing).

- [ ] **Step 5: Commit**

```bash
git add lib/pet-care-api.ts tests/pet-care-api.test.ts
git commit -m "feat(care-api): validate new optional care fields"
```

---

## Task 5: POST route — simpan field baru + sync berat

**Files:**
- Modify: `app/api/member/pets/[id]/care/route.ts:41-66`
- Test: manual + covered by existing route behavior; validator unit-tested in Task 4.

**Interfaces:**
- Consumes: `validateCarePayload` (Task 4), Prisma models (Task 1).
- Produces: record tersimpan dengan field baru; bila `weightKg` terisi & kategori `deworm|flea`, `Pet.weightKg` diperbarui + baris `PetWeightLog`.

- [ ] **Step 1: Update POST handler create-block**

Ganti blok `const record = await prisma.petCareRecord.create(...)` sampai `return`:

```typescript
  const data = validated.data;
  const record = await prisma.petCareRecord.create({
    data: {
      petId: id,
      category: data.category,
      doneAt: data.doneAt,
      note: data.note,
      nextDueAt: data.nextDueAt,
      productId: data.productId,
      brandText: data.brandText,
      dosageNote: data.dosageNote,
      weightKg: data.weightKg,
      place: data.place,
      vaccineName: data.vaccineName,
      complaint: data.complaint,
    },
  });

  if (data.weightKg !== null && (data.category === "deworm" || data.category === "flea")) {
    await prisma.$transaction([
      prisma.pet.update({ where: { id }, data: { weightKg: data.weightKg } }),
      prisma.petWeightLog.create({
        data: { petId: id, weightKg: data.weightKg, careRecordId: record.id },
      }),
    ]);
  }

  return NextResponse.json({ record }, { status: 201 });
```

- [ ] **Step 2: Typecheck**

Run: `bunx tsc --noEmit`
Expected: no errors in `app/api/member/pets/[id]/care/route.ts`.

- [ ] **Step 3: Commit**

```bash
git add app/api/member/pets/[id]/care/route.ts
git commit -m "feat(care-api): persist new care fields and sync pet weight"
```

---

## Task 6: Endpoint rekomendasi produk

**Files:**
- Create: `app/api/products/care-recommendation/route.ts`
- Test: `tests/care-recommendation.test.ts` (pengurutan diuji di Task 3; di sini uji mapping produk→`RecoProductInput`)

**Interfaces:**
- Consumes: `parseDosageRules`, `sortRecommendedProducts`, `pickDosageForWeight` (Tasks 2-3), Prisma `Product` + variants.
- Produces: `GET /api/products/care-recommendation?category=deworm&species=Anjing&weightKg=4.5` → `{ products: Array<{ id, name, imageUrl, effectivePrice, inStock, instruction }> }`. `weightKg` opsional; tanpa `weightKg` → daftar produk kategori tanpa filter berat & tanpa `instruction`.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest";
import { mapProductToReco } from "@/app/api/products/care-recommendation/route";

describe("mapProductToReco", () => {
  it("aggregates variant stock/price and picks dosage instruction", () => {
    const row = {
      id: "p1", name: "Drontal", imageUrl: "x.jpg", price: 45000, stock: 0,
      dosageRules: [{ minKg: 0, maxKg: 10, instruction: "1/2 tablet" }],
      targetSpecies: ["Anjing"],
      variants: [{ price: 45000, stock: 3 }],
    };
    const out = mapProductToReco(row as any, 4.5);
    expect(out).toEqual({
      id: "p1", name: "Drontal", imageUrl: "x.jpg",
      effectivePrice: 45000, inStock: true, instruction: "1/2 tablet",
    });
  });
  it("omits instruction when weight is null", () => {
    const row = { id: "p", name: "N", imageUrl: null, price: 10000, stock: 5,
      dosageRules: [], targetSpecies: [], variants: [] };
    expect(mapProductToReco(row as any, null).instruction).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test tests/care-recommendation.test.ts`
Expected: FAIL — `mapProductToReco` not exported.

- [ ] **Step 3: Implement route**

```typescript
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  parseDosageRules,
  sortRecommendedProducts,
  pickDosageForWeight,
  effectivePrice,
  effectiveStock,
  type RecoProductInput,
} from "@/lib/product-dosage";

type ProductRow = {
  id: string; name: string; imageUrl: string | null; price: number; stock: number;
  dosageRules: unknown; targetSpecies: string[];
  variants: { price: number; stock: number }[];
};

function toRecoInput(row: ProductRow): RecoProductInput {
  return {
    id: row.id, name: row.name, price: row.price, baseStock: row.stock,
    variantStocks: row.variants.map((v) => v.stock),
    variantPrices: row.variants.map((v) => v.price),
    targetSpecies: row.targetSpecies ?? [],
    dosageRules: parseDosageRules(row.dosageRules),
  };
}

export function mapProductToReco(row: ProductRow, weightKg: number | null) {
  const input = toRecoInput(row);
  const dose = weightKg !== null ? pickDosageForWeight(input.dosageRules, weightKg) : null;
  return {
    id: row.id, name: row.name, imageUrl: row.imageUrl,
    effectivePrice: effectivePrice(input),
    inStock: effectiveStock(input) > 0,
    instruction: dose ? dose.instruction : null,
  };
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const category = url.searchParams.get("category");
  const species = url.searchParams.get("species") ?? "";
  const weightRaw = url.searchParams.get("weightKg");
  const weightKg = weightRaw ? Number(weightRaw) : null;

  if (category !== "deworm" && category !== "flea") {
    return NextResponse.json({ products: [] });
  }

  const rows = (await prisma.product.findMany({
    where: { careCategory: category, isActive: true },
    select: {
      id: true, name: true, imageUrl: true, price: true, stock: true,
      dosageRules: true, targetSpecies: true,
      variants: { where: { isActive: true, deletedAt: null }, select: { price: true, stock: true } },
    },
  })) as unknown as ProductRow[];

  let products;
  if (weightKg !== null && !Number.isNaN(weightKg)) {
    const ordered = sortRecommendedProducts(rows.map(toRecoInput), species, weightKg);
    const byId = new Map(rows.map((r) => [r.id, r]));
    products = ordered.map((o) => mapProductToReco(byId.get(o.id)!, weightKg));
  } else {
    products = rows.map((r) => mapProductToReco(r, null));
  }

  return NextResponse.json({ products });
}
```

> Catatan: pastikan `Product` punya `isActive` (bila tidak, buang dari `where`). Verifikasi cepat: `grep -n "isActive" prisma/schema.prisma` di sekitar model Product; sesuaikan filter.

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test tests/care-recommendation.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/api/products/care-recommendation/route.ts tests/care-recommendation.test.ts
git commit -m "feat(api): product care-recommendation endpoint"
```

---

## Task 7: Fungsi AI ekstraksi dosis (admin)

**Files:**
- Create: `lib/ai/extract-dosage-rules.ts`
- Test: `tests/extract-dosage-rules.test.ts` (uji parser output, bukan panggilan jaringan)

**Interfaces:**
- Consumes: `parseDosageRules` (Task 2), `@anthropic-ai/sdk`.
- Produces: `extractDosageRulesFromText(input: { name: string; description: string }): Promise<DosageRule[]>` — panggil Claude, minta JSON array, parse via `parseDosageRules`. Throw `GenerateDescriptionError`-style bila key hilang. Export helper `parseModelJson(text: string): unknown` untuk diuji.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest";
import { parseModelJson } from "@/lib/ai/extract-dosage-rules";

describe("parseModelJson", () => {
  it("parses a bare JSON array", () => {
    expect(parseModelJson('[{"minKg":0,"maxKg":5,"instruction":"1/2 tablet"}]'))
      .toEqual([{ minKg: 0, maxKg: 5, instruction: "1/2 tablet" }]);
  });
  it("strips markdown fences", () => {
    const t = "```json\n[{\"minKg\":0,\"maxKg\":null,\"instruction\":\"x\"}]\n```";
    expect(parseModelJson(t)).toEqual([{ minKg: 0, maxKg: null, instruction: "x" }]);
  });
  it("returns null on non-JSON", () => {
    expect(parseModelJson("tidak ada aturan pakai")).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test tests/extract-dosage-rules.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```typescript
import Anthropic from "@anthropic-ai/sdk";
import { parseDosageRules, type DosageRule } from "@/lib/product-dosage";

const MODEL_ID = "claude-sonnet-4-5";

const SYSTEM_PROMPT = `Kamu asisten data untuk toko hewan. Dari info produk obat cacing/kutu, ekstrak aturan dosis per rentang berat badan hewan. Output HANYA JSON array valid, tanpa teks lain, format: [{"minKg": number, "maxKg": number|null, "instruction": string}]. minKg inklusif, maxKg eksklusif (null = tak terbatas ke atas). instruction singkat (mis. "1/2 tablet", "1 pipet ukuran S"). Kalau info tidak memuat aturan dosis apa pun, output persis: []`;

export class ExtractDosageError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = "ExtractDosageError";
  }
}

export function parseModelJson(text: string): unknown {
  const cleaned = text
    .trim()
    .replace(/^```(?:\w+)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    return null;
  }
}

export async function extractDosageRulesFromText(input: {
  name: string;
  description: string;
}): Promise<DosageRule[]> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new ExtractDosageError("ANTHROPIC_API_KEY belum di-set.", "MISSING_KEY");
  }
  const client = new Anthropic({ apiKey });
  let response;
  try {
    response = await client.messages.create({
      model: MODEL_ID,
      max_tokens: 500,
      system: SYSTEM_PROMPT,
      messages: [
        { role: "user", content: `Nama: ${input.name}\nDeskripsi:\n${input.description}` },
      ],
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new ExtractDosageError(`Gagal call Claude API: ${message}`, "API_ERROR");
  }
  const first = response.content[0];
  if (!first || first.type !== "text") return [];
  return parseDosageRules(parseModelJson(first.text));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test tests/extract-dosage-rules.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ai/extract-dosage-rules.ts tests/extract-dosage-rules.test.ts
git commit -m "feat(ai): structured dosage-rule extraction from product text"
```

---

## Task 8: Admin endpoint ekstrak dosis (draft, tak simpan)

**Files:**
- Create: `app/api/admin/products/[id]/extract-dosage/route.ts`

**Interfaces:**
- Consumes: `extractDosageRulesFromText` (Task 7), admin auth (`getSession("ADMIN")` — samakan dengan endpoint admin lain).
- Produces: `POST /api/admin/products/{id}/extract-dosage` body `{ name, description }` → `{ dosageRules: DosageRule[] }`. Tidak menulis DB.

- [ ] **Step 1: Implement**

```typescript
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { extractDosageRulesFromText, ExtractDosageError } from "@/lib/ai/extract-dosage-rules";

export async function POST(
  request: Request,
  _ctx: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const body = await request.json().catch(() => null);
  const name = typeof body?.name === "string" ? body.name : "";
  const description = typeof body?.description === "string" ? body.description : "";
  if (!name.trim() || !description.trim()) {
    return NextResponse.json({ error: "Nama dan deskripsi wajib diisi." }, { status: 400 });
  }
  try {
    const dosageRules = await extractDosageRulesFromText({ name, description });
    return NextResponse.json({ dosageRules });
  } catch (err) {
    if (err instanceof ExtractDosageError) {
      return NextResponse.json({ error: err.message, code: err.code }, { status: 502 });
    }
    return NextResponse.json({ error: "Gagal ekstrak dosis." }, { status: 500 });
  }
}
```

> Verifikasi role string: `grep -rn "getSession(\"ADMIN\"" app/api/admin | head -1` — sesuaikan bila kode pakai role lain (mis. `"STAFF"`).

- [ ] **Step 2: Typecheck**

Run: `bunx tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/api/admin/products/[id]/extract-dosage/route.ts
git commit -m "feat(admin-api): extract-dosage draft endpoint"
```

---

## Task 9: Admin product form — kategori obat + editor dosis

**Files:**
- Modify: admin product edit form. Lokasi: cari dengan `grep -rln "Buat deskripsi dengan AI\|generateProductDescription\|generate-description" app components` dan buka file form produk yang memuat tombol AI deskripsi.
- Modify: server action / API yang menyimpan produk (tempat `description` disimpan) untuk ikut menyimpan `careCategory`, `targetSpecies`, `dosageRules`.

**Interfaces:**
- Consumes: `POST /api/admin/products/{id}/extract-dosage` (Task 8), kolom produk (Task 1).
- Produces: admin bisa set `careCategory` (dropdown: —/Obat Cacing/Obat Kutu), pilih `targetSpecies` (checkbox `kPetTypes`), dan mengelola `dosageRules` (list baris minKg/maxKg/instruction) dengan tombol "Ekstrak dosis dari deskripsi" yang mengisi draft (tidak auto-simpan; masuk state form, admin klik Simpan produk seperti biasa).

- [ ] **Step 1: Tambah field kategori obat + spesies ke form**

Di form produk, tambah section "Perawatan (obat)" hanya-tampil bila admin memilih kategori obat:
- Dropdown `careCategory`: `""` (bukan obat), `"deworm"` (Obat Cacing), `"flea"` (Obat Kutu).
- Bila `careCategory` non-kosong: tampilkan checkbox grup `targetSpecies` dari `kPetTypes` (kosong = semua spesies) + editor `dosageRules`.

Ikuti pola field & styling form produk yang ada (jangan perkenalkan komponen input baru bila sudah ada primitive `Field`/`Button` — lihat memory `admin-uiux-audit-fixes`).

- [ ] **Step 2: Editor `dosageRules`**

List baris: tiap baris `minKg` (number), `maxKg` (number, kosong = null), `instruction` (text) + tombol hapus baris + "Tambah baris". Simpan sebagai array di state form.

- [ ] **Step 3: Tombol "Ekstrak dosis dari deskripsi"**

`type="button"` (GOTCHA: tombol AI dalam form server-action WAJIB `type=button`, lihat memory `ai-features-pattern`). On click → `POST /api/admin/products/{id}/extract-dosage` dengan `{ name, description }` dari state form → isi baris `dosageRules` dari respons (replace draft, jangan simpan otomatis). Tampilkan loading + error toast pola admin.

- [ ] **Step 4: Simpan produk ikut menulis 3 kolom baru**

Di handler simpan produk (server action/API), sertakan `careCategory` (null bila kosong), `targetSpecies` (array), `dosageRules` (array JSON) ke `prisma.product.update/create`. Validasi ringan: bila `careCategory` kosong, paksa `targetSpecies=[]` dan `dosageRules=null`.

- [ ] **Step 5: Typecheck + lint**

Run: `bunx tsc --noEmit && bunx eslint app --max-warnings=0` (atau perintah lint repo)
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(admin): product care-category, target species, dosage editor with AI extract"
```

---

## Task 10: Flutter models — Pet.weightKg, field care baru, CareProduct/DosageRule

**Files:**
- Modify: `flutter_app/lib/models/pet.dart:35-144`
- Modify: `flutter_app/lib/models/pet_care_record.dart:66-92`
- Create (in same file or new): `CareProduct`, `DosageRuleView` untuk hasil rekomendasi.
- Test: `flutter_app/test/pet_care_record_model_test.dart` (create)

**Interfaces:**
- Produces:
  - `Pet.weightKg` (`double?`) + di `fromJson`/`copyWith`.
  - `PetCareRecord` +`productId/brandText/dosageNote/weightKg/place/vaccineName/complaint` (semua opsional) + parsing di `fromJson`.
  - `class CareProduct { final String id, name; final String? imageUrl; final int effectivePrice; final bool inStock; final String? instruction; factory CareProduct.fromJson(...) }`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo/models/pet_care_record.dart';

void main() {
  test('PetCareRecord parses new optional fields', () {
    final r = PetCareRecord.fromJson({
      'id': 'r1', 'category': 'deworm', 'doneAt': '2026-07-24T00:00:00.000Z',
      'weightKg': 4.5, 'brandText': 'VermiPet', 'place': null,
    });
    expect(r.weightKg, 4.5);
    expect(r.brandText, 'VermiPet');
    expect(r.place, isNull);
  });

  test('CareProduct.fromJson maps fields', () {
    final p = CareProduct.fromJson({
      'id': 'p1', 'name': 'Drontal', 'imageUrl': 'x.jpg',
      'effectivePrice': 45000, 'inStock': true, 'instruction': '1/2 tablet',
    });
    expect(p.effectivePrice, 45000);
    expect(p.inStock, true);
    expect(p.instruction, '1/2 tablet');
  });
}
```

> Ganti `package:natalo/...` dengan nama package aktual dari `flutter_app/pubspec.yaml` (`name:`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/pet_care_record_model_test.dart`
Expected: FAIL — getter `weightKg`/`CareProduct` undefined.

- [ ] **Step 3: Implement**

`PetCareRecord`: tambah field opsional + parsing:

```dart
  final String? productId;
  final String? brandText;
  final String? dosageNote;
  final double? weightKg;
  final String? place;
  final String? vaccineName;
  final String? complaint;
```

Di constructor tambahkan param opsional; di `fromJson`:

```dart
      productId: json['productId'] as String?,
      brandText: json['brandText'] as String?,
      dosageNote: json['dosageNote'] as String?,
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      place: json['place'] as String?,
      vaccineName: json['vaccineName'] as String?,
      complaint: json['complaint'] as String?,
```

`CareProduct` (baru di `pet_care_record.dart`):

```dart
class CareProduct {
  final String id;
  final String name;
  final String? imageUrl;
  final int effectivePrice;
  final bool inStock;
  final String? instruction;

  const CareProduct({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.effectivePrice,
    required this.inStock,
    this.instruction,
  });

  factory CareProduct.fromJson(Map<String, dynamic> json) => CareProduct(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        effectivePrice: (json['effectivePrice'] as num?)?.toInt() ?? 0,
        inStock: json['inStock'] as bool? ?? false,
        instruction: json['instruction'] as String?,
      );
}
```

`Pet`: tambah `final double? weightKg;` + constructor param + `fromJson` (`weightKg: (json['weightKg'] as num?)?.toDouble()`) + `copyWith`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/pet_care_record_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/pet.dart flutter_app/lib/models/pet_care_record.dart flutter_app/test/pet_care_record_model_test.dart
git commit -m "feat(app-models): pet weightKg, new care fields, CareProduct"
```

---

## Task 11: Flutter service — createCare diperluas + fetchCareRecommendation

**Files:**
- Modify: `flutter_app/lib/services/pet_service.dart:127-151`

**Interfaces:**
- Consumes: `CareProduct` (Task 10), `apiClient`.
- Produces:
  - `createCare(...)` bertambah param opsional: `String? productId, String? brandText, String? dosageNote, double? weightKg, String? place, String? vaccineName, String? complaint`.
  - `Future<List<CareProduct>> fetchCareRecommendation({required PetCareCategory category, required String species, double? weightKg})`.

- [ ] **Step 1: Perluas `createCare` body**

Tambahkan param opsional ke signature, lalu di `body` map sertakan hanya yang non-null:

```dart
        if (productId != null) 'productId': productId,
        if (brandText != null) 'brandText': brandText,
        if (dosageNote != null) 'dosageNote': dosageNote,
        if (weightKg != null) 'weightKg': weightKg,
        if (place != null) 'place': place,
        if (vaccineName != null) 'vaccineName': vaccineName,
        if (complaint != null) 'complaint': complaint,
```

- [ ] **Step 2: Tambah `fetchCareRecommendation`**

```dart
  Future<List<CareProduct>> fetchCareRecommendation({
    required PetCareCategory category,
    required String species,
    double? weightKg,
  }) async {
    final q = <String, String>{
      'category': category.apiValue,
      'species': species,
      if (weightKg != null) 'weightKg': weightKg.toString(),
    };
    final uri = Uri(path: '/api/products/care-recommendation', queryParameters: q);
    final data = await apiClient.getJson(uri.toString());
    final list = (data as Map<String, dynamic>)['products'] as List<dynamic>? ?? [];
    return list
        .map((e) => CareProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }
```

> Verifikasi nama method GET di `apiClient` (`getJson` vs `get`) — `grep -n "getJson\|Future.*get" flutter_app/lib/services/api_client.dart`; sesuaikan.

- [ ] **Step 3: Analyze**

Run: `cd flutter_app && flutter analyze lib/services/pet_service.dart`
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/services/pet_service.dart
git commit -m "feat(app-service): extend createCare, add care recommendation fetch"
```

---

## Task 12: Widget pemilih produk + kartu dosis

**Files:**
- Create: `flutter_app/lib/widgets/care_product_picker.dart`
- Test: `flutter_app/test/care_product_picker_test.dart`

**Interfaces:**
- Consumes: `pet_service.fetchCareRecommendation`, `CareProduct` (Tasks 10-11).
- Produces: `CareProductPicker` — `StatefulWidget` props `{ required PetCareCategory category, required String species, required double? weightKg, required void Function(CareSelection) onChanged }`; `class CareSelection { final String? productId; final String? brandText; final String? dosageNote; final String? instructionShown; }`. Menampilkan daftar produk cocok (semua, badge "Paling sesuai" di item pertama), kartu dosis untuk produk terpilih, dan mode manual (Nama brand + Aturan pakai).

- [ ] **Step 1: Write failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo/widgets/care_product_picker.dart';
import 'package:natalo/models/pet_care_record.dart';

void main() {
  testWidgets('renders product list with top badge and manual toggle', (tester) async {
    final products = [
      const CareProduct(id: 'p1', name: 'Drontal', effectivePrice: 45000, inStock: true, instruction: '1/2 tablet'),
      const CareProduct(id: 'p2', name: 'Caniverm', effectivePrice: 15000, inStock: true),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker.debugWithProducts(
          products: products,
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Drontal'), findsOneWidget);
    expect(find.text('Caniverm'), findsOneWidget);
    expect(find.text('Paling sesuai'), findsOneWidget);
    expect(find.textContaining('Ketik manual'), findsOneWidget);
  });
}
```

> `debugWithProducts` = named constructor yang menyuntik daftar produk langsung (tanpa network) untuk test. Sesuaikan nama package.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/care_product_picker_test.dart`
Expected: FAIL — `CareProductPicker` undefined.

- [ ] **Step 3: Implement widget**

Buat `CareProductPicker` dengan:
- State: `List<CareProduct> _products`, `bool _loading`, `String? _selectedId`, `bool _manual`, controllers `_brandCtrl`/`_dosageCtrl`.
- Default constructor memuat via `fetchCareRecommendation` di `initState`/`didUpdateWidget` (re-fetch saat `weightKg`/`category` berubah). Named `debugWithProducts` isi `_products` langsung, skip fetch.
- Daftar produk: `Column`/`ListView` non-scroll (shrinkWrap) — tiap item tap → set `_selectedId`, panggil `onChanged` dengan `CareSelection(productId: id, instructionShown: product.instruction)`. Item pertama (bila `_products` tidak kosong dan `weightKg != null`) diberi badge "Paling sesuai" (visual saja).
- Kartu dosis: bila produk terpilih punya `instruction` → kartu tint biru (deworm) / coral (flea) "Anjuran pakai: {instruction}. Ikuti aturan kemasan atau tanya dokter hewan." Bila `instruction` null → fallback generik.
- Mode manual: link "Beli di luar Natalo? Ketik manual" → tampilkan 2 TextField (Nama brand wajib, Aturan pakai opsional; GOTCHA fillColor). `onChanged` kirim `CareSelection(brandText:..., dosageNote:...)`. Bila Aturan pakai diisi → kartu "Dicatat sendiri: {dosageNote}"; kosong → fallback generik.
- Empty/`_products` kosong: tampilkan hanya link manual + (jika ada) daftar tanpa badge.

Styling ikut token Anabulku (radius 8-12, brand `NataloColors.primary`, chip 999) — lihat spec Tahap 3 tabel token.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/care_product_picker_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/care_product_picker.dart flutter_app/test/care_product_picker_test.dart
git commit -m "feat(app): care product picker with dosage card and manual mode"
```

---

## Task 13: Form dinamis per kategori

**Files:**
- Modify: `flutter_app/lib/screens/pet_care_form_screen.dart`
- Test: `flutter_app/test/pet_care_form_screen_test.dart` (create/extend)

**Interfaces:**
- Consumes: `CareProductPicker`/`CareSelection` (Task 12), `pet_service.createCare` (Task 11), `Pet.weightKg` (Task 10).
- Produces: form yang menampilkan kolom berbeda per `_category`, foto opsional kecil seragam, dan mengirim field baru ke `createCare`.

- [ ] **Step 1: Ubah konstruktor menerima Pet (untuk species + prefill berat)**

`PetCareFormScreen({ required this.petId, required this.pet })` — atau tambahkan `species`/`lastWeightKg`. Update pemanggil (`grep -rn "PetCareFormScreen(" flutter_app/lib`) untuk mengoper pet.

- [ ] **Step 2: Write failing widget test — kolom berubah per kategori**

```dart
testWidgets('deworm shows weight + product picker, grooming shows place', (tester) async {
  // pump PetCareFormScreen dengan pet dummy (species Anjing, weightKg 4.2)
  // pilih chip "Obat Cacing" -> expect find.textContaining('Berat') & CareProductPicker
  // pilih chip "Grooming" -> expect find.textContaining('Tempat grooming')
});
```

Isi test dengan mock `petService` (inject fetcher agar tidak network — pola memory `flutter-widget-test-shimmer-hang`: bounded pump, mock prefs).

- [ ] **Step 3: Implement conditional fields**

Setelah chip kategori, render blok kondisional berdasarkan `_category`:
- `deworm`/`flea`: TextField "Berat saat ini (kg)" (numeric, prefill `widget.pet.weightKg`, hint "Terakhir: X kg" bila ada) → `setState` update `_weightKg`; lalu `CareProductPicker(category, species: widget.pet.type, weightKg: _weightKg, onChanged: (s) => _selection = s)`.
- `grooming`: TextField "Tempat grooming (opsional)" + chip saran ("Natalo Petshop", "Di rumah") → `_place`.
- `vaccine`: TextField "Nama vaksin (opsional)" → `_vaccineName` + TextField "Dokter hewan/tempat (opsional)" → `_place`.
- `vet`: TextField "Keluhan/tujuan kunjungan (opsional)" → `_complaint` + TextField "Dokter hewan/tempat (opsional)" → `_place`.
- `other`: tidak ada tambahan.

Foto: ganti `_PhotoField` besar menjadi thumbnail kecil seragam (~56px) untuk semua kategori (hapus blok besar; simpan alur pick+save lokal Tahap 3).

- [ ] **Step 4: Kirim field baru di `_save`**

```dart
      final record = await petService.createCare(
        widget.petId,
        category: _category,
        doneAt: _doneAt,
        note: note.isEmpty ? null : note,
        nextDueAt: _nextDueAt,
        weightKg: (_category == PetCareCategory.deworm || _category == PetCareCategory.flea) ? _weightKg : null,
        productId: _selection?.productId,
        brandText: _selection?.brandText,
        dosageNote: _selection?.dosageNote,
        place: _place,
        vaccineName: _vaccineName,
        complaint: _complaint,
      );
```

- [ ] **Step 5: Run tests**

Run: `cd flutter_app && flutter test test/pet_care_form_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/pet_care_form_screen.dart flutter_app/test/pet_care_form_screen_test.dart
git commit -m "feat(app): dynamic care form fields per category"
```

---

## Task 14: Riwayat tampilkan brand/tempat + verifikasi penuh

**Files:**
- Modify: `flutter_app/lib/screens/pet_care_screen.dart` (baris riwayat — tampilkan subteks brand/tempat bila ada)

**Interfaces:**
- Consumes: `PetCareRecord` field baru (Task 10).

- [ ] **Step 1: Tambah subteks riwayat**

Di tile riwayat, di bawah tanggal•note, bila `record.brandText != null || record.productId != null` tampilkan brand (dari `brandText`; productId → nama produk jika tersedia di data, else "Produk Natalo"). Untuk grooming/vaccine/vet tampilkan `place` bila ada. Gaya subteks 11/body `onSurfaceVariant`.

- [ ] **Step 2: Full analyze + test (kedua sisi)**

Run: `cd flutter_app && flutter analyze && flutter test`
Expected: no issues, semua test hijau.

Run: `bun test`
Expected: semua backend test hijau.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/screens/pet_care_screen.dart
git commit -m "feat(app): show brand/place in care history"
```

---

## Self-Review Notes

- **Spec coverage:** Form dinamis 5 kategori (Task 13) ✓; foto kecil seragam (Task 13 Step 3) ✓; berat + riwayat (Tasks 1,5,13) ✓; pemilih produk katalog + semua produk terlihat (Tasks 6,12) ✓; manual brand+aturan pakai (Tasks 4,12) ✓; dosis via admin AI + konfirmasi (Tasks 7,8,9) ✓; tidak ada AI dari app (Tasks 11-13 hanya baca) ✓; rekomendasi cacing & kutu mekanisme sama (Task 6, param category) ✓; label "Dokter Hewan"/"Periksa Dokter" (Task 13) ✓.
- **Out of scope (tidak dibuat):** tombol "Beli lagi", pengingat menawarkan produk, grafik berat, edit record — sesuai spec.
- **Type consistency:** `DosageRule`/`CareProduct`/`CareSelection`/`RecoProductInput` dipakai konsisten lintas task; `weightKg` `double?` (Dart) / `Float?`/`number|null` (backend).
- **Verifikasi runtime yang WAJIB dicek implementer** (ditandai inline): role admin string di `getSession`, nama method `apiClient` GET, `Product.isActive` ada/tidak, nama package Flutter di test import, lokasi form produk admin.

---

## Execution Handoff

Plan lengkap, tersimpan di `docs/superpowers/plans/2026-07-24-perawatan-form-kategori-dinamis.md`.
