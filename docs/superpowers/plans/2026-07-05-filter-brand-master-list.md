# Filter Brand Master List + Multi-Brand Server-Side Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Filter sheet halaman Produk menampilkan daftar brand master (di-scope ke kategori aktif kalau ada), dan multi-select brand benar-benar diteruskan ke server — bukan lagi cuma filter lokal terhadap produk yang kebetulan sudah ter-load.

**Architecture:** Backend (`app/api/brands`, `app/api/products`, `lib/products.ts`) menambah dukungan parameter `category` (brands) dan `brands` jamak (products) — murni penambahan parameter opsional, backward compatible, tanpa migrasi. Flutter (`product_service.dart`, `products_screen.dart`) fetch brand master list per kategori aktif (memoized), kirim `_filter.brands` ke server, dan `_FilterSheet` render dari `List<PetBrand>` (bukan `List<String>`) supaya bisa tampilkan count.

**Tech Stack:** Next.js API routes + Prisma (backend), Flutter/Dart (customer app).

## Global Constraints

- **Tidak ada migrasi Prisma.** Semua field yang dibutuhkan (`Brand.slug`, `Product.categoryId`, dll) sudah ada di schema.
- **Backward compatible.** Parameter baru (`category` di `/api/brands`, `brands` di `/api/products`) HARUS opsional — call site lama (`all_brands_screen.dart`, home "Brand Favorit", entry point lain yang kirim `brand` tunggal) tidak boleh berubah perilaku.
- **`brands` (jamak) exact-match by name** — nilai selalu berasal dari respons `/api/brands` milik aplikasi sendiri, TIDAK perlu logic slug/insensitive-fallback seperti `brand` (tunggal) yang menerima input dari berbagai sumber (home card, deep link).
- **Verifikasi backend:** `npm run lint` harus bersih pada file yang disentuh. Tidak ada test existing untuk `lib/products.ts`/`app/api/brands`/`app/api/products` — jangan buat file test baru; verifikasi = lint + manual (curl/browser) sesuai instruksi tiap task.
- **Verifikasi Flutter:** `cd flutter_app && flutter analyze` bersih pada file yang disentuh. Tidak ada widget test existing untuk `products_screen.dart` — jangan buat test baru; verifikasi = analyze + manual di device/emulator.
- **Commit per task.** Bump `flutter_app/pubspec.yaml` version hanya di task terakhir (task Flutter yang membutuhkan build/deploy).

---

### Task 1: Backend — `/api/brands` terima parameter `category`

**Files:**
- Modify: `app/api/brands/route.ts` (seluruh file, 53 baris)

**Interfaces:**
- Consumes: `prisma.brand.findMany`, model `Brand`/`Product`/`Category` (relasi `Product.categoryId` → `Category`, `Product.brandId` → `Brand`, sudah ada di schema).
- Produces: `GET /api/brands?category=<slug>` (opsional) → response shape TIDAK berubah: `{ brands: [{ id, name, slug, logoUrl, productCount }] }`. Kalau `category` diberikan, `productCount` per brand ter-scope ke kategori itu, dan brand yang tidak punya produk di kategori itu TIDAK muncul di list.

- [ ] **Step 1: Ubah `GET` handler untuk baca query param `category` dan scope query**

Ganti seluruh isi file `app/api/brands/route.ts` menjadi:

```ts
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

// Cache 5 menit — list brand jarang berubah, beban DB rendah.
// stale-while-revalidate 1 jam supaya update brand admin cepat propagate
// tapi user request setelah window cache pertama tetap dapat versi cached.
export const revalidate = 300;

export async function GET(request: NextRequest) {
  // Scope opsional ke kategori aktif — dipakai Filter sheet halaman Produk
  // supaya brand yang tampil hanya brand yang benar-benar jual produk di
  // kategori itu (mis. "Makanan Anjing" tidak menampilkan brand aquarium).
  // Tanpa param ini (call site lama: all_brands_screen.dart, home "Brand
  // Favorit"), perilaku identik dengan sebelumnya — list global.
  const categorySlug = (request.nextUrl.searchParams.get("category") ?? "").trim();

  const brands = await prisma.brand
    .findMany({
      where: {
        isActive: true,
        name: { not: "" },
        ...(categorySlug
          ? {
              products: {
                some: {
                  isActive: true,
                  stock: { gt: 0 },
                  category: { slug: categorySlug },
                },
              },
            }
          : {}),
      },
      orderBy: [{ position: "asc" }, { createdAt: "desc" }, { name: "asc" }],
      select: {
        id: true,
        name: true,
        slug: true,
        logoUrl: true,
        // productCount HARUS cocok dengan apa yang user lihat ketika tap
        // brand → /products. Default filter customer app: isActive=true
        // AND stock>0 (lihat ProductCatalogFilter.inStockOnly default).
        // Tanpa stock filter: brand bisa tampilkan "82 produk" tapi user
        // tap → 0 produk (semuanya stok habis) → confusing UX.
        //
        // Kalau categorySlug ada, count juga di-scope ke kategori itu —
        // harus konsisten dengan where clause di atas.
        _count: {
          select: {
            products: {
              where: {
                isActive: true,
                stock: { gt: 0 },
                ...(categorySlug ? { category: { slug: categorySlug } } : {}),
              },
            },
          },
        },
      },
    })
    .catch(() => []);

  return NextResponse.json(
    {
      brands: brands.map((brand) => ({
        id: brand.id,
        name: brand.name,
        slug: brand.slug,
        logoUrl: brand.logoUrl,
        productCount: brand._count.products,
      })),
    },
    {
      headers: {
        "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600",
      },
    }
  );
}
```

