# Flash Sale Grid Auto-Height Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hilangkan whitespace kosong di dalam kartu grid Flash Sale di Beranda dengan mengganti `GridView` fixed-aspect-ratio dengan layout row-loop auto-height.

**Architecture:** `_FlashSaleGrid` di `flutter_app/lib/screens/home_screen.dart` saat ini pakai `GridView.builder` dengan `childAspectRatio: 0.52` tetap, memaksa semua sel jadi tinggi seragam relatif terhadap lebar layar — konten kartu lebih pendek dari tinggi paksaan itu, jadi ada whitespace di bawah. Fix: ganti dengan pola manual `Row` + `Expanded` per baris (3 kolom) yang sudah dipakai section "Rekomendasi Untuk Kamu" di file yang sama — tinggi kartu murni mengikuti tinggi konten. Slot kosong di baris terakhir (kalau jumlah produk bukan kelipatan 3) diisi `SizedBox.shrink()` supaya kartu lain tetap lebar 1/3 kolom. Karena tidak pakai `CrossAxisAlignment.stretch` (berisiko bikin Beranda blank tanpa error — bug yang sudah pernah terjadi di codebase ini), `_FlashSaleRatingSoldRow` perlu diubah supaya tidak collapse ke tinggi 0 saat produk tidak punya rating/terjual, supaya kartu-kartu dalam satu baris tetap rata tingginya secara alami.

**Tech Stack:** Flutter/Dart, widget layout manual (`Row`/`Expanded`/`Column`), tidak ada dependency baru.

## Global Constraints

- Tidak mengubah logic filter `isFlashSaleEligible` atau `.take(_maxVisible)` — jumlah & seleksi produk yang tampil tetap sama.
- Tidak menggunakan `CrossAxisAlignment.stretch` pada `Row` manapun di grid ini (menyebabkan silent layout exception yang membuat seluruh Beranda blank — lihat catatan di `flutter_app/lib/screens/home_screen.dart:3943-3950`).
- Tidak mengubah struktur internal `_FlashSaleCard` / `_FlashSalePriceBlock` / header / countdown timer — hanya cara grid menyusun kartu-kartu ini dan tinggi minimum baris rating/terjual.
- Spec penuh ada di `docs/superpowers/specs/2026-07-05-flash-sale-grid-auto-height-design.md`.

---

## Task 1: Ganti `GridView.builder` dengan row-loop auto-height di `_FlashSaleGrid`

**Files:**
- Modify: `flutter_app/lib/screens/home_screen.dart:2510-2533`

**Interfaces:**
- Consumes: `visible` (`List<Product>`, sudah ada di scope method `build`, hasil `products.take(_maxVisible).toList()` di baris 2443), `onTap` (`ValueChanged<Product>`, field class), `_FlashSaleCard` (widget sudah ada, constructor `_FlashSaleCard({required Product product, required VoidCallback onTap})`).
- Produces: tidak ada widget/fungsi baru yang dikonsumsi task lain — perubahan murni di dalam method `build` milik `_FlashSaleGrid`.

- [ ] **Step 1: Baca ulang blok kode yang akan diganti untuk memastikan baris tidak bergeser**

Run: `sed -n '2508,2535p' flutter_app/lib/screens/home_screen.dart`

Expected output (harus persis sama sebelum diedit):

