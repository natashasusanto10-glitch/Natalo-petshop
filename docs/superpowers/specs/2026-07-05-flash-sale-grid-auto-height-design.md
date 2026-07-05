# Flash Sale Grid Auto-Height — Design

## Problem

Grid "Diskon Spesial dari Natalo Petshop" di Beranda (`_FlashSaleGrid`,
`flutter_app/lib/screens/home_screen.dart`) terlihat terlalu kosong. Ada dua
sumber kekosongan:

1. **Baris terakhir bolong** — grid 3-kolom, tapi jumlah produk yang lolos
   filter `isFlashSaleEligible` sering bukan kelipatan 3 (mis. 4 produk →
   baris kedua cuma 1 kartu, 2 sel kanan kosong).
2. **Whitespace di dalam tiap kartu** — `GridView` pakai
   `childAspectRatio: 0.52` (fixed, relatif terhadap lebar layar) yang
   memaksa semua sel jadi tinggi & seragam. Konten kartu (gambar 92px +
   judul + harga + baris rating/terjual) lebih pendek dari tinggi sel yang
   dipaksakan, sehingga bagian bawah kartu kosong putih — terutama kartu
   yang tidak punya angka "terjual".

Fokus perbaikan yang disepakati: **whitespace di dalam kartu** (item 2).
Item 1 (baris bolong) tetap terjadi tapi dengan slot transparan, bukan
kotak putih kosong bertepi — jauh kurang mencolok secara visual.

## Root Cause

`childAspectRatio` mengunci rasio lebar:tinggi sel grid tanpa
memperhitungkan tinggi konten sebenarnya. Karena rasio ini relatif
terhadap lebar layar, makin lebar layar makin tinggi sel secara absolut —
sehingga whitespace makin parah di layar besar. Codebase ini sudah punya
pola yang menghindari masalah ini di section lain (`_HomeProductGrid` /
"Rekomendasi Untuk Kamu", `flutter_app/lib/screens/home_screen.dart:3937`):
grid manual berbasis `Row` + `Expanded` per baris, tinggi kartu murni
mengikuti tinggi konten (auto-height), bukan `GridView` dengan aspect
ratio tetap.

## Design

### 1. Ganti `GridView.builder` menjadi row-loop 3 kolom (auto-height)

Di `_FlashSaleGrid` (`flutter_app/lib/screens/home_screen.dart:2511-2533`),
ganti `GridView.builder` dengan pola manual mengikuti section
"Rekomendasi Untuk Kamu", disesuaikan jadi 3 kolom:

- Loop `for (i = 0; i < ceil(visible.length / 3); i++)` menghasilkan satu
  `Row` per baris, berisi 3 slot `Expanded`.
- Tiap slot diisi `_FlashSaleCard` kalau index-nya < `visible.length`,
  kalau tidak diisi `Expanded(child: SizedBox.shrink())` — supaya kartu
  lain di baris itu tetap lebar 1/3 kolom, tidak melebar mengisi slot
  kosong. Pola ini identik dengan penanganan jumlah ganjil di grid
  2-kolom (`flutter_app/lib/screens/home_screen.dart:3966-3975`).
- **Tidak** menggunakan `CrossAxisAlignment.stretch` pada `Row`. Ini sudah
  terdokumentasi sebagai penyebab exception layout yang di-*swallow* oleh
  custom `FlutterError.onError` di app ini, menghasilkan seluruh Beranda
  blank tanpa jejak error apa pun (lihat catatan di
  `flutter_app/lib/screens/home_screen.dart:3943-3950`).
- Spacing antar baris: `SizedBox(height: 10)` (menggantikan
  `mainAxisSpacing: 10` dari `GridView` sebelumnya), spacing antar kolom:
  `SizedBox(width: 10)` (menggantikan `crossAxisSpacing: 10`).

### 2. `_FlashSaleRatingSoldRow` tidak boleh collapse ke tinggi 0

Saat ini (`flutter_app/lib/screens/home_screen.dart:2671-2733`), kalau
produk tidak punya rating (`rating > 0`) dan tidak punya
`soldCount > 0`, widget me-return `const SizedBox.shrink()` — tinggi 0.

Karena grid baru tidak memakai `stretch`, kartu-kartu dalam satu baris
mengandalkan kesamaan tinggi konten masing-masing untuk terlihat rata.
Semua bagian lain kartu sudah punya tinggi tetap (gambar 92px, judul
`SizedBox(height: 27)`, price block 1-2 baris teks) — kecuali baris
rating/terjual ini yang bisa jadi 0 atau ~24px tergantung data. Ini akan
membuat kartu tanpa rating/terjual lebih pendek dari tetangganya di baris
yang sama (ragged row), meski whitespace besar sudah hilang.

**Fix:** ganti `return const SizedBox.shrink();` menjadi
`return const SizedBox(height: 18);` — tinggi yang sama dengan ruang yang
biasa ditempati baris rating/terjual (padding-top 6 + baris teks
setinggi ~12px). Ini membuat semua kartu flash sale punya tinggi
konsisten tanpa perlu `stretch`.

### Cakupan yang TIDAK berubah

- Logic filter `isFlashSaleEligible` dan `.take(8)` — jumlah & seleksi
  produk yang tampil tidak berubah.
- `_FlashSaleCard`, `_FlashSalePriceBlock`, header, dan countdown timer —
  tidak ada perubahan struktur, hanya cara grid menyusun kartu-kartu ini.

## Edge Cases

- **4 produk** (kondisi di screenshot asli): baris 1 = 3 kartu penuh,
  baris 2 = 1 kartu + 2 slot transparan kosong.
- **1-2 produk, atau kelipatan 3** (3, 6): tidak ada slot kosong sama
  sekali.
- **Produk tanpa rating & tanpa terjual bercampur dengan yang punya**,
  dalam satu baris: tinggi kartu tetap seragam berkat fix `SizedBox(height: 18)`.

## Verification Plan

Perubahan ini murni visual di Flutter (bukan web Next.js), diverifikasi
lewat `flutter run` di emulator:

1. Kondisi asli (4 produk flash sale, seperti screenshot) — pastikan
   tidak ada whitespace besar di bawah kartu, dan slot kosong di baris
   terakhir tidak tampak sebagai kotak putih bertepi.
2. Campuran produk dengan/tanpa "terjual" dalam satu baris — pastikan
   tinggi baris tetap rata (tidak ragged).
3. Reload Beranda dan pastikan tidak ada regresi "blank screen" (indikasi
   exception layout yang di-swallow oleh custom error handler) — risiko
   ini eksplisit karena hindari `stretch`.
