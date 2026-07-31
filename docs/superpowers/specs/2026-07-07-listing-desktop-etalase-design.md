# Listing & Discovery Desktop — "Etalase Natalo / Rak Etalase"

**Tanggal:** 2026-07-07 (revisi 3 — arahan parity Flutter: carve-out backend dikerjakan, bukan ditunda)
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

### 4.4 Carve-out backend — **DIKERJAKAN (revisi 3)**

**Arahan owner (2026-07-19): "web saya juga bisa sama dengan Flutter saya".** Target = **parity penuh dengan app Flutter**, bukan sekadar redesign visual. Karena itu keputusan "DITUNDA" di revisi 2 **dibatalkan** — migrasi `/products` ke stack search tidak boleh menurunkan kualitas apa pun, jadi kekurangan search ditutup lebih dulu.

Yang kurang di search dibanding `/api/products` (semua **read-only additif**, tanpa endpoint/schema baru, tanpa reindex karena Meili OFF → `searchProductsFromDb` adalah jalur hidup):
1. **Diskon-saja** — `where` fragment mandiri di `lib/products.ts` (Flash Sale aktif ATAU Promo Toko aktif). Flutter punya toggle "Sedang promo / diskon".
2. **"Paling Populer" penjualan asli** — search sekarang proksi `review_count`. Asli = agregasi `OrderItem` (`getBestSellerProductIds`).
3. **Trending** — skor 14 hari (totalSold·0.5 + pembeli unik·0.3 + hari-beli·0.2), dipakai tile "Trending" di beranda.

**Kendala teknis penting:** `lib/products.ts` sudah `import { productSearchWhere } from "@/lib/search"`, jadi `lib/search.ts` **TIDAK BOLEH** import balik dari `lib/products.ts` (circular). Solusi: ekstrak fungsi ranking + where-diskon ke modul bersama baru `lib/product-ranking.ts` yang di-import kedua sisi.

### 4.5 Bug pre-existing yang wajib ikut diperbaiki
Ditemukan saat investigasi, keduanya menular ke `/products` begitu migrasi:
1. **Produk belum jadi bocor ke pelanggan** — `searchProductsFromDb` hanya filter `isActive: true`, tidak memakai `productIsVisibleWhere()` (`creationState: "ready"`) seperti `/api/products`. Akibatnya produk yang masih `creating` bisa tampil di `/search` **hari ini**, dan akan menyebar ke `/products`. Wajib difix di PR2.
2. **`take: 2000` tanpa `orderBy`** — untuk browse tanpa kata kunci, search memuat 2000 baris **arbitrer** lalu sort di JS. Aman selama katalog < 2000 produk (sekarang ±1.300), tapi diam-diam salah setelah lewat. Minimal: beri `orderBy` deterministik + catat batasnya; ideal: ranking-id-first untuk sort penjualan.

### 4.6 Gotcha implementasi
- `buildDbProductWhere` & `buildDbSearchPageArgs` (`lib/search.ts:288–342`) **diekspor tapi tidak dipakai** oleh `searchProductsFromDb` (yang membangun `where` inline di 799–826). Menambah filter di sana = **kode mati diam-diam**. Tambahkan di builder inline, atau rapikan supaya DB path benar-benar memakainya.
- `discountOnly` versi `where` bisa meloloskan produk yang `discount_price`-nya ternyata `null` (kasus varian). Untuk sama persis dengan badge kartu, saring juga setelah map: `doc.discount_price !== null`.
- `trending` punya filter keras `purchaseFrequencyDays >= 2` → bisa balik sedikit/0 item; siapkan fallback supaya halaman tidak tampak "kosong".

### 4.7 Hasil PR2 + syarat wajib sebelum PR3 (dari review akhir PR2)

**PR2 SELESAI** — search kini setara: `best_seller` pakai penjualan asli (top-2 identik dengan `/api/products?popular=best-seller`), `trending` ada, `discount_only` ada, produk `creating` tidak lagi bocor, `take: 2000` punya urutan deterministik. Diverifikasi live di Preview DB (1324 produk aktif).

