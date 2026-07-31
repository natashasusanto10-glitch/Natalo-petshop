# PR4 — Migrasi Halaman `/products` ke Stack Search

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pindahkan halaman katalog `/products` dari `/api/products` (cursor, param `kategori/new/popular/seed`) ke `/api/search` (page-based, filter penuh), lalu bangun pengalaman desktop premium "Etalase Natalo" di atasnya — tanpa mematikan satu pun link yang sudah beredar.

**Architecture:** Dua helper murni ber-tes menanggung semua bagian yang mudah salah: `lib/products-search-params.ts` (baca URL `/products` → param `/api/search`, termasuk menerjemahkan param lama) dan `lib/search-doc-to-product.ts` (dokumen search → `StoreProduct` supaya `ProductCard` yang sudah ada tetap dipakai). Halaman tetap server component (metadata + data band), dengan satu client component orkestrator yang memegang fetch, URL, dan tata letak.

**Tech Stack:** Next.js App Router, React, Tailwind v4, Prisma, `node:test` via `tsx`.

## Global Constraints

- **Tidak menyentuh** `flutter_app/**`, `prisma/schema.prisma`, migrasi DB, atau logika cart/checkout/voucher/loyalty/auth. Satu-satunya sentuhan backend adalah menambah field `member_price` ke dokumen search (keputusan owner spec §4.9) — **read-only additif, tanpa endpoint baru**.
- **Identitas merek:** biru `#1E5FBF` (`natalo-*`), font Nunito. Jangan perkenalkan `#2568C7` atau aqua/teal. Rose `#E11D48` (badge diskon) dan emas `#FACC15` (bintang) adalah pengecualian yang sudah disetujui, sudah ada di `ProductCard`.
- **Container 1280** via `PageContainer` / `max-w-[var(--nat-container)]`.
- **`kategori` tetap param resmi di URL `/products`.** Banner DB, hero, `DesktopCategoryNav`, `CategoryTabPage`, dan beranda semua menautkannya. Terjemahkan ke `category` hanya saat memanggil API. `category` juga tetap diterima (grid lama sudah menerimanya; bookmark eksternal mungkin ada).
- **Tidak boleh ada link beranda yang mati.** `/products?popular=best-seller` (tile "Terlaris" DAN judul "🏆 Produk Terlaris"), `?popular=trending`, `?new=last-30-days` semua hidup di beranda. Peta terjemahan wajib di spec §4.9 — ikuti persis.
- **Urutan default `/products` = `best_seller`** ("Paling Populer"), keputusan owner §4.8. Pengacakan `seed` dibuang.
- **Filter yang dibuang** (owner §4.8): `today`, `this-week`, `last-30-days`, `most-searched`, `most-bought`. Jangan bangun ulang.
- **Paginasi:** pertahankan infinite-scroll seperti sekarang (naikkan `page`, tambahkan hasil), + tombol "Muat lebih banyak" sebagai fallback. Jangan ganti ke Prev/Next — katalog ini tidak pernah memakainya dan app Flutter juga infinite-scroll.
- **Mobile dipertahankan fungsional:** filter & sortir mobile pindah ke bottom-sheet (`components/BottomSheet.tsx` yang sudah ada). Chip lama (`ProductFilterChips`) menulis `new`/`popular` yang sudah tidak berlaku — wajib diganti, bukan dibiarkan jadi UI mati.
- **Konvensi tes repo:** helper murni pakai `node:test` (`npx tsx --test tests/<file>.test.ts`); komponen React TIDAK punya unit test — diverifikasi lewat tsc/lint/build/preview.
- **BASELINE terukur di branch ini (bukan regresi, jangan diperbaiki):** `npx tsc --noEmit` → 6 error, semua `Cannot find module 'vitest'` di `tests/admin-brand-schema`, `admin-product-form`, `admin-product-media`, `admin-product-schema`, `admin-product-visibility`, `product-video-draft`. Sukses = **0 error non-vitest**. `npm test` → 6 gagal, enam file itu saja. `npx next build` → **sukses penuh**; kegagalan build = regresi nyata.
- Dev server worktree ini sudah jalan di `http://localhost:3022` (nama preview `listing-pr2-filters`). **Jangan** start/stop/restart lewat Bash; cukup `curl`. `python`, `curl`, `diff` tersedia.
- Commit tiap task, pesan gaya conventional-commit.

---

## File Structure

**Created:**
- `lib/products-search-params.ts` — baca `URLSearchParams` halaman `/products` → bentuk kanonis + builder param `/api/search` + builder href `/products`. Satu tanggung jawab: penerjemahan URL.
- `tests/products-search-params.test.ts`
- `lib/search-doc-to-product.ts` — `ProductSearchDoc` → `StoreProduct`.
- `tests/search-doc-to-product.test.ts`
- `components/products/ProductsGridSkeleton.tsx` — skeleton grid 4-up.
- `components/products/ProductsEmptyState.tsx` — empty state hangat (copy ala app).
- `components/products/ProductsSortControl.tsx` — dropdown sortir desktop + bottom-sheet mobile.
- `components/products/ProductsActiveFilterChips.tsx` — baris chip filter aktif + "Hapus semua".
- `components/products/ProductsCatalogClient.tsx` — orkestrator: fetch, URL, sidebar, grid, sheet.

**Modified:**
- `lib/search.ts` — `member_price` di `ProductSearchDoc`.
- `lib/search-document.mjs` — `member_price` di `productToSearchDoc`.
- `lib/search-document.d.mts` — `memberPrice` di tipe parameter.
- `lib/products.ts` — ekspor `normalizeProductWeight`.
- `app/products/page.tsx` — shell server: metadata tetap, tambah `EtalaseBand`, mount client baru.
- `app/products/loading.tsx` — samakan dengan skeleton baru.
- `components/products/ProductCatalogStickyHeader.tsx` — buang chip lama, sembunyikan di `md+`.

**Deleted (setelah dipastikan tak ada importer lain):**
- `components/products/ProductsInfiniteGrid.tsx`, `hooks/useInfiniteProducts.ts`, `components/products/ProductFilterChips.tsx`, `components/products/ProductFilterTopDrawer.tsx`.

**Out of scope (sengaja):** strip "Terakhir kamu lihat" di empty state — butuh endpoint riwayat-lihat per-user yang belum ada (`UserProductView` cuma dipakai agregat di `lib/products.ts:427`); itu fitur tersendiri, bukan poles. Dicatat sebagai tertunda.

---

## Task 1: `member_price` masuk dokumen search

**Files:**
- Modify: `lib/search.ts` (tipe `ProductSearchDoc`, ~baris 60–85)
- Modify: `lib/search-document.mjs` (`productToSearchDoc`, ~baris 121–229)
- Modify: `lib/search-document.d.mts` (tipe parameter `productToSearchDoc`)
- Test: `tests/search.test.ts`

**Interfaces:**
- Produces: `ProductSearchDoc.member_price: number | null`. Dikonsumsi Task 3.

Latar: `productToSearchDoc` tidak pernah membaca `product.memberPrice`, sehingga `/products` pasca-migrasi akan menampilkan harga normal untuk produk ber-harga-member sementara detail & keranjang memakai harga member. `getProductSearchInclude()` memakai `include` (bukan `select`), jadi `memberPrice` SUDAH ikut terambil dari Prisma — hanya perlu diteruskan. Jalur DB memanggil fungsi ini atas baris Prisma saat request, jadi **tidak perlu reindex** (Meili mati).

- [ ] **Step 1: Tulis tes yang gagal**

Di `tests/search.test.ts`, helper `doc()` membangun `ProductSearchDoc`. Tambahkan `member_price: null,` ke objek default di dalam `doc()` (letakkan tepat setelah baris `discount_price: null,`). Lalu tambahkan tes ini di akhir file:

```ts
test("search doc carries member_price so the catalog can show the member pill", () => {
  const withMember = doc({ id: "m", slug: "m", price_min: 100_000, member_price: 80_000 });
  const withoutMember = doc({ id: "n", slug: "n", price_min: 100_000 });

  assert.equal(withMember.member_price, 80_000);
  assert.equal(withoutMember.member_price, null);
});
```

- [ ] **Step 2: Jalankan, pastikan GAGAL**

Run: `npx tsx --test tests/search.test.ts`
Expected: FAIL — `member_price` belum ada di tipe `ProductSearchDoc` (error tipe).

- [ ] **Step 3: Tambah field ke tipe**

Di `lib/search.ts`, di dalam `export type ProductSearchDoc = {`, tambahkan baris ini tepat SETELAH `discount_price: number | null;`:

```ts
  /** Harga member (kalau di-set & lebih murah). Tanpa ini, katalog yang
   *  dilayani search menampilkan harga normal sementara detail & keranjang
   *  memakai harga member — beda harga untuk produk yang sama. */
  member_price: number | null;
```

- [ ] **Step 4: Isi field di `productToSearchDoc`**

Di `lib/search-document.mjs`, di objek yang di-`return` (yang dimulai `return {` dan berisi `id: product.id,`), tambahkan tepat SETELAH baris `discount_price: discountPrice,`:

```js
    member_price:
      typeof product.memberPrice === "number" && product.memberPrice > 0
        ? product.memberPrice
        : null,
```

- [ ] **Step 5: Tambah field ke deklarasi tipe**

Di `lib/search-document.d.mts`, di dalam objek parameter `productToSearchDoc`, tambahkan tepat SETELAH `discountPrice?: number | null;`:

```ts
  memberPrice?: number | null;
```

- [ ] **Step 6: Cek**

Run: `npx tsx --test tests/search.test.ts`
Expected: PASS (semua tes lama + tes baru).

Run: `npx tsc --noEmit`
Expected: 0 error non-vitest.

Run: `npm run lint`
Expected: 0 errors.

- [ ] **Step 7: Verifikasi hidup**

Tunggu ~3 detik (Fast Refresh), lalu:

```bash
curl -s "http://localhost:3022/api/search?per_page=3" | python -c "
import sys,json
d=json.load(sys.stdin)
print('field member_price ada:', all('member_price' in i for i in d['items']))
print('contoh nilai:', [i['member_price'] for i in d['items']])
print('total tidak berubah:', d['total'])
"
```
Expected: `field member_price ada: True`, nilai `[None, None, None]` (katalog ini belum memakai harga member), `total` tetap `1324`.

- [ ] **Step 8: Commit**

```bash
git add lib/search.ts lib/search-document.mjs lib/search-document.d.mts tests/search.test.ts
git commit -m "feat(search): bawa member_price ke dokumen search

Tanpa ini, /products yang dilayani search akan menampilkan harga normal
untuk produk ber-harga-member sementara detail & keranjang memakai harga
member. Jalur DB memanggil productToSearchDoc saat request jadi tidak perlu
reindex; kalau Meili diaktifkan, field ini wajib ikut reindex."
```

---

## Task 2: `lib/products-search-params.ts` — terjemahan URL (TDD)

**Files:**
- Create: `lib/products-search-params.ts`
- Test: `tests/products-search-params.test.ts`

**Interfaces:**
- Consumes: tipe `SearchSort` dari `@/lib/search`.
- Produces:
  ```ts
  export type ProductsCatalogParams = {
    q: string;
    categorySlugs: string[];
    brandSlugs: string[];
    minPrice?: number;
    maxPrice?: number;
    inStock: boolean;
    minRating?: number;
    discountOnly: boolean;
    sort: SearchSort;
    page: number;
  };
  export const PRODUCTS_DEFAULT_SORT: SearchSort;      // "best_seller"
  export const PRODUCTS_PER_PAGE: number;              // 24
  export function parseProductsParams(sp: URLSearchParams): ProductsCatalogParams;
  export function buildApiSearchParams(p: ProductsCatalogParams): URLSearchParams;
  export function buildProductsHref(p: ProductsCatalogParams): string;
  ```
  Dipakai Task 5, 6, 7.

Ini bagian paling mudah salah di PR ini — link yang beredar bergantung padanya. Peta terjemahan wajib ada di spec §4.9.

- [ ] **Step 1: Tulis tes yang gagal**

Create `tests/products-search-params.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import {
  PRODUCTS_DEFAULT_SORT,
  buildApiSearchParams,
  buildProductsHref,
  parseProductsParams,
} from "@/lib/products-search-params";

function parse(query: string) {
  return parseProductsParams(new URLSearchParams(query));
}

test("empty url falls back to the owner-chosen default sort", () => {
  const p = parse("");
  assert.equal(p.sort, "best_seller");
  assert.equal(PRODUCTS_DEFAULT_SORT, "best_seller");
  assert.equal(p.page, 1);
  assert.deepEqual(p.categorySlugs, []);
  assert.equal(p.discountOnly, false);
});

test("kategori is the canonical param and maps to the api category param", () => {
  const p = parse("kategori=makanan-kucing");
  assert.deepEqual(p.categorySlugs, ["makanan-kucing"]);
  assert.equal(buildApiSearchParams(p).getAll("category").join(","), "makanan-kucing");
});

test("english category param is still accepted for external bookmarks", () => {
  assert.deepEqual(parse("category=makanan-anjing").categorySlugs, ["makanan-anjing"]);
});

test("kategori wins when both spellings are present", () => {
  assert.deepEqual(parse("kategori=a&category=b").categorySlugs, ["a"]);
});

test("legacy popular values translate to real sorts", () => {
  assert.equal(parse("popular=best-seller").sort, "best_seller");
  assert.equal(parse("popular=trending").sort, "trending");
  assert.equal(parse("popular=highest-rating").sort, "rating_desc");
  assert.equal(parse("popular=most-searched").sort, "best_seller");
  assert.equal(parse("popular=most-bought").sort, "best_seller");
});

test("every legacy new value collapses to newest", () => {
  for (const value of ["today", "this-week", "this-month", "last-30-days", "newest"]) {
    assert.equal(parse(`new=${value}`).sort, "newest", value);
  }
});

test("dead nav aliases now do what their label promises", () => {
  assert.equal(parse("sort=terlaris").sort, "best_seller");
  assert.equal(parse("sort=baru").sort, "newest");

  const promo = parse("sort=promo");
  assert.equal(promo.discountOnly, true);
  assert.equal(promo.sort, "best_seller");
});

test("dead promo flags now filter to discounted products", () => {
  assert.equal(parse("promo=1").discountOnly, true);
  assert.equal(parse("diskon=1").discountOnly, true);
  assert.equal(parse("discount_only=true").discountOnly, true);
});

test("explicit modern sort beats a legacy param", () => {
  assert.equal(parse("sort=price_asc&popular=best-seller").sort, "price_asc");
});

test("unknown sort falls back to the default instead of breaking", () => {
  assert.equal(parse("sort=bogus").sort, "best_seller");
});

test("multi brand and the numeric filters survive a round trip", () => {
  const p = parse("brand=royal-canin&brand=whiskas&min_price=50000&max_price=90000&in_stock=true&min_rating=4&page=3");
  assert.deepEqual(p.brandSlugs, ["royal-canin", "whiskas"]);
  assert.equal(p.minPrice, 50000);
  assert.equal(p.maxPrice, 90000);
  assert.equal(p.inStock, true);
  assert.equal(p.minRating, 4);
  assert.equal(p.page, 3);

  const api = buildApiSearchParams(p);
  assert.deepEqual(api.getAll("brand"), ["royal-canin", "whiskas"]);
  assert.equal(api.get("min_price"), "50000");
  assert.equal(api.get("in_stock"), "true");
  assert.equal(api.get("min_rating"), "4");
  assert.equal(api.get("page"), "3");
  assert.equal(api.get("per_page"), "24");
});

test("api params omit filters that are not set", () => {
  const api = buildApiSearchParams(parse(""));
  assert.equal(api.get("min_price"), null);
  assert.equal(api.get("in_stock"), null);
  assert.equal(api.get("discount_only"), null);
  assert.equal(api.get("q"), null);
});

test("discountOnly reaches the api as discount_only", () => {
  assert.equal(buildApiSearchParams(parse("promo=1")).get("discount_only"), "true");
});

test("href writes kategori back, never the english spelling", () => {
  const href = buildProductsHref(parse("category=makanan-ikan"));
  assert.ok(href.startsWith("/products?"), href);
  assert.ok(href.includes("kategori=makanan-ikan"), href);
  assert.ok(!href.includes("category="), href);
});

test("href drops the default sort and page 1 to keep urls clean", () => {
  assert.equal(buildProductsHref(parse("")), "/products");
  assert.equal(buildProductsHref(parse("page=1")), "/products");
  assert.ok(buildProductsHref(parse("sort=newest")).includes("sort=newest"));
});

test("href never carries the legacy params forward", () => {
  const href = buildProductsHref(parse("popular=best-seller&new=today&promo=1"));
  assert.ok(!href.includes("popular="), href);
  assert.ok(!href.includes("new="), href);
  assert.ok(!href.includes("promo="), href);
  assert.ok(href.includes("discount_only=true"), href);
});
```

- [ ] **Step 2: Jalankan, pastikan GAGAL**

Run: `npx tsx --test tests/products-search-params.test.ts`
Expected: FAIL — modul `@/lib/products-search-params` belum ada.

- [ ] **Step 3: Implementasi**

