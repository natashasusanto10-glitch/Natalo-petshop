# Listing & Discovery Desktop — "Etalase Natalo / Rak Etalase"

**Tanggal:** 2026-07-07 (revisi 2 — konvergensi ke stack search + parity filter Flutter)
**Status:** Disetujui (arah desain), menunggu review spec
**Cakupan:** Halaman discovery desktop — `/products`, `/kategori`, `/brands`, `/search`. Desktop premium; mobile web dipertahankan & dipoles. **Tidak menyentuh Flutter, schema DB, atau logika transaksi.**

---

## 0. Konteks & tujuan

Lanjutan redesign web Next.js (setelah homepage). Halaman listing masih terasa mobile: `/products` cuma filter pills tanpa sidebar, `/kategori` gaya mobile-tab, `/brands` terjebak layout sempit, `/search` sudah punya sidebar tapi masih `max-w-6xl`. Tujuan: jadikan seluruh alur discovery **terasa premium & khas Natalo**, tetap mudah dipakai pembeli awam & terpercaya, dan **setara-fitur dengan app Flutter** (filter/sort selengkap app).

Arah desain "**Etalase Natalo — Rak Etalase**": tiap halaman listing dibingkai sebagai **etalase toko fisik Natalo di Medan** — hangat, terpercaya, "toko tetangga" premium. Identitas tetap: biru `#1E5FBF`, Nunito, token G1 (`--nat-container` 1280, radius, shadow), komponen existing (`PageContainer`, `ResponsiveGrid`, `ProductCard`, `SectionHeader`).

**Keputusan arsitektural inti (revisi ini):** karena owner memilih **filter selengkap Flutter** (harga range, rating minimum, diskon, stok, kategori, brand-multi, + sort harga/rating), dan investigasi menemukan endpoint **`/api/search` sudah mendukung hampir semuanya lewat fallback murni-Prisma** (jalan walau Meilisearch mati), maka **`/products` dialihkan memakai stack search yang sama dengan `/search`**. Konsekuensi positif: `/products` dan `/search` **berbagi satu sumber data, satu komponen filter, satu kartu, satu kontrol sort** — jauh lebih konsisten & sedikit kode baru.

## 1. Keputusan yang sudah disepakati

| Topik | Keputusan |
|---|---|
| Arah desain | "Etalase Natalo — Rak Etalase" |
| Pedestal kartu (lit-shelf) | **Hangat/netral saja, setia brand** — satu pedestal netral + garis rak 2px biru natalo. **Aqua dibuang** (bukan warna brand app). Amber hanya untuk cue merchandising (flame "Terlaris", medali peringkat) |
| Filter `/products` | **Selengkap Flutter**: Kategori (single) + Brand (multi) + Stok + **Range harga** + **Rating minimum** + **Diskon-saja** |
| Sort `/products` | Terbaru · Paling Populer · Rating Tertinggi · Harga Terendah · Harga Tertinggi (nama ikut app) |
| Sumber data `/products` | **Stack search** (`/api/search` / `searchProducts`) dengan `q` kosong = browse katalog penuh |
| Klaim trust (dikonfirmasi owner, harus benar) | "Kirim hari ini se-Medan" · "100% Original" · "Toko fisik sejak 2018" · Rating "4.9" (konstanta) |
| Container | 1280 (`--nat-container`) di keempat halaman |
| Mobile | Dipertahankan & dipoles; filter/sort via bottom-sheet ala app |
| Sequencing | 3 PR (lihat §9) |

## 2. Prinsip & batasan