**🚧 BLOKER WAJIB UNTUK PR3 — batas 2000 baris.**
`searchProductsFromDb` mengambil maksimal **2000** produk (terbaru dulu), tapi query ranking penjualan **tidak dibatasi**. Selama katalog < 2000 aman. Begitu lewat, best-seller lama bisa di-rank #1 tapi tidak ikut terambil → hilang diam-diam, dan `total` ikut terpotong. **Headroom sekarang: 1324 / 2000 (~676 produk lagi).** PR2 sudah memasang `console.warn` saat menyentuh batas supaya gagalnya berisik, bukan senyap. **PR3 tidak boleh memindahkan `/products` (halaman paling ramai) ke stack ini sebelum** salah satu dikerjakan: (a) ambil produk berdasarkan ranked-ids lebih dulu untuk sort penjualan, atau (b) naikkan batas + pastikan alarm terpantau.

**Keterbatasan Meilisearch (Meili OFF sekarang — dicatat supaya tidak jadi jebakan).**
`searchProductsFromMeili` belum mendukung `discountOnly` maupun `sort=trending`, dan `filterSearchDocs` hanya cek `is_active` sehingga **fix visibilitas `creationState: "ready"` TIDAK berlaku di jalur Meili**. PR2 sudah menambahkan guard: permintaan `discountOnly`/`trending` langsung dilayani DB path (filter yang diam-diam diabaikan lebih berbahaya daripada error). Kalau nanti Meili diaktifkan, `creationState` harus masuk dokumen + reindex sebelum dipercaya.

**Temuan sampingan (bug pre-existing di stack produk, bukan dibuat PR2).**
`/api/products?discountOnly=true` **terlalu longgar**: ia mencocokkan produk yang punya baris promo aktif walau harga efektifnya tidak benar-benar turun — respons API-nya sendiri menunjukkan `discountPrice: null` untuk produk-produk itu. Search lebih ketat (menyaring ulang dengan `discount_price < price_min`, sama dengan syarat badge di kartu) sehingga mengembalikan 0 di Preview DB, yang **lebih jujur**. Kalau nanti pelanggan mengeluh "filter diskon kosong", cek dulu apakah memang tidak ada diskon efektif — bukan bug filter.

### 4.7b Hasil PR3 — bloker batas-2000 DITUTUP + perilaku yang diketahui di atas 2000 baris

**PR3 SELESAI.** `searchProductsFromDb` kini menjalankan ranking lebih dulu, lalu mengambil **kepala** (produk yang pernah terjual, lewat `id IN rankedIds` — tak bisa terpotong) terpisah dari **ekor** (belum pernah terjual, terbaru dulu, dibatasi kuota), lalu menggabungkannya. Best-seller lama tidak bisa lagi hilang diam-diam. Diverifikasi: ketujuh sort mengembalikan id & total **identik** sebelum vs sesudah di Preview DB (1324 produk), dan integritas filter dibuktikan (`min_rating=4`→48, `min_price=100k`→598, jadi rantai `AND` selamat melewati kedua query).

**Perilaku yang diketahui saat katalog melewati 2000 — diwariskan ke PR4, jangan ditemukan ulang:**

- **`total` & facet jadi bergantung-sort.** Di atas batas, `best_seller`/`trending` bisa mencapai `kepala + 2000` sementara `newest` berhenti di 2000. Ini lebih baik daripada pemotongan seragam yang lama, dan **tidak** menghasilkan halaman kosong (array yang sama di-slice), tapi angka "Menampilkan X dari Y" dan hitungan facet akan berubah saat pembeli mengganti sort. Obat sebenarnya: pindahkan filter+paginasi ke SQL.
- **Biaya query di atas batas.** Dua daftar parameter `IN`/`NOT IN` berisi hingga 2000 id per permintaan, dan `orderBy createdAt desc` di bawah `NOT IN` kemungkinan tidak memakai indeks. Dormant sampai katalog ~2000 (headroom hari ini 1324/2000); `console.warn` ekor adalah pemicu untuk meninjau ulang — pantau juga latensi query ekor saat itu.
- **Memori puncak ~2×.** Sort penjualan bisa menghidrasi hingga 4000 baris sekaligus (kepala + ekor) alih-alih 2000. Wajar di skala sekarang; siapa pun yang menaikkan `CATALOG_FETCH_CAP` harus tahu biayanya berlipat.
- **Dua batas, dua warn.** `CATALOG_FETCH_CAP` (ekor) dan `SALES_HEAD_CAP` (kepala) masing-masing punya `console.warn` sendiri. Tidak ada lagi pemotongan yang diam.

