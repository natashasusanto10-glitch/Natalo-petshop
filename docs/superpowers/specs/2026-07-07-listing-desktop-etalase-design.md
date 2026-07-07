# Listing & Discovery Desktop — "Etalase Natalo / Rak Etalase"

**Tanggal:** 2026-07-07
**Status:** Disetujui (arah desain), menunggu review spec
**Cakupan:** Halaman discovery desktop — `/products`, `/kategori`, `/brands`, `/search`. Desktop premium; mobile web dipertahankan. **Tidak menyentuh Flutter, API, atau logika transaksi.**

---

## 0. Konteks & tujuan

Lanjutan redesign web Next.js (setelah homepage). Halaman listing masih terasa mobile: `/products` cuma filter pills tanpa sidebar, `/kategori` gaya mobile-tab, `/brands` terjebak layout sempit, `/search` sudah punya sidebar tapi masih `max-w-6xl`. Tujuan: jadikan seluruh alur discovery **terasa premium & khas Natalo** (bukan grid marketplace generik), tetap mudah dipakai pembeli awam & terpercaya.

Arah desain "**Etalase Natalo — Rak Etalase / The Lit Aisle**" (hasil panel desain 4-arah + juri): tiap halaman listing dibingkai sebagai **etalase toko fisik Natalo di Medan** — hangat, terpercaya, "toko tetangga" premium. Identitas tetap: biru `#1E5FBF`, Nunito, token G1 (`--nat-container` 1280, radius, shadow), komponen existing (`PageContainer`, `ResponsiveGrid`, `ProductCard`, `SectionHeader`).

## 1. Keputusan yang sudah disepakati

| Topik | Keputusan |
|---|---|
| Arah desain | "Etalase Natalo — Rak Etalase" dengan efek **lit-shelf penuh** (glow pedestal per-kategori) |
| Filter `/products` | Kategori (single) + Brand (multi) + Stok (toggle) + Sort flag. **Tanpa harga** (harga tetap eksklusif `/search`) |
| Klaim trust (dikonfirmasi owner, harus benar) | "Kirim hari ini se-Medan" · "100% Original" · "Toko fisik sejak 2018" · Rating "4.9" |
| Container | 1280 (`--nat-container`) di keempat halaman |
| Mobile | Dipertahankan; semua tambahan `md:`-gated |
| Sequencing | 2 PR (lihat §7) |

## 2. Prinsip & batasan

- **Tanpa** perubahan `app/api/**`, `flutter_app/**`, schema DB, atau logika cart/checkout/voucher/loyalty/auth.
- Filter hanya yang **API sudah dukung**: `?kategori=`, `?brands=a,b,c` (multi, sudah diparse `parseIdList`), `?inStock=true` (sudah diparse `parseBooleanFlag`), sort via flag `new=`/`popular=`. **Dilarang** menambah price-sort/price-slider ke `/products`.
- Reuse/extend komponen & token existing. Hindari palet/font baru.
- Mobile web byte-preserved: `ProductFilterChips`, `ProductFilterTopDrawer`, `BottomSheet` tetap; sidebar/enhancement hanya `md+`.
- Klaim trust = janji, bukan dekorasi — pakai hanya yang dikonfirmasi benar (§1). Rating "4.9" jadikan satu konstanta agar mudah diubah.
- Premium **terlihat saat diam** (bukan hanya hover) — supaya lolos review via screenshot statis.

## 3. Signature: "Rak Etalase — the Lit Shelf"

Tiap tile produk/kategori/brand duduk di atas **pedestal cahaya lembut yang menyesuaikan kategori**: hangat madu-biru (`natalo-50`-ish radial) untuk hewan/makanan/mainan, sejuk aqua untuk ikan/aquarium — melitералkan etalase kaca toko fisik + cahaya aquarium, sekaligus menyelesaikan dualitas pet-vs-aquarium (tidak memaksakan satu motif air ke listing anjing/kucing). **Statis & terlihat saat diam**, hanya makin terang + terangkat saat hover.

Benang merah tunggal: **garis "shelf-line" 2px gradasi natalo** yang muncul di bawah kicker masthead, judul section, baris kategori aktif di rail, dan wipe-in di bawah nama/harga kartu saat hover. Ini yang menyatukan `/products`, `/kategori`, `/brands`, `/search` jadi satu shopfront. Implementasi: utility radial-gradient + kelas tint kategori di atas token existing (murah, CSS).

## 4. Desain per halaman

### 4.1 `/products` (inti)