- **Tanpa** perubahan `flutter_app/**`, schema DB (`prisma/schema.prisma`), atau logika cart/checkout/voucher/loyalty/auth.
- **Tanpa endpoint baru.** `/products` memakai `/api/search` yang sudah ada. Data brand/kategori & count facet dari `/api/search/facets` yang sudah ada.
- **Batas sentuhan backend (bila carve-out §4.4 diambil):** hanya **penambahan read-only additif** pada helper query yang sudah ada (`lib/search.ts` DB-fallback) — mereuse where-logic diskon yang sudah ada & ordering penjualan yang sudah ada di `lib/products.ts`. Tanpa endpoint baru, tanpa schema, tanpa write/transaction. **Default rekomendasi: tunda 2 carve-out ini** (lihat §4.4) supaya PR pertama 100% frontend.
- Reuse/extend komponen & token existing. Hindari palet/font baru. **Web tetap satu-biru `#1E5FBF`** untuk brand & kontrol (tidak mengimpor `#2568C7` app — hindari palet ganda).
- Mobile web byte-preserved untuk perilaku existing; enhancement desktop `md:`-gated; bottom-sheet filter/sort mobile mereuse pola yang ada.
- Klaim trust = janji, bukan dekorasi — hanya yang dikonfirmasi benar (§1). Rating "4.9" satu konstanta.
- Premium **terlihat saat diam** (bukan hanya hover) — supaya lolos review via screenshot statis.

## 3. Signature: "Rak Etalase — the Lit Shelf" (hangat/netral)

Tiap tile produk/kategori/brand duduk di atas **pedestal cahaya hangat lembut yang seragam** (honey-neutral `natalo-50`/amber-50 tipis, radial halus) — melitеralkan etalase kaca toko fisik. **Statis & terlihat saat diam**, hanya makin terang + terangkat saat hover. **Tanpa varian aqua** — netral untuk semua kategori (setia palet app: biru + amber).

Benang merah tunggal: **garis "shelf-line" 2px biru natalo `#1E5FBF`** di bawah kicker masthead, judul section, baris kategori aktif di sidebar, dan wipe-in di bawah nama/harga kartu saat hover. Ini yang menyatukan `/products`, `/kategori`, `/brands`, `/search` jadi satu shopfront. Implementasi: utility radial-gradient + garis di atas token existing (murah, CSS).

## 4. Arsitektur data `/products` (baru)

### 4.1 Satu sumber: stack search
`/products` fetch ke **`/api/search`** (`searchProducts` di `lib/search.ts`) dengan `q` kosong → browse katalog penuh (backend sudah mendukung `q=""` mengembalikan semua produk aktif lalu filter/sort/paginate; fallback murni-Prisma jalan walau Meili mati). Param yang dikirim (semua sudah didukung endpoint):
- `category` (slug, single untuk `/products`), `brand` (multi via `append` berulang), `in_stock=true`, `min_price`, `max_price`, `min_rating`, `sort`, `page`, `per_page=24`.

### 4.2 Sort (nama ikut app, map ke `sort` search)
| Label UI | `sort` |
|---|---|
| Paling Populer *(default)* | `best_seller` |
| Terbaru | `newest` |
| Rating Tertinggi | `rating_desc` (backend siap; hanya tambah opsi UI) |
| Harga Terendah | `price_asc` |
| Harga Tertinggi | `price_desc` |

### 4.3 Paginasi
Search bersifat **page-based** (`page`/`per_page`, balikan `total`/`page`/`per_page`), sedangkan `/products` sekarang cursor/infinite (`useInfiniteProducts`). `/products` diadaptasi ke pola page-based: infinite-scroll tetap (IntersectionObserver existing) tapi menaikkan `page++` alih-alih cursor; tombol "Muat lebih banyak" sebagai fallback. `useInfiniteProducts` diganti/di-fork jadi `useInfiniteSearch` (hook baru client-only) atau `/products` memakai pola fetch `/search` yang sudah ada.

### 4.4 Dua carve-out (butuh sentuhan backend read-only — **default: DITUNDA**)
Semua item lain frontend-only. Dua ini **bukan** bawaan search:
1. **Diskon-saja** — ada di `/api/products` (`discountOnly`), tak ada di search. Untuk memasangnya di search: tambah param `discount_only` + satu cabang `where` di DB-fallback `searchProductsFromDb`, **mereuse where-logic diskon yang sudah ada** (`lib/products.ts:964–990`). Kecil, read-only, tanpa reindex (path Meili menyusul terpisah bila Meili diaktifkan).
2. **"Paling Populer" berbasis penjualan asli** — `best_seller` di search sekarang proksi jumlah-ulasan/rating (bukan penjualan). Penjualan asli ada di `/api/products` (`popular=best-seller`, agregasi `OrderItem`). Menyamakan butuh agregasi `OrderItem` di DB-fallback search (sedang, read-only) atau indeks `sold_count` (lebih besar).