**Saran untuk PR4 sebelum memindahkan `/products`:** jalankan sekali uji sintetis di-atas-batas (turunkan sementara `CATALOG_FETCH_CAP` ke mis. 50 di percobaan terpisah) supaya klaim terkuat PR3 — kepala selamat, ekor terpotong — berubah dari "dinalar" jadi "diamati". Preview DB (1324) tidak bisa memicu jalur itu.

### 4.8 Keputusan owner 2026-07-31 (sebelum PR3) — pemecahan, filter yang dibuang, urutan default

Setelah investigasi kode penuh, tiga hal dibawa ke owner karena mengubah apa yang pembeli lihat. Semua sudah diputuskan:

1. **PR3 dipecah dua.** **PR3 = perbaikan bloker batas-2000 saja** (backend, kecil, bisa diverifikasi lewat `/search` yang sudah memakai jalur itu). **PR4 = migrasi halaman `/products`.** Alasan: kalau perbaikan mesin punya bug halus, ketahuannya di `/search` dulu, bukan langsung di katalog — halaman paling ramai.
2. **Filter tanpa padanan di stack search DIBUANG:** `today`, `this-week`, `last-30-days` (dari param `new`) dan `most-searched`, `most-bought` (dari param `popular`). Alasan: app Flutter sendiri tidak punya filter-filter ini, jadi membuangnya justru menyamakan web dengan app sesuai arahan owner. Yang tersisa tetap lengkap: kategori, brand, stok, harga, rating, diskon + sort Terlaris/Terbaru/Rating/Harga↑↓.
3. **Urutan default `/products` = "Paling Populer"** (`sort=best_seller`, penjualan asli). Pengacakan per-kunjungan (`seed`) dibuang — dengan paginasi berbasis halaman, urutan acak tidak bisa dijamin konsisten antar-halaman dan tidak bisa dijelaskan ke pembeli.

**Koreksi penting atas rencana bloker (opsi (a) versi spec ternyata belum lengkap).** "Ambil produk berdasarkan ranked-ids lebih dulu" kalau ditelan mentah akan **menghapus produk yang belum pernah terjual** — padahal sekarang mereka sengaja dipertahankan dan didorong ke ekor (lihat komentar di `searchProductsFromDb`), dan juga diam-diam ikut menerapkan saringan "layak beli" (`productRankWhere`: harga>0 & stok>0) ke hasil yang tampil. Jadi bentuk benarnya: **kepala terurut-penjualan (diambil by ranked-ids) + ekor belum-terjual (terbaru dulu, dibatasi kuota)**, lalu digabung. Ini yang dikerjakan PR3.

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
- **Backend read-only (PR2, wajib untuk parity)**: modul bersama **baru** `lib/product-ranking.ts` (dipakai `lib/products.ts` + `lib/search.ts`, menghindari circular import) → best-seller penjualan-asli, trending, where-diskon; `searchProductsFromDb` + `/api/search` dapat `discount_only`/`sort=trending` & fix visibilitas.
- **Legacy mobile `/products` yang dipensiunkan di `md+` (PR3)**: `ProductFilterChips` (222 baris) & `ProductFilterTopDrawer` (569 baris) tetap untuk mobile; jangan dihapus, cukup di-`md:hidden` supaya perilaku mobile utuh.

## 8. Verifikasi (wajib sebelum klaim selesai)
1. `npm run lint` bersih; `npx tsc --noEmit` tanpa error baru; `npx next build` compile sukses.
2. `npm test` hijau (+ unit test helper murni baru bila ada, mis. slug→tint / sort-param map).
3. Preview `next dev` (DB Preview) di 375/768/1024/1280/1440/1920: band render; sidebar filter berfungsi (kategori single / brand multi / stok / harga / rating); dropdown sort ganti hasil (Terbaru/Populer/Rating/Harga↑↓); grid 4-up lit-shelf terlihat diam; chip aktif + hapus semua; empty & error state; mobile bottom-sheet filter/sort; tanpa overflow horizontal.
4. Cek filter benar-benar memfilter via URL `/api/search?...` (network) & jumlah hasil berubah.
5. `git diff --name-only` — tanpa `flutter_app/**`, tanpa `prisma/schema.prisma`, tanpa logika transaksi; bila PR3 diambil, perubahan `lib/search.ts` hanya read-only additif.