Create `lib/products-search-params.ts`:

```ts
import type { SearchSort } from "@/lib/search";

/**
 * Penerjemah URL halaman /products.
 *
 * `/products` memakai `kategori` (bahasa Indonesia) sebagai param resmi karena
 * banner DB, hero, nav kategori, dan beranda semua menautkannya. `/api/search`
 * memakai `category`. Semua penerjemahan — termasuk param lama yang sudah tidak
 * punya padanan — dikurung di file ini supaya tidak tersebar.
 */

export const PRODUCTS_DEFAULT_SORT: SearchSort = "best_seller";
export const PRODUCTS_PER_PAGE = 24;

export type ProductsCatalogParams = {
  q: string;
  categorySlugs: string[];
  brandSlugs: string[];
  minPrice?: number;
  maxPrice?: number;
  inStock: boolean;
  minRating?: number;
  discountOnly: boolean;
  sort: SearchSort;
  page: number;
};

const MODERN_SORTS: SearchSort[] = [
  "relevance",
  "price_asc",
  "price_desc",
  "newest",
  "rating_desc",
  "best_seller",
  "trending",
];

/** Alias yang dipakai nav desktop. Sebelum PR4 ketiganya TIDAK menyaring apa pun. */
const SORT_ALIASES: Record<string, SearchSort> = {
  terlaris: "best_seller",
  baru: "newest",
  promo: PRODUCTS_DEFAULT_SORT,
};

/** Param `popular` lama. `most-searched`/`most-bought` tidak punya padanan — terlaris paling dekat. */
const POPULAR_SORTS: Record<string, SearchSort> = {
  "best-seller": "best_seller",
  trending: "trending",
  "highest-rating": "rating_desc",
  "most-searched": "best_seller",
  "most-bought": "best_seller",
};

function positiveNumber(raw: string | null): number | undefined {
  if (!raw) return undefined;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
}

export function parseProductsParams(sp: URLSearchParams): ProductsCatalogParams {
  const rawSort = sp.get("sort");

  // `sort=promo` hanya menyaring diskon; urutannya tetap default.
  const discountOnly =
    sp.get("discount_only") === "true" ||
    sp.get("promo") === "1" ||
    sp.get("diskon") === "1" ||
    rawSort === "promo";

  let sort: SearchSort | undefined;
  if (rawSort && (MODERN_SORTS as string[]).includes(rawSort)) {
    sort = rawSort as SearchSort;
  } else if (rawSort && SORT_ALIASES[rawSort]) {
    sort = SORT_ALIASES[rawSort];
  } else {
    const popular = sp.get("popular");
    if (popular && POPULAR_SORTS[popular]) sort = POPULAR_SORTS[popular];
    // Batas 30-hari dibuang (owner §4.8); "terbaru dulu" tak pernah kosong.
    else if (sp.get("new")) sort = "newest";
  }

  const category = sp.get("kategori") ?? sp.get("category");
  const page = Number(sp.get("page"));

  return {
    q: (sp.get("q") ?? "").trim(),
    categorySlugs: category && category !== "all" ? [category] : [],
    brandSlugs: sp.getAll("brand").filter(Boolean),
    minPrice: positiveNumber(sp.get("min_price")),
    maxPrice: positiveNumber(sp.get("max_price")),
    inStock: sp.get("in_stock") === "true",
    minRating: positiveNumber(sp.get("min_rating")),
    discountOnly,
    sort: sort ?? PRODUCTS_DEFAULT_SORT,
    page: Number.isFinite(page) && page >= 1 ? Math.floor(page) : 1,
  };
}

export function buildApiSearchParams(p: ProductsCatalogParams): URLSearchParams {
  const params = new URLSearchParams();
  if (p.q) params.set("q", p.q);
  p.categorySlugs.forEach((slug) => params.append("category", slug));
  p.brandSlugs.forEach((slug) => params.append("brand", slug));
  if (p.minPrice !== undefined) params.set("min_price", String(p.minPrice));
  if (p.maxPrice !== undefined) params.set("max_price", String(p.maxPrice));
  if (p.inStock) params.set("in_stock", "true");
  if (p.minRating !== undefined) params.set("min_rating", String(p.minRating));
  if (p.discountOnly) params.set("discount_only", "true");
  params.set("sort", p.sort);
  params.set("page", String(p.page));
  params.set("per_page", String(PRODUCTS_PER_PAGE));
  return params;
}

/** URL kanonis `/products` — selalu menulis `kategori`, tidak pernah param lama. */
export function buildProductsHref(p: ProductsCatalogParams): string {
  const params = new URLSearchParams();
  if (p.q) params.set("q", p.q);
  p.categorySlugs.forEach((slug) => params.append("kategori", slug));
  p.brandSlugs.forEach((slug) => params.append("brand", slug));
  if (p.minPrice !== undefined) params.set("min_price", String(p.minPrice));
  if (p.maxPrice !== undefined) params.set("max_price", String(p.maxPrice));
  if (p.inStock) params.set("in_stock", "true");
  if (p.minRating !== undefined) params.set("min_rating", String(p.minRating));
  if (p.discountOnly) params.set("discount_only", "true");
  if (p.sort !== PRODUCTS_DEFAULT_SORT) params.set("sort", p.sort);
  if (p.page > 1) params.set("page", String(p.page));
  const query = params.toString();
  return query ? `/products?${query}` : "/products";
}
```

- [ ] **Step 4: Jalankan, pastikan LULUS**

Run: `npx tsx --test tests/products-search-params.test.ts`
Expected: PASS (16 tes).

- [ ] **Step 5: Commit**

```bash
git add lib/products-search-params.ts tests/products-search-params.test.ts
git commit -m "feat(products): helper terjemahan URL katalog -> param search

Mengurung semua penerjemahan di satu tempat: kategori<->category, param lama
popular/new -> sort, dan tiga alias nav yang selama ini mati (terlaris/baru/
promo) plus promo=1 / diskon=1 -> discount_only."
```

---

## Task 3: `lib/search-doc-to-product.ts` — mapper kartu (TDD)

**Files:**
- Create: `lib/search-doc-to-product.ts`
- Modify: `lib/products.ts` (ekspor `normalizeProductWeight`)
- Test: `tests/search-doc-to-product.test.ts`

**Interfaces:**
- Consumes: `ProductSearchDoc` (dengan `member_price` dari Task 1), `StoreProduct` dari `@/lib/products`.
- Produces: `export function searchDocToStoreProduct(doc: ProductSearchDoc): StoreProduct`. Dipakai Task 6.

Latar: `ProductCard` menerima `StoreProduct`; `/api/search` mengembalikan `ProductSearchDoc`. Field yang dibaca `ProductCard` + `ProductCardCta`: `id, name, slug, price, discountPrice, memberPrice, stock, weightGram, imageUrl, hasVariants, avgRating, reviewCount, videoUrl`. Semua ada padanannya kecuali `videoUrl` (dokumen search tidak punya field video → kartu jatuh ke gambar statis; diterima, §4.9).

- [ ] **Step 1: Ekspor `normalizeProductWeight`**

`lib/products.ts` menerapkan koreksi berat maxi-cat 20kg yang dokumen search TIDAK terapkan, padahal `ProductCardCta` menulis berat itu ke keranjang (→ ongkir). Di `lib/products.ts`, ubah baris:

```ts
function normalizeProductWeight(
```
menjadi:
```ts
export function normalizeProductWeight(
```

- [ ] **Step 2: Tulis tes yang gagal**