- [ ] **Step 2: Lint**

Run: `npm run lint -- app/api/brands/route.ts`
Expected: no errors (warnings pre-existing di file lain boleh diabaikan, tapi file ini harus bersih).

- [ ] **Step 3: Verifikasi manual (server lokal)**

Kalau ada server dev berjalan (`npm run dev`), test dengan curl:
```bash
curl -s "http://localhost:3000/api/brands" | head -c 300
curl -s "http://localhost:3000/api/brands?category=makanan-anjing" | head -c 300
```
Expected: keduanya return `{"brands":[...]}` valid JSON; hasil dengan `category` harus subset (jumlah brand sama atau lebih sedikit) dari tanpa `category`. Kalau tidak ada server dev berjalan, skip step ini dan catat di report — verifikasi akan terjadi end-to-end di Task 5 (manual Flutter test).

- [ ] **Step 4: Commit**

```bash
git add app/api/brands/route.ts
git commit -m "feat(api): /api/brands terima param category untuk scope brand ke kategori aktif"
```

---

### Task 2: Backend — `/api/products` + `lib/products.ts` terima parameter `brands` (jamak)

**Files:**
- Modify: `app/api/products/route.ts:56-127` (fungsi `GET`)
- Modify: `lib/products.ts:661-888` (`getProducts`, `getProductsCount`, `buildProductWhere`)

**Interfaces:**
- Consumes: helper `parseIdList()` yang sudah ada di `app/api/products/route.ts:48-54`.
- Produces: `GET /api/products?brands=Happy+Dog,Pet+Expert` (comma-separated, mirror pola `ids`/`exclude`). `getProducts(opts)` dan `getProductsCount(opts)` terima field baru `brands?: string[]`. `buildProductWhere(opts)` terima `brands?: string[]` — kalau non-empty, filter `brand: { name: { in: brands } }`, MENANG atas `brand` (tunggal) kalau dua-duanya ada.

- [ ] **Step 1: Tambah `brands` di `buildProductWhere` (`lib/products.ts:890-914`)**

Ganti signature function dari:

```ts
function buildProductWhere({
  category,
  brand,
  search,
  createdAtCutoff,
  excludeIds,
  includeIds,
  hasPriceOnly,
  inStockOnly,
  withImageOnly,
  discountOnly,
}: {
  category?: string;
  brand?: string;
  search?: string;
  createdAtCutoff?: Date | null;
  excludeIds?: string[];
  includeIds?: string[];
  hasPriceOnly?: boolean;
  inStockOnly?: boolean;
  withImageOnly?: boolean;
  /** Filter produk yang sedang dalam promo (Flash Sale aktif ATAU
   *  Promo Toko aktif via ProductDiscountItem). */
  discountOnly?: boolean;
}): Prisma.ProductWhereInput {
```

menjadi (tambah `brands` di destructure + type):

```ts
function buildProductWhere({
  category,
  brand,
  brands,
  search,
  createdAtCutoff,
  excludeIds,
  includeIds,
  hasPriceOnly,
  inStockOnly,
  withImageOnly,
  discountOnly,
}: {
  category?: string;
  brand?: string;
  /** Multi-select brand names (exact match) — dari Filter sheet checkbox
   *  Flutter. Beda dengan `brand` (tunggal, dari home card tap / deep
   *  link, terima slug ATAU nama case-insensitive). Nilai `brands` selalu
   *  berasal dari respons /api/brands kita sendiri, jadi exact-match by
   *  name sudah cukup — tidak perlu slug/insensitive fallback. Menang
   *  atas `brand` kalau dua-duanya di-set (kasus langka). */
  brands?: string[];
  search?: string;
  createdAtCutoff?: Date | null;
  excludeIds?: string[];
  includeIds?: string[];
  hasPriceOnly?: boolean;
  inStockOnly?: boolean;
  withImageOnly?: boolean;
  /** Filter produk yang sedang dalam promo (Flash Sale aktif ATAU
   *  Promo Toko aktif via ProductDiscountItem). */
  discountOnly?: boolean;
}): Prisma.ProductWhereInput {
```

- [ ] **Step 2: Ganti blok `brand` di return object (`lib/products.ts:1011-1025`) supaya `brands` menang kalau ada**

Ganti:

```ts
    // Brand filter — accept BOTH slug ("whiskas") and display name ("Whiskas")
    // case-insensitive. Flutter customer app kirim brand.name dari home card
    // sedangkan admin/seo URL pakai slug. Server normalize keduanya supaya
    // tidak ada mismatch (lihat fix ini di komentar product_service.dart).
    ...(brand
      ? {
          brand: {
            isActive: true,
            OR: [
              { slug: brand },
              { name: { equals: brand, mode: "insensitive" as const } },
            ],
          },
        }
      : {}),
```

menjadi:

```ts
    // Multi-select brand (Filter sheet checkbox) — exact match by name,
    // menang atas `brand` tunggal kalau dua-duanya di-set.
    ...(brands && brands.length > 0
      ? { brand: { name: { in: brands } } }
      : brand
        ? {
            // Brand filter tunggal — accept BOTH slug ("whiskas") dan
            // display name ("Whiskas") case-insensitive. Flutter customer
            // app kirim brand.name dari home card sedangkan admin/seo URL
            // pakai slug. Server normalize keduanya supaya tidak ada
            // mismatch (lihat fix ini di komentar product_service.dart).
            brand: {
              isActive: true,
              OR: [
                { slug: brand },
                { name: { equals: brand, mode: "insensitive" as const } },
              ],
            },
          }
        : {}),
```

