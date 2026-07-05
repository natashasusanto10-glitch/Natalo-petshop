# Filter Brand — Master List + Multi-Brand Server-Side (Design Spec)

**Tanggal:** 2026-07-05
**Status:** Disetujui untuk implementasi (menunggu review spec)
**Scope:** Backend (2 endpoint kecil, tanpa migrasi) + Flutter.

## Masalah

Dua bug yang saling terkait di halaman Produk (`flutter_app/lib/screens/products_screen.dart`):

### Bug 1 — Daftar brand di Filter sheet tidak lengkap

`_openFilterSheet()` membangun `allBrands` dari `_result.products`
(`products_screen.dart:761-766`) — yaitu produk yang SEDANG tampil di
layar (hasil server-side search/kategori yang aktif), bukan daftar
master brand. Komentar di kode sendiri menyatakan ini eksplisit: *"Get
all unique brands dari current loaded products"*.

Akibat: search "happy dog" → hasil cuma berisi produk brand Happy Dog +
Pet Expert → Filter sheet cuma tampilkan 2 checkbox brand, padahal
katalog punya puluhan brand lain yang seharusnya bisa dipakai untuk
mem-pivot pencarian.

### Bug 2 — Multi-select brand tidak pernah dikirim ke server

`_filter.brands` (`Set<String>`, diisi checkbox di Filter sheet) HANYA
dipakai untuk filter lokal di getter `_products`
(`products_screen.dart:207-208`, `multiBrandMatch`), terhadap
`_result.products` — produk yang KEBETULAN sudah ter-load di halaman
saat ini. `_loadProducts()` dan `_loadMore()`
(`products_screen.dart:415-427`, `362-379`) hanya mengirim `_filter.brand`
(tunggal) ke `productService.fetchProducts(...)`, TIDAK PERNAH mengirim
`_filter.brands` (jamak).

Akibat: kalau user pilih brand yang produknya belum ter-load di halaman
saat ini (mis. brand kecil, di luar 24 produk pertama), UI salah
menampilkan "0 produk" walau brand itu punya stok di katalog.

Bug 2 baru terasa signifikan SETELAH Bug 1 diperbaiki — saat ini bug 2
"tersamar" karena checkbox brand yang tampil memang selalu subset dari
produk yang sudah ter-load, jadi filter lokal itu kebetulan konsisten.

## Keputusan Desain (disepakati user)

1. **Scope brand list:** kalau kategori aktif (mis. dari shortcut
   Beranda "Makanan Anjing"), brand yang tampil di Filter HANYA brand
   yang punya produk di kategori itu. Kalau tidak ada kategori aktif,
   tampilkan semua brand.
2. **Multi-brand server-side:** diperbaiki sekaligus (bukan ditunda) —
   backend nambah dukungan filter banyak brand, konsisten dengan cara
   single-brand sudah bekerja server-side.
3. **Tampilan count:** setiap brand di checkbox menampilkan jumlah
   produknya, mis. `"Happy Dog (12)"`.

## Kondisi Sekarang (baseline, sudah ada — direuse)

- `productService.fetchBrands()` (`flutter_app/lib/services/product_service.dart:400-410`)
  sudah memanggil `/api/brands`, return `List<PetBrand>` (name, slug,
  logoUrl, productCount). Dipakai di `all_brands_screen.dart` — TIDAK
  dipakai di Filter sheet products_screen.dart saat ini.
- `app/api/brands/route.ts` — return SEMUA brand aktif +
  `productCount` global (scoped ke `isActive: true, stock: { gt: 0 }`
  tapi TIDAK di-scope ke kategori manapun). Tidak terima query param
  apa pun saat ini.
- `app/api/products/route.ts:48-53` — helper `parseIdList(value)` sudah
  ada (comma-separated → `string[]`, dipakai untuk param `ids`/`exclude`).
  Pola ini akan direuse untuk param `brands` baru.
- `lib/products.ts` — where-builder brand tunggal
  (`lib/products.ts:1006-1020`): terima `brand` (slug ATAU nama,
  case-insensitive) via `OR: [{slug}, {name: {equals, insensitive}}]`.
  Perlu ditambah `brands` (jamak) di sampingnya.
- `ProductCatalogFilter.brands` (`products_screen.dart:2753`) — Set
  multi-select, sudah ada, sudah diisi checkbox Filter sheet
  (`_selectedBrands`, `products_screen.dart:3134-3160`) — HANYA belum
  diteruskan ke server.
- `PetBrand` model (`flutter_app/lib/models/brand.dart`) — sudah punya
  field `productCount`, siap dipakai untuk badge count.

## Perubahan

### Backend

**1. `app/api/brands/route.ts`** — tambah query param opsional
`category` (slug). Kalau ada:
```ts
const categorySlug = (req.nextUrl.searchParams.get("category") ?? "").trim();
// ...
const brands = await prisma.brand.findMany({
  where: {
    isActive: true,
    name: { not: "" },
    ...(categorySlug
      ? { products: { some: { isActive: true, stock: { gt: 0 }, category: { slug: categorySlug } } } }
      : {}),
  },
  orderBy: [{ position: "asc" }, { createdAt: "desc" }, { name: "asc" }],
  select: {
    id: true, name: true, slug: true, logoUrl: true,
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
}).catch(() => []);
```
Response shape TIDAK berubah (tetap `{ brands: [...] }`) — backward
compatible untuk `all_brands_screen.dart` yang tidak kirim `category`.