Create `tests/search-doc-to-product.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { searchDocToStoreProduct } from "@/lib/search-doc-to-product";
import type { ProductSearchDoc } from "@/lib/search";

function searchDoc(overrides: Partial<ProductSearchDoc> = {}): ProductSearchDoc {
  return {
    id: "p1",
    slug: "royal-canin-persian",
    name: "Royal Canin Persian Adult",
    description: "Makanan kucing persian",
    category_id: "c1",
    category_slug: "makanan-kucing",
    category_name: "Makanan Kucing",
    brand_id: "b1",
    brand_slug: "royal-canin",
    brand_name: "Royal Canin",
    variant_names: [],
    sku_codes: [],
    price_min: 120_000,
    price_max: 120_000,
    discount_price: null,
    member_price: null,
    stock: 5,
    total_stock: 5,
    weight_grams: 500,
    avg_rating: 4.8,
    review_count: 12,
    created_at: 1_700_000_000,
    image_url: "https://example.test/a.jpg",
    is_active: true,
    has_variants: false,
    ...overrides,
  };
}

test("maps the fields the product card actually reads", () => {
  const p = searchDocToStoreProduct(searchDoc());

  assert.equal(p.id, "p1");
  assert.equal(p.slug, "royal-canin-persian");
  assert.equal(p.name, "Royal Canin Persian Adult");
  assert.equal(p.price, 120_000);
  assert.equal(p.discountPrice, null);
  assert.equal(p.stock, 5);
  assert.equal(p.imageUrl, "https://example.test/a.jpg");
  assert.equal(p.hasVariants, false);
  assert.equal(p.avgRating, 4.8);
  assert.equal(p.reviewCount, 12);
});

test("member price survives the mapping so the Member pill still renders", () => {
  const p = searchDocToStoreProduct(searchDoc({ member_price: 99_000 }));
  assert.equal(p.memberPrice, 99_000);
});

test("no member price maps to null, not undefined", () => {
  assert.equal(searchDocToStoreProduct(searchDoc()).memberPrice, null);
});

test("discount price is carried through for the discount badge", () => {
  const p = searchDocToStoreProduct(searchDoc({ price_min: 100_000, discount_price: 75_000 }));
  assert.equal(p.price, 100_000);
  assert.equal(p.discountPrice, 75_000);
});

test("stock falls back to total_stock when the per-product field is zero", () => {
  const p = searchDocToStoreProduct(searchDoc({ stock: 0, total_stock: 7 }));
  assert.equal(p.stock, 7);
});

test("weight gets the same maxi-cat correction the products api applies", () => {
  const p = searchDocToStoreProduct(
    searchDoc({
      name: "Maxi-Cat Premium Cat Food 20kg",
      slug: "maxi-cat-premium-cat-food-20kg",
      weight_grams: 1000,
    }),
  );
  assert.equal(p.weightGram, 20_000);
});

test("ordinary products keep their own weight", () => {
  assert.equal(searchDocToStoreProduct(searchDoc({ weight_grams: 850 })).weightGram, 850);
});

test("brand and category labels come across for downstream use", () => {
  const p = searchDocToStoreProduct(searchDoc());
  assert.equal(p.brand, "Royal Canin");
  assert.equal(p.brandId, "b1");
  assert.equal(p.categorySlug, "makanan-kucing");
});

test("gallery is an empty array so consumers never hit undefined", () => {
  assert.deepEqual(searchDocToStoreProduct(searchDoc()).gallery, []);
});
```

- [ ] **Step 3: Jalankan, pastikan GAGAL**

Run: `npx tsx --test tests/search-doc-to-product.test.ts`
Expected: FAIL — modul belum ada.

- [ ] **Step 4: Implementasi**

Create `lib/search-doc-to-product.ts`:

```ts
import { normalizeProductWeight, type StoreProduct } from "@/lib/products";
import type { ProductSearchDoc } from "@/lib/search";

/**
 * Ubah dokumen search jadi bentuk yang dimengerti `ProductCard`.
 *
 * Dipakai `/products` supaya katalog tetap memakai kartu produk yang sama
 * dengan beranda, walau datanya kini datang dari `/api/search`.
 *
 * CATATAN: dokumen search tidak punya field video, jadi `videoUrl` selalu
 * kosong — kartu di `/products` jatuh ke gambar statis (diterima, spec §4.9).
 */
export function searchDocToStoreProduct(doc: ProductSearchDoc): StoreProduct {
  return {
    id: doc.id,
    name: doc.name,
    slug: doc.slug,
    description: doc.description,
    price: doc.price_min,
    discountPrice: doc.discount_price,
    memberPrice: doc.member_price,
    // `stock` dan `total_stock` di-set sama oleh productToSearchDoc; fallback
    // dipertahankan supaya dokumen lama/ganjil tidak bikin kartu "Habis" palsu.
    stock: doc.stock || doc.total_stock,
    // Dokumen search memakai berat mentah; samakan dengan /api/products supaya
    // berat yang ditulis ke keranjang (→ ongkir) tidak berbeda antar halaman.
    weightGram: normalizeProductWeight(doc.name, doc.slug, doc.weight_grams),
    imageUrl: doc.image_url,
    gallery: [],
    hasVariants: doc.has_variants,
    avgRating: doc.avg_rating,
    reviewCount: doc.review_count,
    categoryId: doc.category_id,
    categorySlug: doc.category_slug,
    brand: doc.brand_name,
    brandId: doc.brand_id,
  };
}
```

- [ ] **Step 5: Jalankan, pastikan LULUS**

Run: `npx tsx --test tests/search-doc-to-product.test.ts`
Expected: PASS (9 tes).

Run: `npx tsc --noEmit`
Expected: 0 error non-vitest.

- [ ] **Step 6: Commit**

```bash
git add lib/search-doc-to-product.ts lib/products.ts tests/search-doc-to-product.test.ts
git commit -m "feat(products): mapper dokumen search -> StoreProduct untuk ProductCard

Menjaga /products tetap memakai kartu produk yang sama dengan beranda.
Berat ikut dinormalisasi seperti /api/products supaya berat di keranjang
(dan ongkirnya) tidak beda antar halaman."
```

---

## Task 4: Skeleton + empty state

**Files:**
- Create: `components/products/ProductsGridSkeleton.tsx`
- Create: `components/products/ProductsEmptyState.tsx`
- Modify: `app/products/loading.tsx`

**Interfaces:**
- Produces:
  ```ts
  export function ProductsGridSkeleton({ withSidebar }: { withSidebar?: boolean }): JSX.Element
  export function ProductsEmptyState({ hasActiveFilters, onReset }: { hasActiveFilters: boolean; onReset: () => void }): JSX.Element
  ```
  Dipakai Task 6 & 7.

- [ ] **Step 1: Buat skeleton**

Create `components/products/ProductsGridSkeleton.tsx`:

```tsx
import { ProductCardSkeleton, Skeleton } from "@/components/Skeleton";

/**
 * Skeleton grid katalog. Meniru geometri grid asli (2/3/4 kolom) supaya tidak
 * ada lompatan lebar saat data masuk.
 */
export function ProductsGridSkeleton({ withSidebar = false }: { withSidebar?: boolean }) {
  const grid = (
    <div className="grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:grid-cols-4">
      {Array.from({ length: 8 }).map((_, i) => (
        <ProductCardSkeleton key={i} />
      ))}
    </div>
  );

  if (!withSidebar) return grid;

  return (
    <div className="mt-4 gap-6 md:grid md:grid-cols-[248px_1fr]">
      <div className="hidden md:block">
        <div className="space-y-4 rounded-2xl border border-gray-100 bg-white p-4">
          <Skeleton className="h-4 w-16" />
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-8 w-full" />
          ))}
        </div>
      </div>
      <div className="min-w-0">{grid}</div>
    </div>
  );
}
```

- [ ] **Step 2: Buat empty state**

Copy ikut app Flutter (spec §6). Create `components/products/ProductsEmptyState.tsx`:

```tsx
"use client";

import Link from "next/link";

/**
 * Empty state hangat — copy disamakan dengan app Flutter supaya pengalaman
 * web & app terasa satu suara.
 */
export function ProductsEmptyState({
  hasActiveFilters,
  onReset,
}: {
  hasActiveFilters: boolean;
  onReset: () => void;
}) {
  return (
    <div className="rounded-[var(--radius-xl)] border border-natalo-100 bg-natalo-50/60 px-6 py-12 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-white text-3xl shadow-[var(--shadow-card)]">
        🐾
      </div>
      <h2 className="mt-4 text-lg font-extrabold text-natalo-900">
        Produk tidak ditemukan
      </h2>
      <p className="mx-auto mt-1 max-w-sm text-sm text-zinc-600">
        Coba kata kunci lain atau ubah filter pencarian.
      </p>
      <div className="mt-5 flex flex-wrap items-center justify-center gap-2">
        {hasActiveFilters && (
          <button
            type="button"
            onClick={onReset}
            className="rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-black text-white transition active:scale-95 hover:bg-natalo-700"
          >
            Reset Filter
          </button>
        )}
        <Link
          href="/products"
          className="rounded-full border border-natalo-200 bg-white px-5 py-2.5 text-sm font-bold text-natalo-700 transition hover:bg-natalo-50"
        >
          Lihat semua produk
        </Link>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Samakan loading.tsx dengan skeleton baru**

Replace the whole body of `app/products/loading.tsx` with:

```tsx
import { Skeleton } from "@/components/Skeleton";
import { ProductsGridSkeleton } from "@/components/products/ProductsGridSkeleton";

