# Beranda — Redesign Desktop + Mobile Web (Kohesif)

**Tanggal:** 2026-07-07
**Status:** Disetujui (arah desain), menunggu review spec
**Cakupan:** Homepage (`app/page.tsx`) + Header (komponen bersama) + shortcut + rail→grid. Desktop dan mobile web. **Flutter tidak disentuh.**

---

## 0. Konteks & tujuan

Website `www.natalopetshop.com` adalah Next.js (App Router + React + Tailwind v4). G1 (fase 1) sudah menambah fondasi design-system (`PageContainer`, `ResponsiveGrid`, `SectionHeader`, token, header 3-tingkat) + memperbaiki hero yang kegedean. Tapi homepage masih "terasa mobile" di desktop karena **pola layout-nya masih mobile**: header menumpuk 4 baris dengan search ngambang, shortcut ikon kecil, dan beberapa section masih swipe-rail horizontal.

Tujuan: jadikan beranda **terasa desktop-native** (dan tetap rapi di mobile web) dengan merombak **pola layout**, bukan identitas visual. Identitas tetap: biru Natalo `#1E5FBF`, font Nunito, token G1.

## 1. Prinsip

- Identitas warna/logo/font dipertahankan. Yang dirombak: layout, kepadatan, hierarki.
- Mobile web boleh dipoles (spacing/tipografi) tapi pola inti mobile (swipe rail, ikon shortcut) dipertahankan — hanya desktop yang berubah pola.
- Tidak menyentuh: logika cart/checkout/voucher/loyalty/auth, endpoint API, schema DB, data. Tidak hardcode produk/kategori/harga/promo/kontak.
- Tidak menyentuh `flutter_app/**` dan `app/api/**`.
- Reuse komponen/primitive existing (`PageContainer`, `ResponsiveGrid`, `SectionHeader`, `ProductCard`). Hindari duplikasi.
- Perubahan bertahap & reversible; sentuh cabang `md:` untuk desktop, jaga mobile.

## 2. Keputusan yang sudah disepakati