## 9. Sequencing (3 PR — revisi 3)
- **PR1 (visual & container, risiko rendah) — ✅ MERGED (PR #187)**: swap container 1280 (products/kategori/brands/search), `EtalaseBand`, kartu `LitShelf` hangat + token kartu ala app, ekstrak `FilterChip`, opsi sort "Rating Tertinggi" di `/search`, lebarkan `/brands` & `/kategori`.
- **PR2 (parity backend, read-only additif)**: modul bersama `lib/product-ranking.ts` (best-seller penjualan-asli, trending, where-diskon) dipakai `lib/products.ts` **dan** `lib/search.ts`; `searchProductsFromDb` dapat `discount_only`, `best_seller` asli, `trending`; **fix bug visibilitas `creationState: "ready"`** (§4.5.1) + `orderBy` deterministik (§4.5.2); param baru di `/api/search`. Unit test untuk bagian murni. Tanpa endpoint/schema baru.
- **PR3 (frontend `/products`)**: alihkan `/products` ke stack search (kompatibel mundur untuk `?kategori=`/`?brand=`/`?new=`/`?popular=` — lihat §9.1); reuse `SearchFilters` + toggle Diskon-saja; hook page-based; band Etalase di `/products`; chip aktif + reset; suppress `ProductCatalogStickyHeader` search/chip di `md+`; bottom-sheet filter/sort mobile; empty state + "Terakhir kamu lihat".

### 9.1 Kompatibilitas URL (WAJIB — jangan sampai link lama mati)
`/products` dipakai banyak entry point. Semua ini **harus tetap jalan** setelah migrasi:
| URL lama | Dipakai oleh | Terjemahan ke search |
|---|---|---|
| `?kategori=<slug>` | `CategoryTabPage` (×2), `DesktopCategoryNav`, kartu kategori beranda, banner | `category=<slug>` |
| `?brand=<slug>` | redirect `/brand/[slug]`, `lib/brand-catalog.ts`, banner | `brand=<slug>` |
| `?q=` | `ProductSearchInput` | `q=` |
| `?new=last-30-days` | tile beranda "Produk Baru" | `sort=newest` |
| `?popular=best-seller` | tile beranda "Terlaris" + `SectionHeader` | `sort=best_seller` (asli, setelah PR2) |
| `?popular=trending` | tile beranda "Trending" | `sort=trending` (setelah PR2) |
| `?sort=terlaris\|baru\|promo` | `DesktopCategoryNav` | **sekarang no-op** (halaman tak parse `sort`) → petakan `terlaris`→`best_seller`, `baru`→`newest`, `promo`→`discount_only=true` |
| `?promo=1` / `?diskon=1` | beranda, `/promo/[id]` fallback, banner | **sekarang no-op** → `discount_only=true` |
Catatan: tiga baris terakhir adalah **link yang sudah rusak hari ini** (halaman tak pernah membaca `sort`/`promo`/`diskon`); PR2+PR3 sekalian memperbaikinya.

## 10. Risiko & mitigasi
- Distinctiveness jangan hanya di `:hover` → lit-shelf **statis**. ✓
- Jangan tumpuk 6–7 band → satu baris meta ringkas. ✓
- Konvergensi ke search: pastikan `q=""` browse & fallback-DB benar di preview (Meili mati) — verifikasi network. ✓
- Paginasi berubah (cursor→page): uji infinite-scroll & "Muat lebih banyak" tak dobel-fetch / tak lompat. ✓
- Default "Paling Populer" proksi rating → **dibatalkan**: PR2 memasang penjualan asli, jadi tak ada penurunan semantik. ✓
- **Link lama mati** saat `/products` pindah stack → tabel kompatibilitas URL §9.1 wajib dipenuhi & diverifikasi satu per satu. ✓
- **Produk `creating` bocor ke pelanggan** (§4.5.1) → fix di PR2, verifikasi `/search` juga ikut bersih. ✓
- **Circular import** `search` ⇄ `products` → modul bersama `lib/product-ranking.ts`. ✓
- Menambah filter di `buildDbProductWhere` = kode mati (§4.6) → edit builder inline di `searchProductsFromDb`. ✓
- Jangan sembunyikan harga/CTA di hover; jangan 5 kolom. ✓
- Jangan tinggalkan `/search` di 1152 → migrasi sekalian. ✓
- Klaim trust = janji → hanya yang dikonfirmasi owner (§1); rating konstanta. ✓

## 11. Di luar cakupan (fase lanjutan)
Product detail (galeri + sticky purchase panel); cart/checkout desktop; SEO; performance; condense-on-scroll band; indeks `sold_count` di Meilisearch untuk best-seller penjualan-asli via Meili (bila Meili diaktifkan); path Meili untuk `discount_only`.