- **Container** `max-w-6xl` → `PageContainer` (1280), di bawah sticky header mobile yang tidak diubah.
- **Band "Etalase"** (ringkas, non-sticky — hindari 6 baris menumpuk):
  - Baris 1: breadcrumb `Beranda / Katalog / {Kategori}` + shelf-line vertikal 3px `natalo-500` sebagai section mark.
  - Baris 2: judul Nunito `font-extrabold text-3xl` (BUKAN `text-4xl font-black` yang terlihat chunky-app), kontekstual via logic `activeBrandName` existing ("Katalog Produk" default / "Produk {Brand}" / "{Kategori}"), + satu kalimat kurasi hangat ("Semua kebutuhan hewan & aquarium, langsung dari toko kami di Medan").
  - **Satu baris meta tipis** (bukan 4-ikon CRO row): `{N} produk · Kirim hari ini se-Medan · 100% Original · Toko fisik sejak 2018` (soft-tint text).
  - Latar wash `natalo-50→putih`, keyline 1px `natalo-100`, `radius-xl`, ditutup shelf-line 2px. Kategori-aware tint (aqua untuk ikan/aquarium). Sisi kanan: thumbnail kategori existing di-bleed low-contrast + duotone, fallback gradient + watermark paw/fin — via map frontend `slug→tagline+tint` (tanpa schema/API).
  - Read-only. Condense-on-scroll **ditunda** (hindari layout-jank).
- **Sidebar filter desktop** — komponen BARU `ProductsFilterSidebar` (sengaja BUKAN varian `SearchFilters`, yang terkopel ke `/api/search` Facets + kategori multi-select). Layout ikut shell `/search`: `md:grid-cols-[248px_1fr]`, `aside hidden md:block`, `sticky top-24 max-h-[calc(100vh-6rem)] overflow-y-auto`, `radius-lg`, hairline, lapang. Grammar chip:
  - **Kategori** — pill single-select (radio), "Semua Produk" dipin atas; aktif = fill `natalo-50` + `natalo-700` + shelf-line kiri 3px.
  - **Brand** — pill toggle multi-select (check kecil saat on) + input "Cari brand" bila list panjang; tulis `?brands=` (comma-separated).
  - **Ketersediaan** — satu switch "Hanya stok tersedia" (`?inStock=true`).
  - **Tanpa** harga/rating (eksklusif `/search`). Sort ada di bar atas.
  - Data brand: fetch server-side via `prisma.brand.findMany` yang HALAMAN `/brands` sudah pakai; **per-item count di-drop** di `/products` (nol dependensi `/api/search`).
  - Mobile: `ProductFilterChips` + `ProductFilterTopDrawer` existing tetap; rail `hidden md:block`.
- **Bar sort + count** (atas kolom 1fr, desktop): kiri = string existing "Menampilkan X dari Y produk" (angka `font-black`); kanan = **sort segmented ala iOS** (track `slate-100 rounded-full`, 4 label selalu terlihat: Default · Terbaru · Terlaris · Trending; segmen aktif = pill putih `shadow-card` `natalo-700` yang meluncur). Map 1:1 param existing: Default=none, Terbaru=`new=newest`, Terlaris=`popular=best-seller`, Trending=`popular=trending`. **Tanpa opsi Harga.** Mobile: chip "Urut" + BottomSheet existing tetap.
- **Grid + kartu**: `ResponsiveGrid` **cap 4 kolom** desktop (BUKAN 5 — 5-col di 1280 minus rail 248px → kartu ~190px, CTA sesak), `lg:gap-6`. Reuse `ProductCard` default (logika tak diubah). Tambah **lit-shelf glow statis kategori-aware** di bawah produk (terlihat diam); saat hover: lift + `scale-[1.03]` existing, glow lebih terang, shelf-line wipe di bawah nama. **Harga & `ProductCardCta` selalu tampil** (tidak disembunyikan di hover). Badge tetap subtle (maks satu soft-tint chip via `badge` prop, mis. "Original") + `showRating`; jangan ulang brand/search term.
- **Chip filter aktif**: saat ada filter aktif, baris chip di bawah bar sort — **ekstrak** `FilterChip` yang sekarang private di `app/search/page.tsx` jadi komponen shared (ekstraksi jujur, bukan reuse literal). Pill `natalo-50` + `natalo-700` + × per chip; nilai polos ("Whiskas ×", "Aquarium & Ikan ×", "Stok tersedia ×") tanpa prefix "Brand:/Kategori:" (ikut aturan subtle-badge/no-redundant-label). Link "Reset semua filter" (`natalo-600`). Animasi scale-from-0.96 + fade. Desktop-only; mobile pakai inline-clear chips existing.
- **States**: band render instan (nama/blurb/count server-known) → tak flash blank; hanya grid ghosting. `ProductGridSkeleton` restyle 4-up + lit-shelf base + skeleton sidebar (jaga bentuk layout). Konten masuk via `nat-content-fade-in--stagger` ("lampu rak menyala"). Apply filter/sort reuse `useTransition` dim existing (grid `opacity-60 pointer-events-none`) → feedback instan. **Empty** hangat: card `natalo-50` rounded, glyph paw/fin, headline Nunito ("Belum ada produk di rak ini"), langkah jelas ("Reset filter" bila filter penyebab + "Lihat semua produk"), link sekunder "Chat toko". **Error**: panel `red-50` existing dihangatkan.