**Rekomendasi:** ship PR1–PR2 tanpa dua carve-out ini — pakai proksi `best_seller` yang ada untuk label "Paling Populer" (cukup layak untuk sort listing), dan **tunda "Diskon-saja"** ke follow-up backend kecil (§11). Bila owner ingin keduanya sekarang, jadikan **PR3 backend-read-only** (§9). Keputusan ini dikonfirmasi di review gate.

## 5. Desain per halaman

### 5.1 `/products` (inti)
- **Container** `max-w-6xl` → `PageContainer` (1280), di bawah sticky header mobile yang tidak diubah.
- **Band "Etalase"** (ringkas, non-sticky):
  - Baris 1: breadcrumb `Beranda / Katalog / {Kategori}` + shelf-line vertikal 3px `natalo-500`.
  - Baris 2: judul Nunito `font-extrabold text-3xl`, kontekstual (`activeBrandName` existing → "Katalog Produk" / "Produk {Brand}" / "{Kategori}") + satu kalimat kurasi hangat.
  - **Satu baris meta tipis**: `{N} produk · Kirim hari ini se-Medan · 100% Original · Toko fisik sejak 2018` (soft-tint).
  - Latar wash `natalo-50→putih`, keyline 1px `natalo-100`, `radius-xl`, ditutup shelf-line 2px. Sisi kanan: thumbnail kategori existing di-bleed low-contrast, fallback gradient + watermark paw. Read-only.
- **Sidebar filter desktop** — **reuse & extend `components/SearchFilters.tsx`** (bukan komponen baru). Karena `/products` kini memakai stack search yang sama, `SearchFilters` (`ActiveFilters`: categorySlugs, brandSlugs, minPrice, maxPrice, inStock, minRating) dipakai apa adanya + tambah toggle **Diskon-saja** (bila carve-out diambil). Layout shell `/search`: `md:grid-cols-[248px_1fr]`, `aside hidden md:block`, `sticky top-24`, `radius-lg`, hairline. Grammar chip Natalo (pill single kategori / multi brand / switch stok / range harga / rating bintang). Kategori `/products` disajikan **single-select** (radio) walau backend dukung multi. Count per-brand dari `/api/search/facets`.
  - Mobile: **filter bottom-sheet** ala app (`_FilterSheet`) — seksi HARGA (range) · BRAND (multi, "Lihat semua N") · RATING MINIMUM (4/3/2 ke atas) · STOK · DISKON, tombol apply "Tampilkan N produk" (preview count). Reuse `ProductFilterTopDrawer`/`BottomSheet` existing sebagai wadah.
- **Bar sort + count** (atas kolom 1fr): kiri = "Menampilkan X dari Y produk" (angka `font-black`); kanan = **dropdown "Urutkan"** (5 opsi §4.2, gaya konsisten dengan select sort `/search` — bukan segmented, karena 5 opsi terlalu lebar untuk segmented). Mobile: chip "Urut" + BottomSheet ala app ("Urutkan berdasarkan").
- **Grid + kartu**: `ResponsiveGrid` **cap 4 kolom** desktop, `lg:gap-6`. Reuse `ProductCard` default (logika tak diubah) + **lit-shelf pedestal hangat statis** (terlihat diam) + shelf-line wipe saat hover; lift + `scale-[1.03]` existing. **Harga & CTA selalu tampil.** Badge subtle (maks satu soft-tint chip); jangan ulang brand/search term.
- **Chip filter aktif**: baris chip di bawah bar sort — **ekstrak** `FilterChip` yang kini private di `app/search/page.tsx` jadi komponen shared. Pill `natalo-50` + `natalo-700` + × per chip; nilai polos ("Whiskas ×", "≥ Rp50rb ×", "Rating 4+ ×", "Stok tersedia ×"); tanpa prefix "Brand:/Kategori:". Link "Hapus semua" (`natalo-600`). Desktop; mobile pakai inline-clear chips existing.
- **States**: band render instan (nama/blurb/count server-known). `ProductGridSkeleton` restyle 4-up + lit-shelf base + skeleton sidebar (shimmer meniru geometri kartu, tanpa layout-shift — pola app). Apply filter/sort reuse `useTransition` dim existing. **Empty** hangat (copy ikut app): headline "Produk tidak ditemukan", body "Coba kata kunci lain atau ubah filter pencarian.", tombol "Reset Filter", + strip **"Terakhir kamu lihat"** (recently-viewed dari localStorage, client-only, additif) supaya bukan dead-end. **Error**: panel dihangatkan, copy ikut app ("Gagal memuat produk" + "Coba lagi").