- [ ] **Step 3: Tambah `brands` di `getProducts` (`lib/products.ts:661-711`)**

Tambah field `brands?: string[];` di object type parameter `opts` (setelah `brand?: string;`), destructure `brands` dari `opts ?? {}`, dan teruskan ke `buildProductWhere`:

```ts
export async function getProducts(opts?: {
  category?: string;
  brand?: string;
  brands?: string[];
  search?: string;
  take?: number;
  skip?: number;
  newFilter?: NewProductFilter;
  popularFilter?: PopularFilter;
  randomSeed?: string;
  excludeIds?: string[];
  /** Filter HANYA produk dengan ID dalam list ini. Dipakai wishlist
   *  untuk fetch produk yang specific di-favorit (bypass pagination
   *  + inStock filter standar). */
  includeIds?: string[];
  hasPriceOnly?: boolean;
  inStockOnly?: boolean;
  withImageOnly?: boolean;
  /** Filter produk yang sedang ada diskon aktif (Flash Sale atau Promo Toko) */
  discountOnly?: boolean;
  viewerId?: string | null;
}): Promise<StoreProduct[]> {
  const {
    category,
    brand,
    brands,
    search,
    take,
    skip,
    newFilter,
    popularFilter,
    randomSeed,
    excludeIds,
    includeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
    discountOnly,
    viewerId,
  } = opts ?? {};
  const createdAtCutoff = newProductCutoff(newFilter);
  const where = buildProductWhere({
    category,
    brand,
    brands,
    search,
    createdAtCutoff,
    excludeIds,
    includeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
    discountOnly,
  });
```

- [ ] **Step 4: Guard `randomSeed` fallback path supaya tidak aktif kalau `brands` di-set (`lib/products.ts:758-769`)**

Cari blok:

```ts
    if (
      randomSeed &&
      !category &&
      !brand &&
      !search &&
      !newFilter &&
      !popularFilter &&
      !excludeIds?.length &&
      !hasPriceOnly &&
      !inStockOnly &&
      !withImageOnly
    ) {
```

Tambah `!brands?.length &&` setelah `!brand &&`:

```ts
    if (
      randomSeed &&
      !category &&
      !brand &&
      !brands?.length &&
      !search &&
      !newFilter &&
      !popularFilter &&
      !excludeIds?.length &&
      !hasPriceOnly &&
      !inStockOnly &&
      !withImageOnly
    ) {
```

(Tanpa guard ini, random-seed homepage-browsing mode bisa aktif walau user sudah pilih multi-brand, karena kondisi lama tidak tahu soal `brands`.)

- [ ] **Step 5: Tambah `brands` di `getProductsCount` (`lib/products.ts:821-859`)**

Sama seperti Step 3, tambah field `brands?: string[];` di type parameter, destructure, teruskan ke `buildProductWhere`:

```ts
export async function getProductsCount(opts?: {
  category?: string;
  brand?: string;
  brands?: string[];
  search?: string;
  newFilter?: NewProductFilter;
  popularFilter?: PopularFilter;
  excludeIds?: string[];
  includeIds?: string[];
  hasPriceOnly?: boolean;
  inStockOnly?: boolean;
  withImageOnly?: boolean;
  discountOnly?: boolean;
}): Promise<number> {
  const {
    category,
    brand,
    brands,
    search,
    newFilter,
    popularFilter,
    excludeIds,
    includeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
    discountOnly,
  } = opts ?? {};
  const createdAtCutoff = newProductCutoff(newFilter);
  const where = buildProductWhere({
    category,
    brand,
    brands,
    search,
    createdAtCutoff,
    excludeIds,
    includeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
    discountOnly,
  });
```

- [ ] **Step 6: Parse & teruskan `brands` di `app/api/products/route.ts` GET handler**

Cari baris (`app/api/products/route.ts:75`):

```ts
  const brand = (sp.get("brand") ?? "").trim();
```

Tambah tepat setelahnya:

```ts
  const brand = (sp.get("brand") ?? "").trim();
  // Multi-select brand dari Filter sheet checkbox — comma-separated,
  // exact match by name (reuse parseIdList, sama pola dengan ids/exclude).
  const brandsList = parseIdList(sp.get("brands"));
```

Lalu update KEDUA pemanggilan (`getProducts` dan `getProductsCount`, `app/api/products/route.ts:95-127`) untuk teruskan `brands: brandsList.length > 0 ? brandsList : undefined`. Ganti:

```ts
  const [items, total] = await Promise.all([
    getProducts({
      category: category || undefined,
      brand: brand || undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      randomSeed:
        seed && !category && !brand && !search && !newFilter && !popularFilter ? seed : undefined,
      take: limit,
      skip: cursor,
      excludeIds,
      includeIds: includeIds.length > 0 ? includeIds : undefined,
      // Wishlist tidak filter stok — produk stok 0 yang sudah
      // di-wishlist harus tetap visible (sesuai spec).
      hasPriceOnly,
      inStockOnly: includeIds.length > 0 ? false : inStockOnly,
      withImageOnly,
      discountOnly,
      viewerId: session?.sub ?? null,
    }),
    getProductsCount({
      category: category || undefined,
      brand: brand || undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      excludeIds,
      includeIds: includeIds.length > 0 ? includeIds : undefined,
      hasPriceOnly,
      inStockOnly: includeIds.length > 0 ? false : inStockOnly,
      withImageOnly,
      discountOnly,
    }),
  ]);
```

menjadi:

```ts
  const [items, total] = await Promise.all([
    getProducts({
      category: category || undefined,
      brand: brand || undefined,
      brands: brandsList.length > 0 ? brandsList : undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      randomSeed:
        seed && !category && !brand && !brandsList.length && !search && !newFilter && !popularFilter
          ? seed
          : undefined,
      take: limit,
      skip: cursor,
      excludeIds,
      includeIds: includeIds.length > 0 ? includeIds : undefined,
      // Wishlist tidak filter stok — produk stok 0 yang sudah
      // di-wishlist harus tetap visible (sesuai spec).
      hasPriceOnly,
      inStockOnly: includeIds.length > 0 ? false : inStockOnly,
      withImageOnly,
      discountOnly,
      viewerId: session?.sub ?? null,
    }),
    getProductsCount({
      category: category || undefined,
      brand: brand || undefined,
      brands: brandsList.length > 0 ? brandsList : undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      excludeIds,
      includeIds: includeIds.length > 0 ? includeIds : undefined,
      hasPriceOnly,
      inStockOnly: includeIds.length > 0 ? false : inStockOnly,
      withImageOnly,
      discountOnly,
    }),
  ]);
```

- [ ] **Step 7: Lint**

Run: `npm run lint -- lib/products.ts app/api/products/route.ts`
Expected: no errors di dua file ini.

- [ ] **Step 8: Verifikasi manual (server lokal, kalau tersedia)**

```bash
curl -s "http://localhost:3000/api/products?brands=Happy%20Dog,Pet%20Expert&limit=5" | head -c 500
```
Expected: `items` yang di-return semuanya punya `brand` salah satu dari dua nama itu. Kalau tidak ada server dev berjalan, skip — verifikasi end-to-end di Task 5.

- [ ] **Step 9: Commit**

```bash
git add lib/products.ts app/api/products/route.ts
git commit -m "feat(api): /api/products terima param brands (multi-select, exact match by name)"
```

---

### Task 3: Flutter — `product_service.dart` kirim `category`/`brands` ke backend baru

**Files:**
- Modify: `flutter_app/lib/services/product_service.dart:152-197` (`fetchProducts`), `:400-413` (`fetchBrands`)

**Interfaces:**
- Consumes: `apiClient.getJson(String path, {Map<String, dynamic>? query})` (sudah ada, tidak berubah).
- Produces: `fetchProducts({..., Set<String>? brands})` — kirim `brands` sebagai query param comma-separated. `fetchBrands({String? category})` — kirim `category` sebagai query param kalau non-null/non-empty. Kedua signature TETAP backward compatible (parameter baru opsional, default null).

- [ ] **Step 1: Tambah parameter `brands` di `fetchProducts` (`flutter_app/lib/services/product_service.dart:152-197`)**

Ganti:

```dart
  Future<ProductResult> fetchProducts({
    String? brand,
    String? category,
    String? query,
    int limit = 30,
    String? newFilter,
    String? popularFilter,
    bool inStock = false,
    bool hasPrice = false,
    bool withImage = false,

    /// Filter produk yang sedang diskon (Flash Sale aktif atau Promo
    /// Toko aktif). Server-side filter — lebih akurat dari client-side
    /// karena tidak terkubur di limit pagination.
    bool discountOnly = false,

    /// Filter HANYA produk dengan ID dalam list. Dipakai wishlist.
    /// Backend auto-bypass inStockOnly supaya produk stok 0 yang
    /// di-wishlist tetap muncul.
    List<String>? ids,

    /// Cursor untuk pagination — lanjut dari offset N (response
    /// `nextCursor`). Null = halaman pertama. Dipakai infinite scroll.
    String? cursor,
  }) async {
    try {
      final keyword = query?.trim() ?? '';
      final data = await apiClient.getJson(
        '/api/products',
        timeout: const Duration(seconds: 15),
        query: {
          if (keyword.isNotEmpty) 'search': keyword,
          if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
          'limit': '$limit',
          if (newFilter != null) 'new': newFilter,
          if (popularFilter != null) 'popular': popularFilter,
          if (inStock) 'inStock': 'true',
          if (hasPrice) 'hasPrice': 'true',
          if (withImage) 'withImage': 'true',
          if (discountOnly) 'discountOnly': 'true',
          if (ids != null && ids.isNotEmpty) 'ids': ids.join(','),
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
      );
```

menjadi (tambah param `brands` + query key `brands`):

```dart
  Future<ProductResult> fetchProducts({
    String? brand,

    /// Multi-select brand names (dari Filter sheet checkbox) — dikirim
    /// server-side, bukan lagi cuma filter lokal terhadap produk yang
    /// sudah ter-load. Beda dengan `brand` (tunggal, dari home card tap).
    Set<String>? brands,
    String? category,
    String? query,
    int limit = 30,
    String? newFilter,
    String? popularFilter,
    bool inStock = false,
    bool hasPrice = false,
    bool withImage = false,

    /// Filter produk yang sedang diskon (Flash Sale aktif atau Promo
    /// Toko aktif). Server-side filter — lebih akurat dari client-side
    /// karena tidak terkubur di limit pagination.
    bool discountOnly = false,

    /// Filter HANYA produk dengan ID dalam list. Dipakai wishlist.
    /// Backend auto-bypass inStockOnly supaya produk stok 0 yang
    /// di-wishlist tetap muncul.
    List<String>? ids,

    /// Cursor untuk pagination — lanjut dari offset N (response
    /// `nextCursor`). Null = halaman pertama. Dipakai infinite scroll.
    String? cursor,
  }) async {
    try {
      final keyword = query?.trim() ?? '';
      final data = await apiClient.getJson(
        '/api/products',
        timeout: const Duration(seconds: 15),
        query: {
          if (keyword.isNotEmpty) 'search': keyword,
          if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
          if (brands != null && brands.isNotEmpty) 'brands': brands.join(','),
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
          'limit': '$limit',
          if (newFilter != null) 'new': newFilter,
          if (popularFilter != null) 'popular': popularFilter,
          if (inStock) 'inStock': 'true',
          if (hasPrice) 'hasPrice': 'true',
          if (withImage) 'withImage': 'true',
          if (discountOnly) 'discountOnly': 'true',
          if (ids != null && ids.isNotEmpty) 'ids': ids.join(','),
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
      );
```