### 4.2 `/kategori` (`CategoryTabPage`)
`max-w-6xl` → 1280; tambah band Etalase ("Kategori — Jelajahi rak Natalo", subtitle, total count via `SectionHeader`); tiap tile kategori dapat lit-shelf + tint kategori-aware + shelf-line-on-hover. Baris tab mobile tetap.

### 4.3 `/brands` (`BrandDirectoryClient`) — perbaikan struktural terbesar
Sekarang terjebak `max-w-2xl`/`grid-cols-3` mobile. Desktop → 1280 + band Etalase ("Brand Pilihan — merek terpercaya yang kami stok", brand count, "7 tahun kurasi"); grid logo 4–6 kolom lebih lapang; logo `mix-blend-multiply` existing di tile putih lit-shelf; input "Cari brand" pakai field shared. Grid 3-col mobile dipertahankan.

### 4.4 `/search` — mewarisi visual
Sudah punya sidebar 240px. Warisi: sort segmented sama, `FilterChip` shared, chip aktif soft-tint, kartu lit-shelf, band-Etalase-lite ("Hasil untuk '…'"). **Tetap** simpan filter harga + rating yang memang eksklusif `/search`. **Migrasi `max-w-6xl` (1152) → `PageContainer` 1280** di pass yang sama supaya keempat halaman benar-benar sejajar (1152 vs 1280 terlihat sebagai jahitan).

## 5. Komponen (baru vs extend)

- **Baru**: `ProductsFilterSidebar` (md-only); `EtalaseBand` (band header reusable, kategori-aware tint + slug→tagline map); `SegmentedSort` (sort control); `LitShelf` utility/kelas (radial glow + tint kategori); shared `FilterChip` (diekstrak dari `/search`); trust-meta line component.
- **Extend (client-only, tanpa API)**: `useInfiniteProducts` (hari ini pass single `brand`, tanpa `inStock`) → baca/teruskan `brands` (multi) + `inStock` dari URL, rekonsiliasi dgn IntersectionObserver reset-on-param-change existing. `ProductsInfiniteGrid` (hari ini hardcode `grid-cols-2/3/4`, baca `q/kategori/brand/new/popular`) → baca 2 param ekstra + pakai grid 4-up + lit-shelf.
- **Edit terstruktur (PR2)**: `ProductCatalogStickyHeader` sekarang render search bar + chip row di SEMUA breakpoint (hanya baris logo/cart yang `md:hidden`); setelah rail desktop memiliki filtering, PR2 suppress search+chip itu di `md+` (edit nyata ke komponen shared, bukan drop-in prop).

## 6. Verifikasi (wajib sebelum klaim selesai)

1. `npm run lint` bersih; `npx tsc --noEmit` tanpa error baru; `npx next build` compile sukses.
2. `npm test` hijau (+ unit test untuk helper murni baru bila ada, mis. slug→tint mapping).
3. Preview `next dev` (DB Preview) di 375/768/1024/1280/1440/1920: band render, sidebar chip berfungsi (kategori single / brand multi / stok), sort segmented ganti hasil, grid 4-up dengan lit-shelf terlihat diam, chip aktif + reset, empty state; mobile keempat halaman tak berubah; tanpa overflow horizontal.
4. Cek filter benar-benar memfilter (URL `?brands=`, `?inStock=`, `?kategori=`, sort flag) via network/hasil.
5. `git diff --name-only` — tidak ada `app/api/**`, `flutter_app/**`, atau logika transaksi.

## 7. Sequencing (2 PR)

- **PR1 (reuse rendah-risiko)**: swap container 1280 (products/kategori/brands/search), `EtalaseBand`, `SegmentedSort`, chip aktif (ekstrak `FilterChip`), kartu `LitShelf`, lebarkan `/brands` & `/kategori`.
- **PR2 (kerja baru inti)**: `ProductsFilterSidebar` + wiring `useInfiniteProducts`/`ProductsInfiniteGrid` (`brands`/`inStock`) + suppress `ProductCatalogStickyHeader` search/chip di `md+` + `/search` mewarisi visual.

## 8. Risiko & mitigasi (dari panel juri)

- Distinctiveness jangan hanya di `:hover` → lit-shelf **statis** kategori-aware. ✓
- Jangan tumpuk 6–7 band → satu baris meta ringkas. ✓
- Jangan paksa sidebar dari `SearchFilters` (multi-select kategori + Facets counts) → `ProductsFilterSidebar` chip-based, drop counts. ✓
- Jangan satu motif aquarium untuk semua → glow/tint **kategori-aware**; nada "toko tetangga" hangat, bukan luxury-cold (Natalo mass-market top-seller). ✓
- Jangan sembunyikan harga/CTA di hover; jangan 5 kolom; jangan price-sort di `/products`. ✓
- Jangan tinggalkan `/search` di 1152 sementara lain 1280 → migrasi sekalian. ✓
- Klaim trust = janji → hanya yang dikonfirmasi owner (§1); rating jadikan konstanta.

## 9. Di luar cakupan (fase lanjutan)
Product detail (galeri + sticky purchase panel); cart/checkout desktop; SEO; performance; condense-on-scroll band.
