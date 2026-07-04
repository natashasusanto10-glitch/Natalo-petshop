# Brand Favorit — Optical Sizing & Normalisasi Logo

**Tanggal:** 2026-07-04
**Status:** Design (menunggu review)

## Masalah

Section "Brand Favorit" di Home (grid 2×3) terasa "kurang pas": ukuran logo
loncat-loncat antar kartu. Logo banner lebar (Happy Dog, Happy Cat, Royal
Canin, Sakkai Pro) tampil dominan mepet tepi kartu, sedangkan logo kotak/tinggi
dengan whitespace tebal (Nexgard, Whiskas, Hill's, CIAO/INABA) tampil kecil dan
tenggelam di tengah.

### Akar masalah

1. **`BoxFit.contain` mengepaskan bounding box, bukan berat visual.** Di
   `_BrandLogoImage` ([home_screen.dart:3666](../../../flutter_app/lib/screens/home_screen.dart))
   semua logo dirender `contain` di dalam `Expanded(flex: 5)`, jadi tiap logo
   mengisi seluruh area sesuai aspect ratio intrinsiknya — yang berbeda-beda
   drastis antar brand.
2. **Padding kartu tipis & seragam** (`EdgeInsets.all(4)` logo + `all(6)` kartu)
   tidak mengompensasi logo yang melar.
3. **Aspect ratio kartu 1.45** (pipih lebar) menguntungkan logo banner,
   merugikan logo kotak.
4. **File logo dari admin tidak dinormalisasi** — padding transparan bawaan PNG
   bervariasi, jadi masalah datang dari sisi aset juga, bukan cuma layout.

## Solusi: 3 lapis

### Lapis A — Perbaikan render Flutter

Menyembuhkan semua logo yang sudah terlanjur ke-upload, murni presentasi.

Di `_BrandGridCard` / `_BrandLogoImage`
([home_screen.dart:3607](../../../flutter_app/lib/screens/home_screen.dart)):

- **Patok tinggi logo.** Ganti `Expanded(flex: 5)` + `contain` (yang mengisi
  seluruh kotak) dengan logo yang di-`ConstrainedBox(maxHeight: ~26)` dan
  di-center. Ini menghentikan logo banner melar mepet tepi dan menaikkan logo
  kecil ke garis tinggi yang sama.
- **Longgarkan padding kartu** dari `all(4)`/`6` → ~`12` horizontal, supaya ada
  bingkai kosong konsisten mengelilingi tiap logo.
- **Naikkan aspect ratio kartu** sedikit: `childAspectRatio` 1.45 → ~1.35
  (kartu sedikit lebih tinggi, logo kotak dapat ruang). `gridHeight` mengikuti
  perhitungan yang sama di
  [home_screen.dart:3536](../../../flutter_app/lib/screens/home_screen.dart).
- Berlaku sama untuk cabang network (`CachedNetworkImage`), asset
  (`Image.asset`), dan fallback inisial (`_BrandInitial`).

Nilai `maxHeight`, padding, dan aspect ratio final akan di-tune saat implementasi
lewat preview visual — angka di atas adalah titik awal.

### Lapis B — Normalisasi aset saat upload

Menuntaskan sisa "logo tenggelam" akibat padding transparan bawaan file.

- Modul baru `lib/upload/normalize-logo.ts` — fungsi yang menerima buffer
  gambar, memakai `sharp` (sudah ada di dependency) untuk:
  1. **Trim** border transparan (`.trim()`).
  2. **Pasang ulang di kanvas seragam** dengan padding persentase tetap — logo
     mengisi ~80% kanvas, sisanya transparan (`.extend()` / composite ke kanvas
     square transparan).
  3. Output PNG (atau WEBP) transparan.
- **Opt-in per-jenis.** Endpoint `/api/admin/upload`
  ([route.ts](../../../app/api/admin/upload/route.ts)) juga dipakai foto produk,
  yang **tidak boleh** di-trim. `BrandLogoUploadButton`
  ([BrandLogoUploadButton.tsx](../../../components/admin/BrandLogoUploadButton.tsx))
  mengirim penanda (mis. field FormData `kind: "brand-logo"`). Hanya upload
  dengan `kind === "brand-logo"` yang lewat `normalize-logo`. Jalur foto produk
  tidak berubah.

### Lapis C — Skrip one-off backfill

Merapikan semua logo lama yang sudah ada di DB tanpa reupload manual.

- Skrip di `scripts/` (mis. `scripts/normalize-brand-logos.mjs`).
- Alur: ambil semua brand ber-`logoUrl` dari DB (Prisma) → unduh tiap logo →
  lewatkan `normalize-logo` (modul yang sama dengan Lapis B) → re-upload ke
  UploadThing → update `logoUrl` di DB.
- **Idempoten & aman diulang:** log per-brand (sukses/skip/error), lanjut walau
  satu brand gagal, tidak menghapus logo lama sebelum upload baru sukses.

## Prinsip isolasi

Pipeline normalisasi `sharp` hidup di **satu** modul `lib/upload/normalize-logo.ts`,
dikonsumsi bersama oleh Lapis B (route) dan Lapis C (skrip). Tidak ada logika
duplikat; mengubah aturan padding/trim cukup di satu tempat.

## Urutan & sifat

- Lapis A berdiri sendiri (Flutter) dan sudah mengangkat mayoritas masalah untuk
  logo yang ada.
- Lapis B & C berbagi modul dan sebaiknya diimplementasi berurutan (B dulu,
  lalu C memakai modulnya).
- Tidak ada perubahan skema DB — `logoUrl` tetap satu kolom string.

## Non-goals

- Tidak mengubah alur/UX upload foto produk.
- Tidak menambah kolom/tabel baru.
- Tidak mengubah logika carousel/auto-slide Brand Favorit.
- Tidak menyentuh section lain di Home.