### 5.2 `/kategori` (`CategoryTabPage`)
`max-w-6xl` → 1280; tambah band Etalase ("Kategori — Jelajahi rak Natalo", subtitle, total count via `SectionHeader`); tiap tile kategori dapat lit-shelf hangat + shelf-line-on-hover. Baris tab mobile tetap.

### 5.3 `/brands` (`BrandDirectoryClient`) — perbaikan struktural terbesar
Sekarang terjebak `max-w-2xl`/`grid-cols-3` mobile. Desktop → 1280 + band Etalase ("Brand Pilihan — merek terpercaya yang kami stok", brand count, "7 tahun kurasi"); grid logo 4–6 kolom lebih lapang; logo `mix-blend-multiply` existing di tile putih lit-shelf; input "Cari brand" pakai field shared. Grid 3-col mobile dipertahankan.

### 5.4 `/search` — mewarisi & memberi
Sudah memakai stack yang sama. Perubahan: warisi visual band-lite ("Hasil untuk '…'" / "Semua produk"), kartu lit-shelf, `FilterChip` shared. **Tambah opsi sort "Rating Tertinggi"** (`rating_desc`, backend sudah dukung, hanya belum ada di `SORT_OPTIONS`). **Toggle Diskon-saja** di `SearchFilters` (bila carve-out diambil) otomatis menguntungkan `/search` juga. **Migrasi `max-w-6xl` (1152) → `PageContainer` 1280** supaya keempat halaman sejajar.

## 6. Adopsi konkret dari app Flutter (untuk konsistensi mobile↔web)

Disadur (read-only) dari `flutter_app/lib/...`, diterjemahkan ke token web:
- **Anatomi kartu**: badge diskon `-N%` **sudut asimetris** warna rose `#E11D48`; harga `font-black`/w900 (rose bila diskon, `#1E5FBF`/onSurface bila normal); bintang rating `#FACC15`/`#F59E0B` + "N terjual"; pill "Member" `#3B82F6`; pill promo "Hemat s.d. …" (hijau ongkir `#16A34A`/`#ECFDF3`, merah hemat `#EF4444`/`#FEF2F2`). Radius kartu 16–18.
- **Medali peringkat** emas `#F59E0B` / perak `#94A3B8` / perunggu untuk grid "Terlaris" (selaras `lib/rank-badge.ts` yang sudah ada).
- **Chip filter aktif**: fill `#EEF4FF`, teks `#1E5FBF` (web satu-biru), radius pill, × + "Hapus semua".
- **Empty state**: copy & pola recovery strip "Terakhir kamu lihat".
- **Skeleton shimmer** meniru geometri kartu persis (paket shimmer web / CSS).
- **Sort/filter UX mobile**: bottom-sheet "Urutkan berdasarkan" & filter sheet dengan apply "Tampilkan N produk".
- **TIDAK diadopsi**: font app (Plus Jakarta Sans — web tetap Nunito); biru-kontrol `#2568C7` (web tetap `#1E5FBF`); aqua (tak ada di app).

## 7. Komponen (baru vs extend)

- **Reuse/extend (frontend-only)**:
  - `SearchFilters` → dipakai `/products` juga; + toggle Diskon-saja (opsional carve-out); pastikan grammar chip Natalo.
  - `SORT_OPTIONS` `/search` → + "Rating Tertinggi"; dipakai bersama sebagai dropdown "Urutkan".
  - `FilterChip` (private di `/search`) → ekstrak jadi komponen shared.
  - `ProductCard` → lit-shelf pedestal hangat + token badge/harga/rating ala app (§6).
  - `useInfiniteProducts` → fork/ganti `useInfiniteSearch` (page-based, kirim param search penuh), atau `/products` pakai pola fetch `/search`.
  - `ProductsInfiniteGrid` → 4-up grid + lit-shelf + baca param filter penuh dari URL.