- [ ] **Step 2: Tambah parameter `category` di `fetchBrands` (`flutter_app/lib/services/product_service.dart:400-413`)**

Ganti:

```dart
  Future<List<PetBrand>> fetchBrands() async {
    try {
      final data = await apiClient.getJson('/api/brands');
      final map = _asMap(data);
      final raw = map == null ? data : (map['brands'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PetBrand.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
```

menjadi:

```dart
  /// Fetch daftar brand. `category` opsional (slug) — scope brand ke
  /// kategori itu (dipakai Filter sheet halaman Produk saat kategori
  /// aktif). Tanpa `category`, return daftar brand global (perilaku
  /// lama, dipakai all_brands_screen.dart & home "Brand Favorit").
  Future<List<PetBrand>> fetchBrands({String? category}) async {
    try {
      final data = await apiClient.getJson(
        '/api/brands',
        query: {
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
        },
      );
      final map = _asMap(data);
      final raw = map == null ? data : (map['brands'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PetBrand.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
```

- [ ] **Step 3: Analyze**

Run: `cd flutter_app && flutter analyze lib/services/product_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/services/product_service.dart
git commit -m "feat(service): fetchProducts terima brands, fetchBrands terima category"
```

---

### Task 4: Flutter — `products_screen.dart` master brand list wiring + `_FilterSheet` render

**Files:**
- Modify: `flutter_app/lib/screens/products_screen.dart` — tambah import, state, method baru; modifikasi `initState`, `_loadProducts`, `_loadMore`, `_openFilterSheet`, dan `_FilterSheet`/`_FilterSheetState` (tipe `allBrands` + render checkbox).

**Interfaces:**
- Consumes: `productService.fetchBrands({String? category})` dan `productService.fetchProducts({..., Set<String>? brands})` dari Task 3. `PetBrand` model (`flutter_app/lib/models/brand.dart`, fields: `name`, `slug`, `logoUrl`, `productCount`).
- Produces: — (state `_allBrands` dan tipe `_FilterSheet.allBrands` internal ke task ini, tidak dikonsumsi task lain).

Task ini digabung dalam satu unit (bukan dipecah 2 task) karena
langkah 1-6 (screen-state wiring) meninggalkan `flutter analyze` error
di tengah jalan (`_FilterSheet.allBrands` masih `List<String>` sementara
`_allBrands` sudah `List<PetBrand>`) yang baru valid setelah langkah
7-9 (`_FilterSheet` type change) selesai — reviewer tidak bisa menilai
langkah 1-6 terpisah dari 7-9.

- [ ] **Step 1: Tambah import `PetBrand`**

Di `flutter_app/lib/screens/products_screen.dart`, cari baris import (sekitar baris 13):

```dart
import '../models/home_category.dart';
```

Tambah tepat setelahnya:

```dart
import '../models/home_category.dart';
import '../models/brand.dart';
```

- [ ] **Step 2: Tambah state `_allBrands` + guard memoisasi kategori**

Cari (`flutter_app/lib/screens/products_screen.dart:126-131`):

```dart
  // Daftar kategori MASTER dari /api/categories (semua kategori yang punya
  // produk aktif + jumlahnya). Dipakai untuk isi filter sheet — sebelumnya
  // sheet derive dari produk yang KEBETULAN ter-load (page 1 = 24 produk),
  // jadi cuma muncul 2 kategori walau DB punya 20. Fallback ke derived
  // (_categories) kalau fetch master gagal.
  List<HomeCategory> _allCategories = const [];
```

Tambah tepat setelahnya:

```dart
  // Daftar brand MASTER dari /api/brands, di-scope ke _filter.category
  // kalau ada kategori aktif (brand yang tidak jual produk di kategori
  // itu tidak muncul). Sebelumnya Filter sheet derive brand dari
  // _result.products (produk yang KEBETULAN ter-load/hasil search) —
  // search kata sempit ("happy dog") cuma nampilkan 2 brand walau
  // katalog punya puluhan. Fetch ulang HANYA kalau kategori berubah
  // (bukan tiap keystroke search) — lihat guard di _loadProducts.
  List<PetBrand> _allBrands = const [];
  String? _brandsFetchedForCategory;
```

- [ ] **Step 3: Tambah method `_loadAllBrands()` (fetch + guard memoisasi)**

Cari method `_loadAllCategories()` (`flutter_app/lib/screens/products_screen.dart:288-299`):

```dart
  /// Fetch daftar kategori master (/api/categories) untuk filter sheet.
  /// Fire-and-forget — kalau gagal, sheet fallback ke kategori yang
  /// ter-derive dari produk ter-load (_categories getter).
  Future<void> _loadAllCategories() async {
    try {
      final cats = await productService.fetchCategories();
      if (!mounted) return;
      setState(() => _allCategories = cats);
    } catch (_) {
      // Diam — fallback derived categories tetap jalan.
    }
  }
```

Tambah method baru tepat setelahnya:

```dart

  /// Fetch daftar brand master (/api/brands), di-scope ke `_filter.category`
  /// kalau ada. Dipanggil dari `_loadProducts()` HANYA kalau kategori
  /// berubah sejak fetch terakhir (guard `_brandsFetchedForCategory`) —
  /// supaya tidak refetch brand di setiap keystroke search (yang juga
  /// men-trigger `_loadProducts`). Fire-and-forget — kalau gagal, Filter
  /// sheet tampilkan "Belum ada brand di katalog." (guard `allBrands.isEmpty`
  /// yang sudah ada di _FilterSheet).
  Future<void> _loadAllBrands() async {
    final category = _filter.category;
    try {
      final brands = await productService.fetchBrands(category: category);
      if (!mounted) return;
      setState(() {
        _allBrands = brands;
        _brandsFetchedForCategory = category;
      });
    } catch (_) {
      // Diam — Filter sheet fallback ke "Belum ada brand di katalog."
    }
  }
```

- [ ] **Step 4: Panggil `_loadAllBrands()` di `initState` dan di akhir `_loadProducts()`**

Di `initState` (`flutter_app/lib/screens/products_screen.dart:284`), cari:

```dart
    _loadAllCategories();
    _loadProducts();
```

Ganti jadi:

```dart
    _loadAllCategories();
    _loadAllBrands();
    _loadProducts();
```

Lalu di `_loadProducts()` (`flutter_app/lib/screens/products_screen.dart:403-438`), cari blok akhir:

```dart
    if (!mounted || epoch != _loadEpoch) return;
    setState(() {
      _result = result;
      _nextCursor = result.nextCursor;
      _hasMore = result.nextCursor != null;
      _loading = false;
    });
  }
```

(ini muncul PERSIS di `_loadProducts`, beda dengan `_loadMore` yang punya blok `setState` berbeda — pastikan match method yang benar, yaitu yang langsung mengikuti `Future<void> _loadProducts() async {`). Ganti jadi:

```dart
    if (!mounted || epoch != _loadEpoch) return;
    setState(() {
      _result = result;
      _nextCursor = result.nextCursor;
      _hasMore = result.nextCursor != null;
      _loading = false;
    });
    // Refetch brand master list HANYA kalau kategori berubah sejak fetch
    // terakhir — _loadProducts juga jalan tiap keystroke search, jangan
    // refetch brand di setiap itu.
    if (_filter.category != _brandsFetchedForCategory) {
      _loadAllBrands();
    }
  }
```

- [ ] **Step 5: Kirim `_filter.brands` ke server di `_loadProducts()` dan `_loadMore()`**

Di `_loadProducts()` (`flutter_app/lib/screens/products_screen.dart:415-427`), cari:

```dart
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageSize,
      // cursor: null → fetch dari awal
      category: _filter.category,
      // Brand server-side (sama logic dengan _loadMore — lihat komentar di sana).
      brand: widget.selectedBrand ?? _filter.brand,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
      discountOnly: widget.flashSaleOnly || _filter.discountOnly,
    );
```

Ganti jadi (tambah `brands: _filter.brands`):

```dart
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageSize,
      // cursor: null → fetch dari awal
      category: _filter.category,
      // Brand server-side (sama logic dengan _loadMore — lihat komentar di sana).
      brand: widget.selectedBrand ?? _filter.brand,
      brands: _filter.brands,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
      discountOnly: widget.flashSaleOnly || _filter.discountOnly,
    );
```

Di `_loadMore()` (`flutter_app/lib/screens/products_screen.dart:362-378`), cari:

```dart
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageSize,
      cursor: _nextCursor,
      // Kategori & brand difilter SERVER-SIDE. Backend sekarang accept
      // brand by slug ATAU name (case-insensitive) — fix di
      // lib/products.ts:974. Tanpa ini, brand cuma di-filter client dari
      // produk ter-load page-N → pilih brand kecil = 0 hasil walau ada
      // produk-nya. selectedBrand prioritas (dari home tap Brand Favorit),
      // _filter.brand fallback (dari filter sheet single-brand picker).
      category: _filter.category,
      brand: widget.selectedBrand ?? _filter.brand,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
      discountOnly: widget.flashSaleOnly || _filter.discountOnly,
    );
```

Ganti jadi (tambah `brands: _filter.brands`):

```dart
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageSize,
      cursor: _nextCursor,
      // Kategori & brand difilter SERVER-SIDE. Backend sekarang accept
      // brand by slug ATAU name (case-insensitive) — fix di
      // lib/products.ts:974. Tanpa ini, brand cuma di-filter client dari
      // produk ter-load page-N → pilih brand kecil = 0 hasil walau ada
      // produk-nya. selectedBrand prioritas (dari home tap Brand Favorit),
      // _filter.brand fallback (dari filter sheet single-brand picker).
      // Multi-select brands (checkbox Filter sheet) juga server-side —
      // lihat catatan sama di _loadProducts.
      category: _filter.category,
      brand: widget.selectedBrand ?? _filter.brand,
      brands: _filter.brands,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
      discountOnly: widget.flashSaleOnly || _filter.discountOnly,
    );
```

- [ ] **Step 6: Ganti `_openFilterSheet()` supaya pakai `_allBrands`, bukan derive dari `_result.products`**

Cari (`flutter_app/lib/screens/products_screen.dart:757-793`):