export default function ProductsLoading() {
  return (
    <div className="mx-auto max-w-[var(--nat-container)] px-[var(--nat-gutter)] py-4 md:py-10">
      <div className="mb-5 md:mb-6">
        <Skeleton className="h-7 w-44" />
        <Skeleton className="mt-2 h-3.5 w-56" />
      </div>
      <Skeleton className="mb-3 h-3 w-40" />
      <ProductsGridSkeleton withSidebar />
    </div>
  );
}
```

- [ ] **Step 4: Cek**

Run: `npx tsc --noEmit`
Expected: 0 error non-vitest.

Run: `npm run lint`
Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add components/products/ProductsGridSkeleton.tsx components/products/ProductsEmptyState.tsx app/products/loading.tsx
git commit -m "feat(products): skeleton grid + empty state hangat untuk katalog"
```

---

## Task 5: Kontrol sortir + chip filter aktif

**Files:**
- Create: `components/products/ProductsSortControl.tsx`
- Create: `components/products/ProductsActiveFilterChips.tsx`

**Interfaces:**
- Consumes: `ProductsCatalogParams` (Task 2); `BottomSheet` dari `@/components/BottomSheet` (props: `open`, `onClose`, `title?`, `children`, `footer?`); `FilterChip` dari `@/components/products/FilterChip` (props: `label`, `onRemove`); `formatRupiah` dari `@/lib/format`.
- Produces:
  ```ts
  export const PRODUCTS_SORT_OPTIONS: { value: SearchSort; label: string }[];
  export function ProductsSortControl({ sort, onSortChange }: { sort: SearchSort; onSortChange: (next: SearchSort) => void }): JSX.Element
  export function ProductsActiveFilterChips({ params, facets, onChange, onReset }: {...}): JSX.Element | null
  ```
  Dipakai Task 6.

- [ ] **Step 1: Buat kontrol sortir**

Label mengikuti app Flutter (spec §4.2). Create `components/products/ProductsSortControl.tsx`:

```tsx
"use client";

import { useState } from "react";
import { BottomSheet } from "@/components/BottomSheet";
import type { SearchSort } from "@/lib/search";

/** Label disamakan dengan app Flutter supaya web & app satu bahasa. */
export const PRODUCTS_SORT_OPTIONS: { value: SearchSort; label: string }[] = [
  { value: "best_seller", label: "Paling Populer" },
  { value: "trending", label: "Trending" },
  { value: "newest", label: "Terbaru" },
  { value: "rating_desc", label: "Rating Tertinggi" },
  { value: "price_asc", label: "Harga Terendah" },
  { value: "price_desc", label: "Harga Tertinggi" },
];

export function ProductsSortControl({
  sort,
  onSortChange,
}: {
  sort: SearchSort;
  onSortChange: (next: SearchSort) => void;
}) {
  const [open, setOpen] = useState(false);
  const active = PRODUCTS_SORT_OPTIONS.find((o) => o.value === sort) ?? PRODUCTS_SORT_OPTIONS[0];

  return (
    <>
      {/* Desktop: select native — 6 opsi terlalu lebar untuk segmented. */}
      <label className="hidden items-center gap-2 md:inline-flex">
        <span className="text-xs font-semibold text-zinc-500">Urutkan</span>
        <select
          value={sort}
          onChange={(event) => onSortChange(event.target.value as SearchSort)}
          className="h-9 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 outline-none focus:border-natalo-500 focus:ring-2 focus:ring-natalo-100"
        >
          {PRODUCTS_SORT_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </label>

      {/* Mobile: bottom-sheet ala app. */}
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
        aria-expanded={open}
        className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 active:bg-gray-50 md:hidden"
      >
        Urut: {active.label}
      </button>

      <BottomSheet open={open} onClose={() => setOpen(false)} title="Urutkan berdasarkan">
        <div className="-mx-1 space-y-1">
          {PRODUCTS_SORT_OPTIONS.map((option) => {
            const selected = option.value === sort;
            return (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  onSortChange(option.value);
                  setOpen(false);
                }}
                className={`flex h-12 w-full items-center justify-between rounded-2xl px-4 text-left text-sm font-extrabold transition active:bg-natalo-50 ${
                  selected ? "bg-natalo-50 text-natalo-700" : "text-gray-800"
                }`}
              >
                <span>{option.label}</span>
                {selected && <span className="text-natalo-600">✓</span>}
              </button>
            );
          })}
        </div>
      </BottomSheet>
    </>
  );
}
```

- [ ] **Step 2: Buat chip filter aktif**

Create `components/products/ProductsActiveFilterChips.tsx`:

```tsx
"use client";

import { FilterChip } from "@/components/products/FilterChip";
import { formatRupiah } from "@/lib/format";
import type { Facets } from "@/components/SearchFilters";
import type { ProductsCatalogParams } from "@/lib/products-search-params";

/**
 * Baris chip filter aktif. Nilainya polos ("Whiskas", bukan "Brand: Whiskas")
 * mengikuti aturan badge di spec — jangan ulang nama dimensinya.
 */
export function ProductsActiveFilterChips({
  params,
  facets,
  onChange,
  onReset,
}: {
  params: ProductsCatalogParams;
  facets: Facets | null;
  onChange: (next: ProductsCatalogParams) => void;
  onReset: () => void;
}) {
  const hasPrice = params.minPrice !== undefined || params.maxPrice !== undefined;
  const hasAny =
    params.categorySlugs.length > 0 ||
    params.brandSlugs.length > 0 ||
    hasPrice ||
    params.inStock ||
    params.minRating !== undefined ||
    params.discountOnly;

  if (!hasAny) return null;

  return (
    <div className="mt-3 flex flex-wrap items-center gap-2">
      {params.categorySlugs.map((slug) => (
        <FilterChip
          key={`category-${slug}`}
          label={facets?.categories.find((c) => c.slug === slug)?.name ?? slug}
          onRemove={() => onChange({ ...params, categorySlugs: [], page: 1 })}
        />
      ))}
      {params.brandSlugs.map((slug) => (
        <FilterChip
          key={`brand-${slug}`}
          label={facets?.brands.find((b) => b.slug === slug)?.name ?? slug}
          onRemove={() =>
            onChange({
              ...params,
              brandSlugs: params.brandSlugs.filter((value) => value !== slug),
              page: 1,
            })
          }
        />
      ))}
      {hasPrice && (
        <FilterChip
          label={`${params.minPrice ? formatRupiah(params.minPrice) : "Rp0"} - ${
            params.maxPrice ? formatRupiah(params.maxPrice) : "Maks"
          }`}
          onRemove={() =>
            onChange({ ...params, minPrice: undefined, maxPrice: undefined, page: 1 })
          }
        />
      )}
      {params.inStock && (
        <FilterChip
          label="Stok tersedia"
          onRemove={() => onChange({ ...params, inStock: false, page: 1 })}
        />
      )}
      {params.minRating !== undefined && (
        <FilterChip
          label={`Rating ${params.minRating}+`}
          onRemove={() => onChange({ ...params, minRating: undefined, page: 1 })}
        />
      )}
      {params.discountOnly && (
        <FilterChip
          label="Sedang diskon"
          onRemove={() => onChange({ ...params, discountOnly: false, page: 1 })}
        />
      )}
      <button
        type="button"
        onClick={onReset}
        className="h-7 rounded-full px-2 text-xs font-extrabold text-natalo-600 active:bg-natalo-50"
      >
        Hapus semua
      </button>
    </div>
  );
}
```

- [ ] **Step 3: Cek**

Run: `npx tsc --noEmit`
Expected: 0 error non-vitest.

Run: `npm run lint`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add components/products/ProductsSortControl.tsx components/products/ProductsActiveFilterChips.tsx
git commit -m "feat(products): kontrol sortir (dropdown desktop + sheet mobile) & chip filter aktif"
```

---

## Task 6: `ProductsCatalogClient` — orkestrator

**Files:**
- Create: `components/products/ProductsCatalogClient.tsx`

**Interfaces:**
- Consumes: `parseProductsParams`, `buildApiSearchParams`, `buildProductsHref`, `PRODUCTS_PER_PAGE`, `type ProductsCatalogParams` (Task 2); `searchDocToStoreProduct` (Task 3); `ProductsGridSkeleton`, `ProductsEmptyState` (Task 4); `ProductsSortControl`, `ProductsActiveFilterChips` (Task 5); `SearchFilters` + `type ActiveFilters` + `type Facets` dari `@/components/SearchFilters`; `ProductCard`; `BottomSheet`.
- Produces: `export function ProductsCatalogClient(): JSX.Element`. Dipakai Task 7.

Catatan penting: `SearchFilters` bersifat route-agnostic (hanya memanggil `onFiltersChange`/`onReset`) — pakai apa adanya, jangan diedit. `ActiveFilters` tidak punya `discountOnly`, jadi toggle diskon diletakkan di luar `SearchFilters` (di sheet mobile & sidebar desktop, tepat di bawahnya).

- [ ] **Step 1: Implementasi**

Create `components/products/ProductsCatalogClient.tsx`:

```tsx
"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { BottomSheet } from "@/components/BottomSheet";
import { ProductCard } from "@/components/ProductCard";
import {
  SearchFilters,
  type ActiveFilters,
  type Facets,
} from "@/components/SearchFilters";
import { ProductsActiveFilterChips } from "@/components/products/ProductsActiveFilterChips";
import { ProductsEmptyState } from "@/components/products/ProductsEmptyState";
import { ProductsGridSkeleton } from "@/components/products/ProductsGridSkeleton";
import { ProductsSortControl } from "@/components/products/ProductsSortControl";
import {
  PRODUCTS_PER_PAGE,
  buildApiSearchParams,
  buildProductsHref,
  parseProductsParams,
  type ProductsCatalogParams,
} from "@/lib/products-search-params";
import { searchDocToStoreProduct } from "@/lib/search-doc-to-product";
import type { ProductSearchDoc } from "@/lib/search";