- **Baru**: `EtalaseBand` (band header reusable, slug→tagline map); `LitShelf` utility/kelas (pedestal hangat + shelf-line); trust-meta line; `RecentlyViewedStrip` (localStorage, client-only).
- **Edit terstruktur**: `ProductCatalogStickyHeader` (render search+chip di semua breakpoint) → suppress search+chip di `md+` setelah sidebar desktop punya filtering.
- **Backend read-only (opsional, PR3)**: `lib/search.ts` DB-fallback → param `discount_only` + ordering best-seller penjualan-asli (mereuse logika `lib/products.ts`).

## 8. Verifikasi (wajib sebelum klaim selesai)
1. `npm run lint` bersih; `npx tsc --noEmit` tanpa error baru; `npx next build` compile sukses.
2. `npm test` hijau (+ unit test helper murni baru bila ada, mis. slug→tint / sort-param map).
3. Preview `next dev` (DB Preview) di 375/768/1024/1280/1440/1920: band render; sidebar filter berfungsi (kategori single / brand multi / stok / harga / rating); dropdown sort ganti hasil (Terbaru/Populer/Rating/Harga↑↓); grid 4-up lit-shelf terlihat diam; chip aktif + hapus semua; empty & error state; mobile bottom-sheet filter/sort; tanpa overflow horizontal.
4. Cek filter benar-benar memfilter via URL `/api/search?...` (network) & jumlah hasil berubah.
5. `git diff --name-only` — tanpa `flutter_app/**`, tanpa `prisma/schema.prisma`, tanpa logika transaksi; bila PR3 diambil, perubahan `lib/search.ts` hanya read-only additif.

## 9. Sequencing (3 PR)
- **PR1 (visual & container, risiko rendah)**: swap container 1280 (products/kategori/brands/search), `EtalaseBand`, kartu `LitShelf` hangat + token kartu ala app, ekstrak `FilterChip`, dropdown "Urutkan" (+ "Rating Tertinggi" di `/search`), lebarkan `/brands` & `/kategori`.
- **PR2 (fungsional inti, frontend-only)**: alihkan `/products` ke stack search; reuse `SearchFilters` di `/products` (kategori/brand/stok/harga/rating); hook page-based; chip aktif + reset; suppress `ProductCatalogStickyHeader` search/chip di `md+`; bottom-sheet filter/sort mobile; empty/recently-viewed.
- **PR3 (opsional, backend read-only)**: param `discount_only` + best-seller penjualan-asli di DB-fallback search; toggle Diskon-saja di `SearchFilters`. **Hanya bila owner minta parity penuh sekarang.**

## 10. Risiko & mitigasi
- Distinctiveness jangan hanya di `:hover` → lit-shelf **statis**. ✓
- Jangan tumpuk 6–7 band → satu baris meta ringkas. ✓
- Konvergensi ke search: pastikan `q=""` browse & fallback-DB benar di preview (Meili mati) — verifikasi network. ✓
- Paginasi berubah (cursor→page): uji infinite-scroll & "Muat lebih banyak" tak dobel-fetch / tak lompat. ✓
- Default "Paling Populer" pakai proksi rating bila PR3 ditunda — beri tahu owner semantiknya (bukan penjualan asli) di review gate. ✓
- Jangan sembunyikan harga/CTA di hover; jangan 5 kolom. ✓
- Jangan tinggalkan `/search` di 1152 → migrasi sekalian. ✓
- Klaim trust = janji → hanya yang dikonfirmasi owner (§1); rating konstanta. ✓

## 11. Di luar cakupan (fase lanjutan)
Product detail (galeri + sticky purchase panel); cart/checkout desktop; SEO; performance; condense-on-scroll band; indeks `sold_count` di Meilisearch untuk best-seller penjualan-asli via Meili (bila Meili diaktifkan); path Meili untuk `discount_only`.