```dart
  Future<void> _openFilterSheet() async {
    FocusScope.of(context).unfocus();
    // Get all unique brands dari current loaded products untuk multi-
    // select brand list. Sort alphabetically untuk UX consistent.
    final allBrands = _result.products
        .map((p) => p.brand.trim())
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    // Compute price range bounds dari product data (max price untuk
    // RangeSlider upper bound). Round up ke nearest 100k untuk UX
    // smooth slider.
    final maxProductPrice = _result.products.isEmpty
        ? 1000000.0
        : _result.products.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    final priceMaxBound = ((maxProductPrice / 100000).ceil() * 100000)
        .clamp(100000, 10000000)
        .toDouble();

    final result = await showModalBottomSheet<ProductCatalogFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FilterSheet(
        currentFilter: _filter,
        allBrands: allBrands,
        priceMaxBound: priceMaxBound,
        // Live preview count — closure ke parent state supaya tetap
        // hitung filter result terbaru tiap toggle di sheet.
        previewCountForFilter: (filter) => _previewFilterMatchCount(filter),
      ),
    );
    if (result == null) return;
    setState(() => _filter = result);
    _loadProducts();
  }
```

Ganti jadi (hapus derive `allBrands` dari `_result.products`, pakai `_allBrands` state):

```dart
  Future<void> _openFilterSheet() async {
    FocusScope.of(context).unfocus();
    // Compute price range bounds dari product data (max price untuk
    // RangeSlider upper bound). Round up ke nearest 100k untuk UX
    // smooth slider.
    final maxProductPrice = _result.products.isEmpty
        ? 1000000.0
        : _result.products.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    final priceMaxBound = ((maxProductPrice / 100000).ceil() * 100000)
        .clamp(100000, 10000000)
        .toDouble();

    final result = await showModalBottomSheet<ProductCatalogFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FilterSheet(
        currentFilter: _filter,
        // Master brand list (di-scope ke kategori aktif kalau ada) — lihat
        // _loadAllBrands(). Bukan lagi derive dari _result.products
        // (produk yang kebetulan ter-load/hasil search sempit).
        allBrands: _allBrands,
        priceMaxBound: priceMaxBound,
        // Live preview count — closure ke parent state supaya tetap
        // hitung filter result terbaru tiap toggle di sheet.
        previewCountForFilter: (filter) => _previewFilterMatchCount(filter),
      ),
    );
    if (result == null) return;
    setState(() => _filter = result);
    _loadProducts();
  }
```

Lanjutkan langsung ke Step 7 di bawah TANPA menjalankan `flutter analyze`
dulu — pada titik ini `_FilterSheet.allBrands` masih bertipe `List<String>`
sedangkan `_allBrands` (state) sudah `List<PetBrand>`, jadi analyze akan
error. Ini normal dan sengaja diperbaiki di Step 7-8 dalam task yang sama
(bukan task terpisah), supaya seluruh task berakhir di state yang bersih
dan bisa direview sebagai satu kesatuan.

- [ ] **Step 7: Ganti tipe parameter `_FilterSheet.allBrands`**

Cari (`flutter_app/lib/screens/products_screen.dart:3112-3126`):

```dart
class _FilterSheet extends StatefulWidget {
  final ProductCatalogFilter currentFilter;
  final List<String> allBrands;
  final double priceMaxBound;

  /// Closure dari parent — compute count match untuk filter candidate.
  /// Update live saat user toggle, displayed di apply button label.
  final int Function(ProductCatalogFilter) previewCountForFilter;

  const _FilterSheet({
    required this.currentFilter,
    required this.allBrands,
    required this.priceMaxBound,
    required this.previewCountForFilter,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}
```

Ganti jadi (`List<String>` → `List<PetBrand>`):

```dart
class _FilterSheet extends StatefulWidget {
  final ProductCatalogFilter currentFilter;
  final List<PetBrand> allBrands;
  final double priceMaxBound;

  /// Closure dari parent — compute count match untuk filter candidate.
  /// Update live saat user toggle, displayed di apply button label.
  final int Function(ProductCatalogFilter) previewCountForFilter;

  const _FilterSheet({
    required this.currentFilter,
    required this.allBrands,
    required this.priceMaxBound,
    required this.previewCountForFilter,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}
```

- [ ] **Step 8: Update bagian checkbox brand supaya pakai `PetBrand.name` + tampilkan count**

Cari blok lengkap (`flutter_app/lib/screens/products_screen.dart:3286-3342`):

```dart
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: _FilterSectionTitle('BRAND')),
                        if (_selectedBrands.isNotEmpty)
                          Text(
                            '${_selectedBrands.length}/${widget.allBrands.length}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (widget.allBrands.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Belum ada brand di katalog.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      ...visibleBrands.map((brand) {
                        final selected = _selectedBrands.contains(brand);
                        return _FilterCheckRow(
                          label: brand,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedBrands.remove(brand);
                              } else {
                                _selectedBrands.add(brand);
                              }
                            });
                          },
                        );
                      }),
                    if (hasMoreBrands && !_brandListExpanded)
                      TextButton(
                        onPressed: () =>
                            setState(() => _brandListExpanded = true),
                        child: Text(
                          'Lihat semua ${widget.allBrands.length} brand →',
                          style: const TextStyle(
                            color: Color(0xFF2568C7),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
```

Ganti jadi (`brand` sekarang objek `PetBrand`, label pakai `brand.name`, tampilkan `brand.productCount`, `_selectedBrands` tetap `Set<String>` berisi nama):

```dart
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: _FilterSectionTitle('BRAND')),
                        if (_selectedBrands.isNotEmpty)
                          Text(
                            '${_selectedBrands.length}/${widget.allBrands.length}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (widget.allBrands.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Belum ada brand di katalog.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      ...visibleBrands.map((brand) {
                        final selected = _selectedBrands.contains(brand.name);
                        return _FilterCheckRow(
                          label: '${brand.name} (${brand.productCount})',
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedBrands.remove(brand.name);
                              } else {
                                _selectedBrands.add(brand.name);
                              }
                            });
                          },
                        );
                      }),
                    if (hasMoreBrands && !_brandListExpanded)
                      TextButton(
                        onPressed: () =>
                            setState(() => _brandListExpanded = true),
                        child: Text(
                          'Lihat semua ${widget.allBrands.length} brand →',
                          style: const TextStyle(
                            color: Color(0xFF2568C7),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
```