```dart
          const SizedBox(height: 12),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: visible.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // 0.62 → 0.56 → 0.52: cell makin tinggi untuk muat text section
              // (title + harga + strikethrough) di card diskon. Grid 3-kolom
              // wajib tinggi seragam (bukan auto-height), jadi turunkan aspect
              // ratio. Di 0.56 masih overflow ~5.7px saat ada strikethrough;
              // 0.52 kasih ruang cukup.
              childAspectRatio: 0.52,
            ),
            itemBuilder: (context, index) {
              final product = visible[index];
              return _FlashSaleCard(
                product: product,
                onTap: () => onTap(product),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

Kalau baris tidak persis sama, cari ulang blok ini dengan `grep -n "GridView.builder" flutter_app/lib/screens/home_screen.dart` sebelum lanjut ke Step 2.

- [ ] **Step 2: Ganti blok `GridView.builder` dengan row-loop 3 kolom auto-height**

Gunakan tool edit untuk mengganti persis blok di atas (dari `const SizedBox(height: 12),` sampai `),` penutup `GridView.builder`, TIDAK termasuk `],` dan sisanya) dengan:

```dart
          const SizedBox(height: 12),
          // Row-loop manual (BUKAN GridView dengan childAspectRatio tetap).
          // Alasan sama dengan grid "Rekomendasi Untuk Kamu" di bawah:
          // childAspectRatio tetap memaksa tinggi sel seragam relatif lebar
          // layar, menyisakan whitespace besar di bawah konten kartu yang
          // lebih pendek. Auto-height: tinggi kartu murni ikut konten.
          for (var i = 0; i < (visible.length + 2) ~/ 3; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == ((visible.length + 2) ~/ 3) - 1 ? 0 : 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col > 0) const SizedBox(width: 10),
                    Expanded(
                      child: i * 3 + col < visible.length
                          ? _FlashSaleCard(
                              product: visible[i * 3 + col],
                              onTap: () => onTap(visible[i * 3 + col]),
                            )
                          // Slot kosong di baris terakhir kalau jumlah
                          // produk bukan kelipatan 3 — Expanded kosong
                          // supaya kartu lain tetap lebar 1/3 kolom,
                          // bukan melebar mengisi slot ini.
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

**Catatan penting:** JANGAN tambahkan `crossAxisAlignment: CrossAxisAlignment.stretch` pada `Row` di atas. Ini pernah menyebabkan seluruh Beranda blank tanpa jejak error apa pun karena custom `FlutterError.onError` di app ini tidak memanggil `FlutterError.presentError` (lihat komentar di `flutter_app/lib/screens/home_screen.dart:3943-3950`).

- [ ] **Step 3: Jalankan static analysis**

Run: `cd flutter_app && flutter analyze lib/screens/home_screen.dart`
Expected: `No issues found!` (atau hanya warning pre-existing yang tidak terkait perubahan ini — bandingkan dengan output `flutter analyze` sebelum edit kalau ragu).

- [ ] **Step 4: Commit**

```bash
cd flutter_app
git add lib/screens/home_screen.dart
git commit -m "$(cat <<'EOF'
fix(home): grid flash sale auto-height — hilangkan whitespace di kartu

GridView childAspectRatio: 0.52 memaksa semua sel tinggi seragam
relatif lebar layar, menyisakan whitespace besar di bawah konten
kartu yang lebih pendek. Ganti dengan row-loop manual (pola sama
seperti grid Rekomendasi) — tinggi kartu murni ikut konten.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Cegah `_FlashSaleRatingSoldRow` collapse ke tinggi 0

**Files:**
- Modify: `flutter_app/lib/screens/home_screen.dart:2671-2733`

**Interfaces:**
- Consumes: `product.rating` (`double`), `product.soldCount` (`int`) — field yang sudah ada di model `Product`.
- Produces: tidak ada — perubahan murni internal ke widget `_FlashSaleRatingSoldRow` yang sudah dipakai `_FlashSaleCard` (baris 2608, tidak berubah).

**Kenapa task ini perlu:** Task 1 melepas grid dari `GridView` fixed-height ke row-loop auto-height TANPA `CrossAxisAlignment.stretch` (lihat alasan di Task 1). Supaya 3 kartu dalam satu baris tetap terlihat rata tanpa `stretch`, setiap bagian kartu (gambar, judul, harga, rating/terjual) harus konsisten tingginya antar produk. Saat ini `_FlashSaleRatingSoldRow` return `SizedBox.shrink()` (tinggi 0) kalau produk tidak punya rating dan tidak punya `soldCount` — ini membuat kartu tanpa rating/terjual lebih pendek dari tetangganya di baris yang sama.

- [ ] **Step 1: Baca ulang blok kode yang akan diganti**

Run: `sed -n '2676,2681p' flutter_app/lib/screens/home_screen.dart`

Expected output (harus persis sama sebelum diedit):

```dart
  @override
  Widget build(BuildContext context) {
    final hasRating = product.rating > 0;
    final hasSold = product.soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();

```

- [ ] **Step 2: Ganti `SizedBox.shrink()` dengan `SizedBox(height: 18)`**

Ganti baris:

```dart
    if (!hasRating && !hasSold) return const SizedBox.shrink();
```

menjadi:

```dart
    // Tinggi tetap (bukan shrink ke 0) supaya kartu tanpa rating/terjual
    // tetap sama tinggi dengan tetangganya di baris yang sama — grid
    // flash sale row-loop tidak pakai CrossAxisAlignment.stretch, jadi
    // kerataan baris bergantung pada tiap bagian kartu punya tinggi
    // konsisten. 18 = padding-top 6 + tinggi baris teks/ikon ~12.
    if (!hasRating && !hasSold) return const SizedBox(height: 18);
```

- [ ] **Step 3: Jalankan static analysis**

Run: `cd flutter_app && flutter analyze lib/screens/home_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd flutter_app
git add lib/screens/home_screen.dart
git commit -m "$(cat <<'EOF'
fix(home): jangan collapse baris rating/terjual ke tinggi 0 di kartu flash sale

Grid flash sale sekarang auto-height tanpa CrossAxisAlignment.stretch
(lihat commit sebelumnya), jadi kerataan baris bergantung tiap bagian
kartu konsisten tingginya. Produk tanpa rating & tanpa terjual dulu
bikin baris ini tinggi 0, sekarang reserve 18px biar kartu dalam satu
baris tetap rata.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Verifikasi visual di emulator (RAM tertinggi)

**Files:** Tidak ada file yang diubah — task ini murni verifikasi manual.

**Interfaces:** N/A (tidak ada kode baru).

- [ ] **Step 1: Konfirmasi emulator dengan RAM tertinggi**

Run: `grep -i "hw.ramSize\|avd.ini.displayname" ~/.android/avd/*.avd/config.ini`
Expected: `Pixel_7_2.avd/config.ini` menunjukkan `hw.ramSize=24576` (24GB) — lebih tinggi dari `Natalo_Fast_API35.avd` (`6G`). Gunakan `Pixel_7_2`.

- [ ] **Step 2: Jalankan emulator Pixel_7_2**

Run: `flutter emulators --launch Pixel_7_2`
Expected: emulator boot, tidak ada error di terminal.

- [ ] **Step 3: Jalankan app di emulator**

Run (dari `flutter_app/`): `flutter run -d Pixel_7_2`
Expected: app build & install sukses, Beranda tampil tanpa exception di console.

- [ ] **Step 4: Navigasi ke Beranda dan cek grid Flash Sale**

Di app yang berjalan, pastikan section "⚡ Flash Sale — Diskon Spesial dari Natalo Petshop" terlihat:
- Tidak ada whitespace kosong besar di bagian bawah kartu manapun.
- Kalau jumlah produk bukan kelipatan 3, baris terakhir menyisakan slot transparan (bukan kotak putih bertepi).
- Kartu tanpa angka "terjual" tetap sejajar tingginya dengan kartu lain di baris yang sama.

- [ ] **Step 5: Cek tidak ada regresi silent-blank-screen**

Reload Beranda (hot restart: tekan `R` di terminal `flutter run`, atau pull-to-refresh kalau ada). Pastikan seluruh Beranda tetap render normal (bukan blank), yang berarti tidak ada layout exception yang di-swallow oleh custom error handler.

- [ ] **Step 6: Tidak ada commit untuk task ini** — task ini murni verifikasi manual, tidak menghasilkan perubahan kode.

---

## Self-Review Notes

- **Spec coverage:** Item 1 (row-loop 3 kolom, slot kosong, larangan `stretch`) → Task 1. Item 2 (`_FlashSaleRatingSoldRow` fix tinggi 18px) → Task 2. Verification plan spec → Task 3 (ditambah dengan instruksi user untuk pakai emulator RAM tertinggi).
- **Placeholder scan:** tidak ada TBD/TODO; semua step berisi command atau kode lengkap.
- **Type consistency:** `_FlashSaleCard({required Product product, required VoidCallback onTap})` dipakai identik di Task 1 dengan constructor yang sudah ada di baris 2544 (tidak diubah). `visible` tetap `List<Product>` dari `build()` method yang sama, tidak ada penamaan baru yang bentrok.