type SearchResponse = {
  items: ProductSearchDoc[];
  total: number;
  page: number;
  per_page: number;
  facets: Facets | null;
};

const EMPTY_FACETS: Facets = {
  categories: [],
  brands: [],
  price_range: { min: 0, max: 0 },
  weights: [],
};

export function ProductsCatalogClient() {
  const router = useRouter();
  const sp = useSearchParams();
  const params = useMemo(() => parseProductsParams(new URLSearchParams(sp.toString())), [sp]);
  const key = buildApiSearchParams(params).toString();

  const [items, setItems] = useState<ProductSearchDoc[]>([]);
  const [total, setTotal] = useState(0);
  const [facets, setFacets] = useState<Facets | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filterOpen, setFilterOpen] = useState(false);

  // Halaman yang sudah ditambahkan lewat infinite-scroll, di ATAS params.page.
  const [extraPages, setExtraPages] = useState(0);
  const loaderRef = useRef<HTMLDivElement | null>(null);
  const requestIdRef = useRef(0);

  // Ganti filter/sort → mulai dari awal lagi.
  useEffect(() => {
    setExtraPages(0);
  }, [key]);

  useEffect(() => {
    const requestId = ++requestIdRef.current;
    const controller = new AbortController();
    setLoading(true);
    setError(null);

    fetch(`/api/search?${key}`, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error("Gagal memuat produk");
        return response.json() as Promise<SearchResponse>;
      })
      .then((data) => {
        if (requestId !== requestIdRef.current) return;
        setItems(data.items ?? []);
        setTotal(data.total ?? 0);
        setFacets(data.facets ?? EMPTY_FACETS);
      })
      .catch((cause) => {
        if (cause instanceof Error && cause.name === "AbortError") return;
        if (requestId !== requestIdRef.current) return;
        setError("Gagal memuat produk");
      })
      .finally(() => {
        if (!controller.signal.aborted && requestId === requestIdRef.current) setLoading(false);
      });

    return () => controller.abort();
  }, [key]);

  const loadedCount = items.length;
  const hasMore = loadedCount < total;

  const loadMore = useCallback(async () => {
    if (loadingMore || loading || !hasMore) return;
    setLoadingMore(true);
    const nextPage = params.page + extraPages + 1;
    const nextKey = buildApiSearchParams({ ...params, page: nextPage }).toString();
    try {
      const response = await fetch(`/api/search?${nextKey}`);
      if (!response.ok) throw new Error("Gagal memuat produk");
      const data = (await response.json()) as SearchResponse;
      setItems((prev) => {
        const seen = new Set(prev.map((item) => item.id));
        return [...prev, ...(data.items ?? []).filter((item) => !seen.has(item.id))];
      });
      setExtraPages((value) => value + 1);
    } catch {
      setError("Gagal memuat produk");
    } finally {
      setLoadingMore(false);
    }
  }, [extraPages, hasMore, loading, loadingMore, params]);

  useEffect(() => {
    const node = loaderRef.current;
    if (!node || !hasMore) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) void loadMore();
      },
      { rootMargin: "320px" },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [hasMore, loadMore]);

  function apply(next: ProductsCatalogParams) {
    router.push(buildProductsHref({ ...next, page: 1 }), { scroll: false });
  }

  function reset() {
    router.push(params.q ? buildProductsHref({ ...params, q: params.q, categorySlugs: [], brandSlugs: [], minPrice: undefined, maxPrice: undefined, inStock: false, minRating: undefined, discountOnly: false, page: 1 }) : "/products", { scroll: false });
  }

  const filters: ActiveFilters = {
    categorySlugs: params.categorySlugs,
    brandSlugs: params.brandSlugs,
    minPrice: params.minPrice,
    maxPrice: params.maxPrice,
    inStock: params.inStock,
    minRating: params.minRating,
  };

  function onFiltersChange(next: ActiveFilters) {
    apply({
      ...params,
      // Kategori di /products single-select walau backend dukung multi.
      categorySlugs: next.categorySlugs.slice(-1),
      brandSlugs: next.brandSlugs,
      minPrice: next.minPrice,
      maxPrice: next.maxPrice,
      inStock: next.inStock,
      minRating: next.minRating,
    });
  }

  const discountToggle = (
    <label className="mt-4 flex cursor-pointer items-center gap-2 rounded-lg px-2 py-1.5 text-sm hover:bg-natalo-50">
      <input
        type="checkbox"
        checked={params.discountOnly}
        onChange={(event) => apply({ ...params, discountOnly: event.target.checked })}
        className="h-4 w-4 accent-natalo-600"
      />
      <span className="text-zinc-700">Sedang diskon</span>
    </label>
  );

  const filtersPanel = (
    <>
      <SearchFilters
        facets={facets}
        filters={filters}
        onFiltersChange={onFiltersChange}
        onReset={reset}
      />
      {discountToggle}
    </>
  );

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-gray-500">
          {loading ? (
            "Memuat produk..."
          ) : (
            <>
              Menampilkan <span className="font-black text-natalo-700">{loadedCount}</span> dari{" "}
              <span className="font-black text-natalo-700">{total}</span> produk
            </>
          )}
        </p>
        <div className="flex items-center gap-2">
          <ProductsSortControl
            sort={params.sort}
            onSortChange={(next) => apply({ ...params, sort: next })}
          />
          <button
            type="button"
            onClick={() => setFilterOpen(true)}
            className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 active:bg-gray-50 md:hidden"
          >
            Filter
          </button>
        </div>
      </div>

      <ProductsActiveFilterChips
        params={params}
        facets={facets}
        onChange={apply}
        onReset={reset}
      />

      <div className="mt-4 gap-6 md:grid md:grid-cols-[248px_1fr]">
        <aside className="hidden md:block">
          <div className="sticky top-24 max-h-[calc(100vh-6rem)] overflow-y-auto rounded-2xl border border-gray-100 bg-white p-4">
            <h2 className="mb-4 text-sm font-black text-gray-950">Filter</h2>
            {filtersPanel}
          </div>
        </aside>

        <section className="min-w-0">
          {loading ? (
            <ProductsGridSkeleton />
          ) : error ? (
            <div className="rounded-2xl border border-red-100 bg-red-50 p-8 text-center">
              <p className="text-sm font-bold text-red-600">Gagal memuat produk</p>
              <button
                type="button"
                onClick={() => router.refresh()}
                className="mt-3 rounded-full bg-red-600 px-4 py-2 text-xs font-black text-white"
              >
                Coba lagi
              </button>
            </div>
          ) : items.length === 0 ? (
            <ProductsEmptyState
              hasActiveFilters={
                params.categorySlugs.length > 0 ||
                params.brandSlugs.length > 0 ||
                params.inStock ||
                params.discountOnly ||
                params.minRating !== undefined ||
                params.minPrice !== undefined ||
                params.maxPrice !== undefined
              }
              onReset={reset}
            />
          ) : (
            <>
              <div className="nat-content-fade-in grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:grid-cols-4">
                {items.map((doc, index) => (
                  <ProductCard
                    key={doc.id}
                    product={searchDocToStoreProduct(doc)}
                    priority={index < 4}
                    showRating
                  />
                ))}
              </div>

              <div ref={loaderRef} className="h-10" aria-hidden="true" />

              {hasMore && (
                <div className="flex justify-center py-6">
                  <button
                    type="button"
                    onClick={() => void loadMore()}
                    disabled={loadingMore}
                    className="rounded-full border border-natalo-200 bg-white px-6 py-2.5 text-sm font-bold text-natalo-700 transition hover:bg-natalo-50 disabled:opacity-60"
                  >
                    {loadingMore ? "Memuat produk..." : "Muat lebih banyak"}
                  </button>
                </div>
              )}

              {!hasMore && (
                <p className="py-6 text-center text-sm font-semibold text-gray-400">
                  Semua produk sudah ditampilkan.
                </p>
              )}
            </>
          )}
        </section>
      </div>

      <BottomSheet
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        title="Filter Produk"
        footer={
          <button
            type="button"
            onClick={() => setFilterOpen(false)}
            className="h-11 w-full rounded-full bg-natalo-600 text-sm font-black text-white active:bg-natalo-700"
          >
            Tampilkan {total} produk
          </button>
        }
      >
        {filtersPanel}
      </BottomSheet>
    </>
  );
}
```

Catatan `PRODUCTS_PER_PAGE`: dipakai lewat `buildApiSearchParams`; kalau linter mengeluh impornya tak terpakai, hapus dari daftar impor.

- [ ] **Step 2: Cek**

Run: `npx tsc --noEmit`
Expected: 0 error non-vitest.

Run: `npm run lint`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add components/products/ProductsCatalogClient.tsx
git commit -m "feat(products): client katalog di atas stack search (sidebar, sortir, chip, infinite-scroll)"
```