- [ ] **Step 9: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/products_screen.dart`
Expected: `No issues found!` — error type-mismatch dari Step 6 sudah hilang karena tipe `allBrands` sekarang cocok (`List<PetBrand>`).

- [ ] **Step 10: Commit**

```bash
git add flutter_app/lib/screens/products_screen.dart
git commit -m "feat(products): filter sheet pakai master brand list + kirim brands ke server"
```

---

### Task 5: Verifikasi manual di device/emulator + bump versi

**Files:**
- Modify: `flutter_app/pubspec.yaml` (version)

- [ ] **Step 1: Analyze penuh (lintas-file)**

Run: `cd flutter_app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Verifikasi manual di device/emulator**

Build & jalankan app (`flutter run` atau via Codemagic), lalu cek:
1. Buka halaman Produk TANPA kategori aktif ("Semua") → cari kata sempit
   (mis. "happy dog") → buka Filter → BRAND harus tampilkan SEMUA brand
   katalog (bukan cuma 1-2 brand yang match search), masing-masing
   dengan angka count, mis. "Happy Dog (12)".
2. Dari Beranda, tap shortcut kategori (mis. "Makanan Anjing") → halaman
   Produk terbuka dengan kategori aktif → buka Filter → BRAND hanya
   menampilkan brand yang benar-benar jual produk di kategori itu (brand
   aquarium/kucing-only tidak muncul).
3. Di Filter, centang 1 brand yang kemungkinan TIDAK ada di 24 produk
   pertama yang ter-load (mis. brand dengan count kecil) → tap
   "Tampilkan X produk" → hasil grid menampilkan produk brand itu (BUKAN
   "Belum ada produk yang cocok" / grid kosong).
4. Reset filter → BRAND checklist kembali ke daftar master (bukan hilang).

- [ ] **Step 3: Bump versi**

Baca versi saat ini:
```bash
grep "^version:" flutter_app/pubspec.yaml
```
Naikkan satu patch+build (mis. dari `1.0.163+203` → `1.0.164+204` — sesuaikan dengan angka yang terbaca).

- [ ] **Step 4: Commit + push**

```bash
git add flutter_app/pubspec.yaml
git commit -m "chore: bump versi untuk filter brand master list + multi-brand server-side"
git push
```

Catatan deploy: perubahan ini menyentuh BACKEND (`app/api/brands`,
`app/api/products`, `lib/products.ts`) DAN Flutter — Vercel harus
deploy backend TERLEBIH DAHULU sebelum build Codemagic, supaya param
`category`/`brands` baru sudah tersedia saat APK baru dipakai.

---

## Self-Review (penulis plan)

**Spec coverage:**
- Bug 1 (brand list dari search, bukan master) → Task 1 (backend scope) + Task 4 Step 6 (`_openFilterSheet` pakai `_allBrands`) ✅
- Bug 2 (multi-brand tidak dikirim ke server) → Task 2 (backend `brands` param) + Task 4 Step 5 (`_loadProducts`/`_loadMore` kirim `_filter.brands`) ✅
- Keputusan "kategori aktif → brand di-scope, tanpa kategori → global" → Task 1 (`category` opsional di `/api/brands`) + Task 4 Step 2-4 (`_loadAllBrands` pakai `_filter.category`, guard refetch saat kategori berubah) ✅
- Keputusan "tampilkan count" → Task 4 Step 8 (`'${brand.name} (${brand.productCount})'`) ✅
- Backward compatible (`all_brands_screen.dart`, home "Brand Favorit") → Task 1 & 3 param opsional, default behavior tak berubah ✅
- Edge case "tidak auto-clear brand saat ganti kategori" → tidak ada task yang menambah auto-clear, sesuai spec (this is intentionally absent) ✅
- Edge case "live preview count tetap approximate" → tidak disentuh oleh task manapun (out of scope, sesuai spec) ✅

**Placeholder scan:** tidak ada TBD/TODO; semua step berisi kode/aksi konkret dengan before/after lengkap.

**Type consistency:** `_FilterSheet.allBrands` diubah dari `List<String>` → `List<PetBrand>` di Task 4 Step 7, dikonsumsi dari `_allBrands` (Task 4 Step 2, sudah `List<PetBrand>` sejak deklarasi) — satu task, satu commit, tidak ada state antar-task yang tidak konsisten. `_selectedBrands` tetap `Set<String>` (berisi `brand.name`) di semua task — konsisten dengan `ProductCatalogFilter.brands` (`Set<String>`) yang tidak diubah. `buildProductWhere`/`getProducts`/`getProductsCount` semua menerima `brands?: string[]` dengan nama & tipe yang sama persis di Task 2. `fetchProducts({Set<String>? brands})` (Task 3) dikonsumsi persis dengan nama parameter `brands` di Task 4 Step 5.

**Struktur task:** Awalnya Task 4 (screen-state wiring) dan Task 5 (`_FilterSheet` type change) dirancang terpisah, tapi digabung jadi satu Task 4 karena keduanya meninggalkan `flutter analyze` error yang saling bergantung — tidak bisa direview/di-approve independen. Task 5 final (verifikasi + bump versi) sekarang task terakhir.