| Topik | Keputusan |
|---|---|
| Announcement bar | **Dihapus total** (berantakan di paling atas; pesan gratis-ongkir/original/WA tetap ada di trust section + footer) |
| Header desktop | **1 baris utama**: Logo · search bar lebar inline (flex-1) · aksi (Wishlist, Notifikasi, Cart, Masuk/avatar). Baris nav di bawah. Lebar 1280 (`--nat-container`). |
| Header mobile | Tidak berubah pola; poles spacing tipis. |
| Shortcut desktop | **6 tile besar** (icon + label, mengisi lebar konten, hover). |
| Shortcut mobile | Tetap ikon bulat; dirapatkan sedikit. |
| Produk Terlaris | Desktop **grid** kartu produk standar + **badge angka peringkat** (1,2,3…). Mobile tetap swipe rail. |
| Kategori Populer | Desktop **grid**. Mobile tetap swipe rail. |
| Brand Favorit | Desktop **grid ~12 (2 baris)** + "Lihat semua brand" (→ `/brands`). Mobile tetap rail auto-slide. |
| Mekanisme rail→grid | **Opsi A** — container responsif satu markup: mobile `flex overflow-x-auto`, desktop `md:grid`. Tanpa JS baru, tanpa duplikasi DOM. |
| Hero | Sudah dibatasi 1024px (PR #30, live). Tidak diubah lagi. |

## 3. Desain per bagian

### Bagian A — Header (komponen bersama `components/Header.tsx`)

Hanya cabang **desktop (`md+`)** yang dirombak; cabang mobile + semua conditional per-route (early `return null`, auth-page branch) tidak diubah.

- **Hapus** render `AnnouncementBar` dari header (Bagian ini juga menghapus pemakaian komponennya di header; komponen `components/header/AnnouncementBar.tsx` boleh dibiarkan tidak terpakai atau dihapus — pilih hapus jika tak ada konsumen lain).
- **Baris utama desktop** jadi satu baris flex: `Logo` (shrink-0) · `HomeSearchBar` (desktop, `flex-1`, lebar, tidak lagi `max-w-xl` di baris terpisah) · aksi kanan (`Wishlist ❤`, `NotificationBell`, `CartCount`, tombol `Masuk`/avatar).
  - Pindahkan instance search desktop dari baris terpisah (`mx-auto hidden w-full max-w-xl … md:flex md:pb-2`) menjadi inline di baris utama.
  - Tambah link Wishlist (ikon `❤` → `/wishlist`) di aksi kanan desktop.
- **Baris nav desktop** final = Kategori ▾ · Brand · Promo · Terlaris · Produk Baru · Feed. **Drop** "Beranda" (redundan dgn logo) dan "Tentang Kami" (sudah di footer) dari nav teks desktop. "Produk" boleh masuk sebagai bagian dropdown Kategori atau link tersendiri — pilih satu, jangan duplikat dengan Kategori.
- Selaraskan lebar inner header ke `max-w-[var(--nat-container)]` (1280) — sekarang `max-w-6xl` (1152).
- Mobile header: struktur tetap; boleh poles spacing/tipografi kecil.

### Bagian B — Shortcut desktop jadi tile (`app/page.tsx` section shortcut)

- Mobile (`< md`): tetap `grid-cols-3` ikon bulat 56px seperti sekarang (dirapatkan sedikit bila perlu).
- Desktop (`md+`): grid tile besar `md:grid-cols-3 lg:grid-cols-6` (atau serupa) — tiap tile: icon lebih besar + label, background lembut, border tipis, hover elevasi. Mengisi lebar 1280 penuh, tidak ngambang.
- Data `SHORTCUT_ITEMS` tetap; hanya presentasi berubah.

### Bagian C — Rail → Grid (3 section di `app/page.tsx` + `BrandChoiceSection`)

Terapkan mekanisme Opsi A pada tiap container rail:
- Mobile: tetap `flex snap-x snap-mandatory gap-2.5 overflow-x-auto …` (tidak berubah).
- Desktop: tambah `md:grid md:grid-cols-N md:gap-4 md:overflow-visible md:snap-none`, dan pada kartu anak override lebar mobile dengan `md:w-auto md:min-w-0 md:max-w-none md:basis-auto`.

**C1 — Produk Terlaris** (`app/page.tsx` ~880-948, 6 produk):
- Ganti kartu bespoke ranked jadi `ProductCard` standar (konsisten dgn Rekomendasi/Flash Sale).
- Tambah dukungan badge angka peringkat di `ProductCard` via prop baru opsional `rankBadge?: number` (render angka kecil di pojok gambar). Default tidak tampil. Reusable untuk masa depan.
- Desktop grid: `md:grid-cols-3 lg:grid-cols-6` (6 produk → 1 baris di lg+, atau 3+3 di md).

**C2 — Kategori Populer** (`app/page.tsx` ~953-989, 6 kategori):
- Container responsif; desktop `md:grid-cols-3 lg:grid-cols-6` (6 kategori → 1 baris di lg+). Kartu kategori existing dipakai, tambah class desktop.

**C3 — Brand Favorit** (`components/home/BrandChoiceSection.tsx`, jumlah variabel):
- Mobile: tetap rail auto-slide semua brand (tidak berubah).
- Desktop: `md:grid md:grid-cols-4 lg:grid-cols-6 md:overflow-visible`. Batasi **12 tampil** di desktop via CSS (`md:[&>*:nth-child(n+13)]:hidden`) — mobile tetap render semua (rail), desktop tampil 12 (2 baris di 6-kolom).
- Header section sudah punya "Lihat semua" → `/brands` (dipertahankan).

### Bagian D — Konsistensi & mobile polish

- Pastikan semua section homepage dibungkus `PageContainer` (mayoritas sudah dari G1) dan judul pakai `SectionHeader` bila punya CTA.
- Mobile web: poles spacing vertikal antar section + ukuran tipografi judul agar konsisten (via token, tanpa mengubah pola).

## 4. Verifikasi (wajib sebelum klaim selesai)

1. `npm run lint` bersih (relatif baseline pre-existing).
2. `npx tsc --noEmit` tidak ada error baru.
3. `npm run build` compile sukses.
4. Preview `next dev` (DB Preview, bukan production) — cek di **375 / 768 / 1024 / 1280 / 1440 / 1920 px**: header 1-baris di desktop, tidak ada announcement bar, shortcut tile mengisi lebar, 3 rail jadi grid di desktop & tetap swipe di mobile, tidak ada overflow horizontal, mobile tetap rapi.
5. Konfirmasi tidak ada file `app/api/**`, `flutter_app/**`, atau logika transaksi tersentuh (`git diff --name-only`).

## 5. Risiko & kompatibilitas

- `Header.tsx` dipakai lintas halaman + banyak conditional per-route. Mitigasi: hanya sentuh cabang desktop `md:`, jangan ubah logika hide/show existing atau auth-branch.
- Menghapus announcement bar menghapus CTA WA dari header desktop — tetap tersedia di footer + trust section (tidak ada info hilang).
- Perubahan `BrandChoiceSection` menyentuh komponen dengan JS auto-slide — pastikan auto-slide mobile tetap jalan; desktop grid tak nge-scroll (aman).
- Menambah prop `rankBadge` ke `ProductCard` bersifat aditif — konsumen lain tidak terpengaruh.

## 6. Di luar cakupan (fase lanjutan)

Halaman listing/kategori/search/detail/cart/checkout desktop mendalam; SEO lanjutan; performance; analytics. Masing-masing spec terpisah.