---

## Task 7: Tukar halaman `/products` ke stack baru (shell server + sticky header + hapus kode mati)

**Files:**
- Modify: `app/products/page.tsx`
- Modify: `components/products/ProductCatalogStickyHeader.tsx`
- Delete: `components/products/ProductsInfiniteGrid.tsx`, `hooks/useInfiniteProducts.ts`, `components/products/ProductFilterChips.tsx`, `components/products/ProductFilterTopDrawer.tsx`

**Interfaces:**
- Consumes: `ProductsCatalogClient` (Task 6); `parseProductsParams` (Task 2); `ProductsGridSkeleton` (Task 4); `EtalaseBand` dari `@/components/products/EtalaseBand` (props: `heading`, `tagline`, `meta?: string[]`, `breadcrumb?: {label, href?}[]`, `thumbnailUrl?`, `className?`); `etalaseHeading`, `etalaseTagline`, `ETALASE_TRUST` dari `@/lib/etalase`; `PageContainer`.
- Produces: `ProductCatalogStickyHeader` dengan props menyusut jadi `{ brandName, categories, activeBrandName?, query, isSearchResult }`.

**Kenapa satu task, bukan dua:** halaman dan sticky header saling bergantung — props header menyusut DAN halaman berhenti mengoper prop lama pada saat yang sama. Memisahnya membuat typecheck gagal di antara keduanya, jadi tidak bisa di-review terpisah. Penghapusan komponen mati ikut di sini karena halaman inilah pemakai terakhirnya.

- [ ] **Step 1: Tulis ulang halaman**

Replace the ENTIRE contents of `app/products/page.tsx` with:

```tsx
import type { Metadata } from "next";
import { Suspense } from "react";
import { EtalaseBand } from "@/components/products/EtalaseBand";
import { ProductCatalogStickyHeader } from "@/components/products/ProductCatalogStickyHeader";
import { ProductsCatalogClient } from "@/components/products/ProductsCatalogClient";
import { ProductsGridSkeleton } from "@/components/products/ProductsGridSkeleton";
import { PageContainer } from "@/components/ui/PageContainer";
import { ETALASE_TRUST, etalaseHeading, etalaseTagline } from "@/lib/etalase";
import { parseProductsParams } from "@/lib/products-search-params";
import { prisma } from "@/lib/prisma";

// Filter per-pengunjung lewat query param. Halaman tetap dinamis supaya state
// filter langsung terlihat sementara grid dimuat di klien.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Katalog Produk",
  description:
    "Temukan pakan ikan, aksesoris kucing, anjing, burung, kelinci, dan kebutuhan aquarium lengkap dengan harga terjangkau.",
  openGraph: {
    title: "Katalog Produk",
    description:
      "Semua kebutuhan hewan peliharaan kamu tersedia di sini. Produk original, harga bersaing.",
  },
};

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const resolved = await searchParams;
  const usp = new URLSearchParams();
  for (const [rawKey, rawValue] of Object.entries(resolved)) {
    if (Array.isArray(rawValue)) rawValue.forEach((value) => usp.append(rawKey, value));
    else if (rawValue !== undefined) usp.set(rawKey, rawValue);
  }
  const params = parseProductsParams(usp);
  const isSearchResult = Boolean(params.q);

  const categorySlug = params.categorySlugs[0] ?? null;
  const brandSlug = params.brandSlugs[0] ?? null;

  const [categories, activeBrand, activeCategory] = await Promise.all([
    prisma.category.findMany({ orderBy: { name: "asc" } }).catch(() => []),
    brandSlug
      ? prisma.brand
          .findFirst({ where: { slug: brandSlug, isActive: true }, select: { name: true } })
          .catch(() => null)
      : Promise.resolve(null),
    categorySlug
      ? prisma.category
          .findFirst({ where: { slug: categorySlug }, select: { name: true } })
          .catch(() => null)
      : Promise.resolve(null),
  ]);

  const categoriesForHeader = categories.map((category) => ({
    slug: category.slug,
    name: category.name,
  }));

  const heading = etalaseHeading({
    brandName: activeBrand?.name,
    categoryName: activeCategory?.name,
    isSearch: isSearchResult,
    query: params.q,
  });
  const tagline = etalaseTagline({
    brandName: activeBrand?.name,
    categoryName: activeCategory?.name,
    isSearch: isSearchResult,
  });

  return (
    <PageContainer
      className={
        isSearchResult
          ? "pb-[calc(1.5rem+env(safe-area-inset-bottom))] md:py-8"
          : "pb-[calc(6rem+env(safe-area-inset-bottom))] md:py-10"
      }
    >
      <ProductCatalogStickyHeader
        brandName={process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop"}
        categories={categoriesForHeader}
        activeBrandName={activeBrand?.name}
        query={params.q}
        isSearchResult={isSearchResult}
      />

      <div className="mb-4 hidden md:block">
        <EtalaseBand
          heading={heading}
          tagline={tagline}
          meta={[...ETALASE_TRUST]}
          breadcrumb={[{ label: "Beranda", href: "/" }, { label: "Katalog" }]}
        />
      </div>

      <Suspense fallback={<ProductsGridSkeleton withSidebar />}>
        <ProductsCatalogClient />
      </Suspense>
    </PageContainer>
  );
}
```

Catatan: props `activeCategory`, `activeNewFilter`, `activePopularFilter` sengaja TIDAK diteruskan lagi — Step 2 membuangnya dari komponennya. Typecheck baru bersih setelah Step 2; jangan panik di antara keduanya.

- [ ] **Step 2: Tulis ulang sticky header jadi mobile-only**

Latar: chip lama menulis `new`/`popular` yang sudah tidak berlaku — kalau dibiarkan, jadi UI yang tampak berfungsi tapi tidak menyaring apa pun. Diganti oleh tombol Filter/Urut di `ProductsCatalogClient`. Di `md+` seluruh sticky header disembunyikan: header global desktop sudah punya pencarian, dan judul kini dipegang `EtalaseBand`.

Replace the ENTIRE contents of `components/products/ProductCatalogStickyHeader.tsx` with:

```tsx
import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { CartCount } from "@/components/CartCount";
import { NotificationBell } from "@/components/NotificationBell";
import { ProductSearchBar } from "@/components/products/ProductSearchBar";

type CategoryOption = {
  slug: string;
  name: string;
};

type Props = {
  brandName: string;
  categories: CategoryOption[];
  activeBrandName?: string;
  query: string;
  isSearchResult: boolean;
};

/**
 * Chrome katalog khusus MOBILE.
 *
 * Di `md+` seluruhnya disembunyikan: header global desktop sudah menyediakan
 * pencarian, judul dipegang EtalaseBand, dan filter dipegang sidebar. Baris
 * chip lama (kategori/produk-baru/populer) dibuang karena menulis param
 * `new`/`popular` yang tidak lagi menyaring apa pun setelah katalog pindah ke
 * stack search — filter & sortir mobile kini ada di ProductsCatalogClient.
 */
export function ProductCatalogStickyHeader({
  brandName,
  categories: _categories,
  activeBrandName,
  query,
  isSearchResult,
}: Props) {
  const title = activeBrandName ? `Produk ${activeBrandName}` : "Katalog Produk";

  return (
    <div className="produk-sticky-header sticky top-0 z-[1050] -mx-4 mb-3 rounded-b-3xl border-b border-slate-200/80 bg-white px-4 pb-2.5 pt-[calc(0.55rem+env(safe-area-inset-top))] shadow-[0_10px_28px_rgba(15,23,42,0.08)] md:hidden">
      <div className="mb-2 flex min-h-[58px] items-center justify-between gap-3">
        <Link href="/" aria-label={brandName} className="flex min-w-0 shrink-0 items-center">
          <Image
            src="/logo.png"
            alt={brandName}
            width={600}
            height={196}
            priority
            sizes="150px"
            className="h-10 w-auto max-w-[150px]"
          />
        </Link>

        <div className="flex shrink-0 items-center gap-1.5">
          <NotificationBell compact />
          <CartCount compact />
        </div>
      </div>

      <div className="mb-1">
        <h1 className="text-xl font-black tracking-tight text-slate-950">{title}</h1>
      </div>

      <div>
        <Suspense fallback={<div className="h-10 w-full animate-pulse rounded-full bg-gray-100" />}>
          <ProductSearchBar defaultValue={query} showBackButton={isSearchResult} />
        </Suspense>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Pastikan komponen lama benar-benar tak terpakai**

```bash
grep -rn "ProductsInfiniteGrid\|useInfiniteProducts\|ProductFilterChips\|ProductFilterTopDrawer" app components hooks lib --include=*.ts --include=*.tsx
```
Expected: hasil HANYA menunjuk ke definisi di dalam keempat file yang akan dihapus itu sendiri. Kalau ada importer LAIN, **BERHENTI** dan laporkan — jangan hapus.

- [ ] **Step 4: Hapus kode mati**

```bash
git rm components/products/ProductsInfiniteGrid.tsx hooks/useInfiniteProducts.ts components/products/ProductFilterChips.tsx components/products/ProductFilterTopDrawer.tsx
```

- [ ] **Step 5: Cek**

Run: `npx tsc --noEmit`
Expected: 0 error non-vitest.

Run: `npm run lint`
Expected: 0 errors. Kalau muncul ERROR "unused var" untuk `_categories`, hapus `categories` dari `Props` komponen DAN dari pemanggilnya di `app/products/page.tsx`.

Run: `curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3022/products"`
Expected: `200`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(products): katalog pindah ke stack search

Shell server memakai parseProductsParams + EtalaseBand desktop; sticky header
jadi mobile-only dan chip filter lamanya dibuang karena menulis param
new/popular yang tidak lagi menyaring apa pun. Grid infinite lama + hook
cursor-nya ikut dihapus."
```

---

## Task 8: Verifikasi penuh + cakupan diff

**Files:** tidak ada (verifikasi saja)

- [ ] **Step 1: Cek statis**

Run: `npx tsc --noEmit` → 0 error non-vitest.
Run: `npm run lint` → 0 errors.
Run: `npm test` → hanya 6 kegagalan vitest baseline; tes baru dari Task 1–3 lulus.
Run: `npx next build` → **sukses penuh** (kegagalan = regresi nyata).

- [ ] **Step 2: Semua link lama harus tetap hidup**

Tunggu ~3 detik setelah edit terakhir, lalu:

```bash
for u in \
  "/products" \
  "/products?kategori=makanan-kucing" \
  "/products?category=makanan-anjing" \
  "/products?brand=royal-canin" \
  "/products?q=makanan" \
  "/products?popular=best-seller" \
  "/products?popular=trending" \
  "/products?new=last-30-days" \
  "/products?sort=terlaris" \
  "/products?sort=baru" \
  "/products?sort=promo" \
  "/products?promo=1" \
  "/products?diskon=1" ; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3022$u")
  echo "$code  $u"
done
```
Expected: **semua `200`.** Satu pun bukan-200 = link customer rusak; hentikan dan laporkan.

- [ ] **Step 3: Terjemahan param benar-benar menyaring/mengurutkan**

```bash
python - <<'PY'
import json,urllib.request
def get(u):
    with urllib.request.urlopen("http://localhost:3022"+u) as r: return json.load(r)
base=get("/api/search?sort=best_seller&per_page=3")
print("acuan terlaris:", [i['slug'] for i in base['items']])
for label,u in [
  ("kategori","/api/search?category=makanan-kucing&sort=best_seller&per_page=3"),
  ("brand","/api/search?brand=royal-canin&sort=best_seller&per_page=3"),
  ("terbaru","/api/search?sort=newest&per_page=3"),
  ("diskon","/api/search?discount_only=true&sort=best_seller&per_page=3"),
]:
    d=get(u); print(f"{label}: total={d['total']}")
PY
```
Expected: total kategori & brand LEBIH KECIL dari total tanpa filter (1324); urutan `newest` berbeda dari `best_seller`. Catat angkanya.

- [ ] **Step 4: Periksa halaman di browser**

Server dev sudah jalan di `http://localhost:3022`. Pakai Browser preview tool; kalau bermasalah (pernah terjadi di sesi ini), pakai `curl` + `grep` dan katakan begitu di laporan.

Di **1280px**, buka `/products` dan pastikan: `EtalaseBand` tampil (judul "Katalog Produk" + baris trust), sidebar Filter tampil, dropdown "Urutkan" ada, grid 4 kolom, sticky header mobile TIDAK tampil. Lalu centang "Stok tersedia" di sidebar → URL berubah dan jumlah produk berubah, chip "Stok tersedia" muncul, klik "Hapus semua" mengembalikannya.

Di **375px**, pastikan: sticky header mobile tampil (logo + search), tombol "Filter" dan "Urut:" tampil, EtalaseBand TIDAK tampil, grid 2 kolom, tidak ada scroll horizontal.

Cek cepat lewat `curl` untuk kelas-kelas kunci:
```bash
curl -s "http://localhost:3022/products" | grep -o 'md:hidden\|md:grid-cols-\[248px_1fr\]\|hidden md:block' | sort | uniq -c
```

- [ ] **Step 5: Cakupan diff**

```bash
git diff --name-only origin/main...HEAD
git diff --name-only origin/main...HEAD | grep -E "^(flutter_app/|prisma/schema)" && echo "!!! TERLARANG" || echo "CLEAN"
```
Expected: `CLEAN`. Tidak boleh ada `flutter_app/**` atau `prisma/schema.prisma`.

- [ ] **Step 6: Commit catatan (kalau ada)**

```bash
git add -A
git commit -m "chore(products): catatan verifikasi PR4" --allow-empty
```

---

## Self-Review (dijalankan saat penulisan)

- **Cakupan spec §5.1:** container 1280 (Task 7 lewat `PageContainer`) ✓; EtalaseBand + breadcrumb + baris trust (Task 7) ✓; sidebar filter reuse `SearchFilters` + toggle diskon (Task 6) ✓; kategori single-select (Task 6, `slice(-1)`) ✓; bar sort + hitungan (Task 6) ✓; grid 4 kolom + `ProductCard` (Task 6) ✓; chip filter aktif + "Hapus semua" (Task 5) ✓; skeleton (Task 4) ✓; empty state copy app (Task 4) ✓; error "Gagal memuat produk" + "Coba lagi" (Task 6) ✓; bottom-sheet filter & sortir mobile (Task 5–6) ✓.
- **Cakupan §4.8/§4.9:** default `best_seller` ✓; filter dibuang, tidak dibangun ulang ✓; `member_price` (Task 1) ✓; tiga alias nav mati diperbaiki + `promo=1`/`diskon=1` (Task 2) ✓; peta terjemahan param lama lengkap & ber-tes (Task 2) ✓; normalisasi berat (Task 3) ✓.
- **Sengaja TIDAK dikerjakan:** strip "Terakhir kamu lihat" (butuh endpoint riwayat-lihat per-user yang belum ada — fitur tersendiri); video produk di grid (dokumen search tak punya field video, §4.9); Meili reindex untuk `member_price` (Meili mati; dicatat di pesan commit Task 1).
- **Pemindaian placeholder:** tidak ada — tiap langkah berisi kode/perintah literal.
- **Konsistensi tipe:** `ProductsCatalogParams` didefinisikan Task 2 dan dipakai dengan bentuk sama di Task 5 & 6; `searchDocToStoreProduct` didefinisikan Task 3 dan dipanggil Task 6; `ProductsGridSkeleton`/`ProductsEmptyState` (Task 4) dipakai Task 6 & 7 dengan props yang sama; props `ProductCatalogStickyHeader` yang menyusut di Task 8 sudah dipakai bentuk barunya di Task 7 (urutan task disebut eksplisit di catatan Task 7).
- **Cacat urutan yang sudah diperbaiki saat penulisan:** shell halaman dan sticky header semula dipecah jadi dua task, padahal saling bergantung — props header menyusut DAN halaman berhenti mengoper prop lama pada saat yang sama, sehingga typecheck pasti gagal di antara keduanya dan tak bisa di-review terpisah. Keduanya (plus penghapusan kode mati, karena halaman itu pemakai terakhirnya) digabung jadi Task 7. Rencana ini punya **8 task**.