**2. `app/api/products/route.ts` + `lib/products.ts`** — tambah param
`brands` (comma-separated), reuse `parseIdList()`:
```ts
const brandsList = parseIdList(sp.get("brands")); // string[]
```
Teruskan ke `getProducts({ ..., brands: brandsList })`. Di where-builder
(`lib/products.ts`, dekat baris 1010), tambah SEBELUM blok `brand`
tunggal:
```ts
...(brands && brands.length > 0
  ? { brand: { name: { in: brands } } }
  : brand
    ? { brand: { isActive: true, OR: [{ slug: brand }, { name: { equals: brand, mode: "insensitive" as const } }] } }
    : {}),
```
`brands` (jamak) exact-match by name (nilai selalu dari respons
`/api/brands` kita sendiri — tak perlu slug/insensitive fallback
seperti `brand` tunggal yang menerima input dari berbagai sumber:
home card, deep link, dsb). `brands` menang atas `brand` tunggal kalau
kebetulan dua-duanya ada.

### Flutter

**3. `product_service.dart`**
- `fetchBrands({String? category})` — kalau ada, kirim
  `query: {'category': category}`.
- `fetchProducts({..., Set<String>? brands})` — kirim
  `if (brands != null && brands.isNotEmpty) 'brands': brands.join(',')`
  (mirror pola `ids.join(',')` yang sudah ada di baris 194).

**4. `products_screen.dart`**
- State baru: `List<PetBrand> _allBrands = const []`,
  `String? _brandsFetchedForCategory` (memo guard).
- Di akhir `_loadProducts()`, setelah `_result` di-set: kalau
  `_filter.category != _brandsFetchedForCategory`, panggil
  `_loadAllBrands()` (fire-and-forget, silent catch — pola sama dengan
  `_loadAllCategories()`), lalu update `_brandsFetchedForCategory`.
  Ini mencegah refetch brand di setiap keystroke search (karena
  `_loadProducts` juga jalan tiap search berubah) — hanya refetch kalau
  KATEGORI-nya yang berubah.
- `_loadAllBrands()`: `productService.fetchBrands(category: _filter.category)`
  → `setState(() => _allBrands = result)`.
- `_openFilterSheet()`: hapus logic `allBrands` dari `_result.products`
  (baris 761-766) — pakai `_allBrands` langsung sebagai parameter
  `_FilterSheet`.
- `_loadProducts()` dan `_loadMore()`: tambah
  `brands: _filter.brands` ke pemanggilan `productService.fetchProducts(...)`.

**5. `_FilterSheet` (widget di `products_screen.dart:31xx`)**
- Parameter `allBrands` ganti tipe `List<String>` → `List<PetBrand>`.
- `visibleBrands`/`hasMoreBrands`/checkbox loop: pakai `brand.name` untuk
  label dan matching `_selectedBrands` (tetap `Set<String>` berisi
  nama), tampilkan `'${brand.name} (${brand.productCount})'`.
- Baris "Belum ada brand di katalog" tetap untuk kasus `_allBrands.isEmpty`.

## Edge Cases

- Tidak ada kategori aktif (`_filter.category == null`) → `fetchBrands()`
  tanpa param category → daftar brand global (perilaku endpoint yang
  sudah ada, tak berubah).
- User sudah centang brand lalu ganti kategori sehingga brand itu jadi
  tak relevan → dibiarkan tercentang (tidak di-auto-clear); kalau
  hasilnya 0 produk, tombol Reset di Filter sheet sudah tersedia.
- `_previewFilterMatchCount` (live count di tombol "Tampilkan X
  produk") tetap dihitung dari `_result.products` (approximate,
  terbatas pada halaman ter-load) — ini limitasi pre-existing, di luar
  scope perubahan ini, TIDAK diperparah oleh perubahan ini (server
  sudah balikin produk yang benar setelah filter di-apply; hanya
  angka preview SEBELUM apply yang approximate).
- `brands` param kosong/tidak dikirim → perilaku identik dengan
  sebelumnya (backward compatible, tidak breaking untuk entry point
  lain yang tidak pernah kirim `brands`).

## Di Luar Scope (YAGNI)

- Memperbaiki approximate live-preview count di tombol apply — masalah
  pre-existing terpisah.
- Auto-clear brand yang tak relevan saat ganti kategori.
- Mengubah cara single-brand (`brand`, tunggal — dari home card tap)
  bekerja — tetap seperti sekarang.

## Testing

- Manual: search kata sempit (mis. "happy dog") → Filter sheet tetap
  tampilkan brand lengkap (bukan cuma 2).
- Manual: masuk kategori "Makanan Anjing" dari shortcut Beranda → buka
  Filter → brand yang tampil hanya brand yang jual makanan anjing.
- Manual: pilih brand kecil (sedikit produk, kemungkinan di luar
  halaman pertama) → hasil menampilkan produk brand itu (bukan 0).
- Manual: `flutter analyze` bersih pada file yang disentuh; cek
  `app/api/brands` dan `app/api/products` tetap merespons tanpa param
  baru (backward compatible) untuk call site lain (`all_brands_screen.dart`,
  home "Brand Favorit").
