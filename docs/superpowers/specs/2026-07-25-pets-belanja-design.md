# Anabulku — Kolom Belanja di Profil Pet — Design Spec

Tanggal: 2026-07-25. Lanjutan Anabulku Tahap 1–3 (CRUD pet, Profil Anabulku, Perawatan). Kartu statistik `Belanja` di `pet_profile_screen.dart` saat ini hardcoded `0` dan tidak bisa ditekan; empty-state masih berbunyi "Journey dan Belanja untuk {nama} akan muncul di sini."

Fitur "Momen" (Journey) **di luar scope spec ini** — diputuskan dipisah jadi spec sendiri.

## Ringkasan

"Belanja" = **produk yang pernah dipakai untuk pet ini + saran produk yang cocok**, bukan riwayat pembelian.

Alasan keputusan itu: `Order`/`OrderItem` **tidak punya `petId`** (sudah diverifikasi di schema), jadi riwayat pembelian per-pet mustahil tanpa menambah kolom + pemilih pet di checkout + backfill order lama yang tak bisa diatribusikan. Sebaliknya `PetCareRecord.productId` **sudah terisi** lewat form Catat Perawatan, jadi hubungan produk↔pet sudah ada hari ini tanpa plumbing baru.

## Keputusan user (brainstorming)

1. **Arti Belanja:** produk yang pernah dipakai + beli lagi. Bukan riwayat order.
2. **Isi kolom:** dua kelompok terpisah — "Pernah dipakai" (fakta) dan "Mungkin cocok" (saran). Dipisah supaya batas fakta vs saran tidak kabur, dan pet baru tanpa riwayat tetap dapat isi.
3. **Sumber saran:** `targetSpecies` kalau ada, fallback nama kategori. (Terverifikasi: `targetSpecies` cuma terisi di **2 dari 1304** produk aktif, sedangkan nama kategori sudah mengandung spesies — "Makanan Kucing", "Snack Anjing", "Obat Ikan". Jadi fallback inilah yang benar-benar menopang fitur hari ini.)
4. **Brand manual** (`brandText`, dibeli di luar Natalo, tanpa `productId`): tetap tampil, tombolnya "Cari di Natalo".
5. **Lokasi:** rail ringkas di profil pet + kartu statistik `Belanja` jadi bisa ditekan → halaman penuh.
6. **Aksi beli lagi:** produk biasa langsung ke keranjang; produk varian buka `ProductVariantPickerSheet` yang sudah ada.

### Keputusan tambahan hasil design review (skill review)

7. **Angka kartu statistik** menghitung SEMUA yang pernah dipakai, termasuk brand manual — supaya angka selalu sama dengan jumlah baris yang user lihat di grup "Pernah dipakai". (Sebelumnya brand manual dikecualikan, yang bisa menampilkan "Belanja 0" padahal halaman berisi 5 baris.)
8. **Kartu statistik:** `Belanja` dan `Perawatan` bisa ditekan dengan afordans jelas (chevron + ripple + `Semantics(button: true)`); `Momen` diredupkan sebagai "belum aktif". Ini sekalian membenahi `Perawatan` yang sekarang sudah `onTap` tapi memakai `GestureDetector` tanpa ripple maupun semantics.
9. **Kartu di rail profil:** satu gesture per kartu — seluruh kartu tap → detail produk, TANPA tombol di dalamnya. Tombol "Beli lagi" hanya ada di halaman penuh yang ruangnya cukup untuk target ≥44pt.

### Keputusan tambahan hasil design review (senior UX pass)

10. **"Beli lagi" pakai `showAddedToCartSheet` (bottom sheet), BUKAN toast.** Satu-satunya jalur add-to-cart lain di app (`product_detail_screen.dart`) sudah pakai sheet ini, bukan toast — spec sebelumnya menulis "toast" tanpa sadar itu bahasa berbeda. Sheet juga menghindari masalah nyata: kalau user menekan "Beli lagi" untuk 3 produk berturut-turut (skenario restock, kasus paling umum di fitur ini), toast beruntun saling menimpa dan tak jelas mana yang sudah masuk keranjang.
11. **Harga di baris riwayat diberi label "Harga sekarang".** `effectivePrice` yang ditampilkan adalah harga HARI INI, bukan harga saat pet ini memakainya dulu (data itu tak disimpan). Tanpa label, user bisa merasa dibohongi kalau harga sudah naik/turun sejak `lastUsedAt`.
12. **Baris konteks dibedakan framingnya dari section Perawatan tepat di atasnya**, supaya tidak terbaca sebagai section yang sama diulang dua kali. Section Perawatan menjawab "kapan saya rawat" (mis. "Obat Cacing — 3 bulan lalu"); baris konteks Belanja menjawab "kenapa produk ini muncul" dengan framing belanja, bukan riwayat medis: **"Dipakai 2x, terakhir 3 bulan lalu"** — mengganti kategori dengan hitungan pemakaian, sumber data sama tapi kesimpulan yang disampaikan beda dan lebih berguna untuk keputusan beli-ulang.
13. **Empty-total state:** kalau `used`, `manual`, DAN `suggested` sama-sama kosong (pet jenis langka tanpa produk cocok sama sekali), section Belanja disembunyikan penuh — behavior sama dengan endpoint gagal (Error handling), bukan tampil kosong dengan pesan. Konsisten: section ini hanya muncul kalau punya sesuatu untuk ditawarkan.
14. **Nama produk panjang:** maksimal 2 baris lalu ellipsis di SEMUA konteks (rail, baris penuh, grid saran) — data nyata sudah punya nama sepanjang "Drontal Plus Tasty Dog Bentuk TULANG Obat Cacing Anjing per tablet untuk 10KG berat badan". Tombol "Beli lagi" di baris penuh punya lebar TETAP dan tidak ikut menyempit kalau nama panjang — nama yang mengalah (ellipsis), bukan tombol.
15. **Hasil pencarian kosong** dari "Cari di Natalo"/"Cari serupa" (brand manual/produk tak lagi dijual di Natalo dengan nama sama) → halaman Katalog dengan empty-state eksplisit "Tidak ditemukan untuk '{query}' — coba kata kunci lain", bukan grid katalog kosong tanpa penjelasan.

## Arsitektur

Tidak ada sistem baru. Reuse: `PetCareRecord.productId`, pola endpoint `care-recommendation`, `ProductVariantPickerSheet`, `AppProductImage`, `formatRupiah`, `cartStore`.

### Endpoint baru

`GET /api/member/pets/[id]/shopping` (auth member, pet wajib milik user) →

```ts
{
  usedCount: number,           // jumlah produk katalog unik yang pernah dipakai
  used: Array<{                // produk katalog, urut terakhir-dipakai
    productId, name, imageUrl, effectivePrice, inStock,
    hasVariants: boolean,      // menentukan langsung-keranjang vs picker
    lastUsedAt: string,
    usageCount: number,        // "Dipakai 2x" (Keputusan 12) — count record productId ini
  }>,
  manual: Array<{ brandText, lastUsedAt, usageCount }>,
  suggested: Array<{ productId, name, imageUrl, effectivePrice, inStock, hasVariants }>,
}
```

- `used` — `PetCareRecord` pet ini dengan `productId != null`, dedup per produk (ambil `doneAt` terbaru), produk non-aktif/terhapus di-skip.
- `manual` — `brandText` distinct dari record tanpa `productId`.
- `suggested` — kandidat, **mengecualikan** semua `productId` di `used`, hanya stok tersedia, batas 8.

### Aturan pencocokan saran

**Disertakan:** `targetSpecies` memuat `pet.type`; **atau** nama kategori memuat `pet.type`; **atau** kategori netral (tidak memuat nama spesies apa pun).

**Dikecualikan:** kategori yang memuat nama spesies **lain** — pemilik Kucing tidak pernah ditawari "Makanan Anjing" atau "Obat Ikan".

Daftar kata spesies diambil dari nilai `Pet.type` yang dipakai app: Kucing, Anjing, Ikan, Burung, Reptil.

Urutan prioritas: (1) `targetSpecies` cocok, (2) kategori ber-spesies cocok, (3) kategori netral. Dalam tiap tingkat, produk terbaru dulu.

### Angka kartu statistik

`Belanja` = `usedCount` = `used.length + manual.length` — jumlah produk katalog unik **plus** brand manual unik. **Bukan** jumlah order dan bukan jumlah record perawatan.

Aturan pengikatnya: angka ini WAJIB sama dengan jumlah baris yang tampil di grup "Pernah dipakai". Kalau nanti ada baris yang disaring di client (mis. produk nonaktif), penyaringan itu harus terjadi di server supaya angka dan isi tidak pernah berbeda.

## UI

### Token & dimensi (dipatok, jangan dikarang ulang)

App sudah punya dua bahasa kartu produk; JANGAN membuat gaya ketiga.

- Gambar produk: `AppProductImage`, rasio 1:1, `borderRadius` 8 — sama dengan grid Katalog dan picker obat.
- Warna: token semantic (`cs.surface`, `cs.outlineVariant`, `cs.onSurfaceVariant`) + `NataloColors.primary` untuk aksen. **Tidak ada hex hardcode**, dan tiap elemen wajib benar di light & dark.
- Berat font: token `NataloWeight` (`body` w400 / `strong` w600).
- Harga selalu lewat `formatRupiah` — pernah ada bug "Rp45000" di picker obat karena interpolasi mentah.
- Ritme spasi 4/8: kartu rail 140px lebar, gap 8, padding section 20 horizontal (sama dengan section lain di profil).

### Di profil pet

Section baru di bawah "Perawatan": judul "Belanja untuk {nama}" + "Lihat semua", lalu rail horizontal.

- Kartu rail: 140px, thumbnail 1:1 di atas, nama maks 2 baris, harga. **Tanpa tombol** — seluruh kartu satu tap → detail produk (Keputusan 9).
- Isi rail: grup "Pernah dipakai" lebih dulu, disusul "Mungkin cocok" bila kurang dari 4; tiap kartu saran diberi penanda halus supaya tidak tertukar dengan fakta.
- **Loading:** skeleton rail bertinggi TETAP sama dengan kartu asli (shimmer, pola `AppProductImage`), supaya tidak ada pergeseran layout saat data tiba.
- **Gagal / kosong total:** section tidak dirender sama sekali dan tinggi skeleton dilepas dalam satu frame — bukan animasi collapse yang membuat konten di bawahnya melonjak.

### Halaman penuh (`PetShoppingScreen`)

Dua kelompok dengan **hierarki visual berbeda**, bukan cuma judul berbeda — supaya tidak terbaca sebagai satu daftar panjang:

1. **"Pernah dipakai untuk {nama}"** — fakta, tampilan paling kaya: baris penuh (bukan grid), thumbnail 56px, nama (maks 2 baris, ellipsis — Keputusan 14), harga berlabel "Harga sekarang" (Keputusan 11), baris konteks "Dipakai 2x, terakhir 3 bulan lalu" (Keputusan 12, BUKAN nama kategori — beda framing dari section Perawatan di atasnya), tombol "Beli lagi" lebar TETAP di kanan (tidak menyempit walau nama panjang). Brand manual jadi baris teks tanpa foto/harga dengan tombol "Cari di Natalo".
2. **"Mungkin cocok untuk {nama}"** — saran, tampilan lebih ringan/sekunder: grid 2 kolom, kartu tanpa baris konteks, header section berbobot lebih rendah daripada grup pertama.

Di bawah grup 2, satu CTA tenang **"Jelajahi produk lain"** → `/products` (Katalog) tanpa filter. Halaman ini scope-nya sengaja sempit (khusus {nama}), tapi tanpa CTA ini jadi jalan buntu kalau semua produk {nama} sudah tercatat via katalog dan tersedia stoknya — tak ada jalan keluar selain tombol back. CTA di-styling sekunder (teks/outline, bukan filled) supaya tidak bersaing dengan aksi utama "Beli lagi"/"Cari di Natalo" di atasnya.

### Aksi

- Beli lagi, produk biasa → `cartStore` + `showAddedToCartSheet` (Keputusan 10) — SAMA dengan jalur add-to-cart di `product_detail_screen.dart`, bukan toast. Ini juga yang menahan beberapa "Beli lagi" berurutan agar tidak saling menimpa seperti toast beruntun.
- Beli lagi, produk varian (`hasVariants`) → `ProductVariantPickerSheet`, lalu `showAddedToCartSheet` setelah konfirmasi.
- Stok habis → tombol TIDAK dimatikan; labelnya berubah jadi "Cari serupa" → katalog terfilter kategori produk itu. (Aturan restraint: hindari tombol mati yang tak bisa menjelaskan diri di layar sentuh.)
- "Cari di Natalo" / "Cari serupa" → halaman produk dengan query; 0 hasil → empty-state eksplisit "Tidak ditemukan untuk '{query}' — coba kata kunci lain" (Keputusan 15), bukan grid kosong tanpa penjelasan.
- Tap baris/kartu (di luar tombol) → detail produk.

### Interaksi & aksesibilitas (syarat implementasi, bukan saran)

- Setiap elemen yang bisa ditekan memberi ripple/feedback ≤150ms; transisi state 150–300ms.
- Target sentuh ≥44pt; tombol di dalam baris tidak boleh menyempit di bawah itu pada layar 375px.
- Label pembaca layar WAJIB memuat nama produk: "Beli lagi, Drontal Cat" — bukan delapan tombol berlabel "Beli lagi" yang tak bisa dibedakan.
- Header section pakai `Semantics(header: true)`.
- Kartu statistik yang bisa ditekan: `InkWell` + `Semantics(button: true)`; `Momen` yang belum aktif diredupkan dan tidak diberi peran button.
- Hormati `prefers-reduced-motion` untuk shimmer dan smooth-scroll rail.

## Error handling & failure modes

- Endpoint gagal → section di profil disembunyikan, profil tetap utuh (pola existing).
- `used`, `manual`, DAN `suggested` sama-sama kosong (Keputusan 13) → section disembunyikan penuh, sama seperti endpoint gagal. Section ini hanya muncul kalau punya sesuatu untuk ditawarkan.
- Pet baru tanpa riwayat (tapi `suggested` ada isi) → "Pernah dipakai" jadi empty-state ramah, "Mungkin cocok" tetap terisi. Ini alasan utama dua grup dipisah.
- Produk pernah dipakai lalu dihapus/nonaktif → di-skip dari `used` **di server**, dan `usedCount` ikut turun. Penyaringan wajib di server supaya angka kartu statistik tak pernah beda dengan jumlah baris.
- Produk stok habis → tetap tampil di `used` (fakta riwayat), tombolnya berubah jadi "Cari serupa" (bukan tombol mati); **tidak** pernah masuk `suggested`.
- Pet milik user lain → 403, tidak membocorkan keberadaan pet.

## Di luar scope

Momen/Journey (spec sendiri), riwayat pembelian per-pet (butuh `petId` di `OrderItem` + pemilih pet di checkout), reminder/notifikasi belanja, langganan/auto-repeat order.

## Yang sudah ada (reuse, bukan bangun ulang)

`PetCareRecord.productId` + `brandText` (sudah terisi dari form Catat Perawatan), pola `care-recommendation` untuk query produk + `effectivePrice`/`effectiveStock` di `lib/product-dosage.ts`, `ProductVariantPickerSheet`, `AppProductImage`, `formatRupiah`, `cartStore`, `showAddedToCartSheet` (`widgets/added_to_cart_sheet.dart`, dipakai `product_detail_screen.dart`), kartu statistik `_StatCard` di `pet_profile_screen.dart`.

## Testing

Backend (`tsx --test`):
1. Aturan spesies: pet Kucing tidak pernah dapat produk kategori "Makanan Anjing"/"Obat Ikan".
2. Kategori netral ("Grooming Tools", "Obat & Suplemen") lolos untuk semua spesies.
3. `targetSpecies` menang di atas nama kategori (urutan prioritas).
4. Dedup `used` per produk, ambil `doneAt` terbaru.
5. `suggested` tidak pernah memuat produk yang ada di `used`.
6. `usedCount == used.length + manual.length` (brand manual IKUT dihitung).
7. Produk nonaktif di-skip dari `used` DAN dari `usedCount` — angka & isi tak boleh berbeda.
8. Pet milik user lain → 403.

Flutter (widget test):
9. Dua grup tampil dengan label benar dan hierarki berbeda (grup fakta baris penuh, grup saran grid).
10. Brand manual → baris teks + tombol "Cari di Natalo", tanpa harga.
11. Beli lagi produk varian → `ProductVariantPickerSheet` terbuka; produk biasa → `cartStore` terpanggil.
12. Pet baru tanpa riwayat → empty-state "Pernah dipakai", "Mungkin cocok" tetap terisi.
13. Kartu statistik: `Belanja` & `Perawatan` punya `Semantics(button: true)` + bisa ditekan; `Momen` TIDAK berperan button.
14. Produk stok habis di `used` → tombol berlabel "Cari serupa", tetap aktif.
15. Angka kartu statistik sama dengan jumlah baris grup "Pernah dipakai" (regresi kontradiksi angka).
16. Label pembaca layar tombol beli lagi memuat nama produk (bukan delapan "Beli lagi" identik).
17. Rail dalam keadaan loading punya tinggi sama dengan rail terisi (regresi pergeseran layout).
18. CTA "Jelajahi produk lain" tampil di bawah grup 2 dan menavigasi ke `/products` tanpa filter.
19. Beli lagi memanggil `showAddedToCartSheet`, BUKAN toast (regresi: harus pakai jalur yang sama dengan `product_detail_screen.dart`).
20. Harga di baris "Pernah dipakai" tampil dengan label "Harga sekarang".
21. Baris konteks berbunyi "Dipakai Nx, terakhir {waktu}" — BUKAN nama kategori (regresi: harus beda framing dari section Perawatan).
22. `used`+`manual`+`suggested` kosong semua → section Belanja tidak dirender sama sekali.
23. Nama produk >2 baris terpotong ellipsis di rail, baris penuh, dan grid saran; lebar tombol "Beli lagi" tidak berubah oleh panjang nama.
24. Pencarian "Cari di Natalo"/"Cari serupa" 0 hasil → tampil pesan "Tidak ditemukan", bukan grid kosong polos.

## Verifikasi device (setelah rilis)

Rail di profil tidak overflow di layar 375px, thumbnail benar-benar tampil, beli lagi masuk keranjang dengan varian benar, dark mode pada kedua grup, dan angka kartu statistik cocok dengan isi halaman.

## DESIGN REVIEW REPORT

Direview dengan `ui-ux-pro-max` (priority table + `pro-rules.md` pre-delivery checklist) dan `flutter-ui-ux`, terhadap kode nyata di `pet_profile_screen.dart`.

| # | Temuan | Tingkat | Status |
|---|---|---|---|
| 1 | Kartu statistik tanpa afordans; `Perawatan` sudah `onTap` tapi `GestureDetector` tanpa ripple/semantics | Kritikal | Dilipat (Keputusan 8) |
| 2 | Angka "Belanja" bisa kontradiksi dengan isi halaman (manual dikecualikan) | Kritikal | Dilipat (Keputusan 7) |
| 3 | Tidak ada loading state → pergeseran layout profil | Penting | Dilipat (skeleton tinggi tetap) |
| 4 | Bahasa kartu tidak dipatok → risiko gaya kartu ketiga | Penting | Dilipat (§Token & dimensi) |
| 5 | Dua grup tanpa hierarki visual | Penting | Dilipat (baris penuh vs grid 2 kolom) |
| 6 | Gesture bertumpuk di kartu rail | Penting | Dilipat (Keputusan 9, rail tanpa tombol) |
| 7 | Aksesibilitas tak disyaratkan; 8 tombol "Beli lagi" identik | Penting | Dilipat (§Interaksi & aksesibilitas) |
| 8 | Tombol mati untuk stok habis | Minor | Diubah jadi "Cari serupa" |
| 9 | Dark mode & reduced-motion hanya di device-verify | Minor | Dinaikkan jadi syarat implementasi |

Catatan: temuan #1 adalah **bug yang sudah ada di produksi**, bukan hanya risiko spec ini — `Perawatan` bisa ditekan tanpa petunjuk visual, tanpa ripple, dan tanpa peran button bagi pembaca layar.

### Putaran 2 — senior UX pass (manual, di luar checklist skill)

| # | Temuan | Status |
|---|---|---|
| 10 | "Beli lagi" ditulis pakai toast, padahal satu-satunya jalur add-to-cart lain di app (`product_detail_screen.dart`) pakai `showAddedToCartSheet`; toast beruntun juga rawan tumpang tindih kalau user menekan beberapa "Beli lagi" berturut-turut | Dilipat — ganti ke `showAddedToCartSheet` |
| 11 | Harga di baris riwayat adalah harga HARI INI, bukan harga saat dipakai — tanpa label bisa terbaca menyesatkan | Dilipat — label "Harga sekarang" |
| 12 | Baris konteks Belanja mengulang persis apa yang sudah ditampilkan section Perawatan tepat di atasnya (sama-sama "kategori — waktu") | Dilipat — framing beda: "Dipakai Nx, terakhir {waktu}" |
| 13 | Kasus riwayat DAN saran kosong bersamaan tak dispesifikasikan | Dilipat — section disembunyikan, sama seperti gagal fetch |
| 14 | Nama produk panjang (data nyata sampai >90 karakter) belum diuji tata letaknya terhadap tombol beli-lagi | Dilipat — ellipsis 2 baris, lebar tombol tetap |
| 15 | Pencarian "Cari di Natalo"/"Cari serupa" 0 hasil mendarat di grid kosong tanpa penjelasan | Dilipat — empty-state eksplisit |

VERDICT: DESIGN CLEARED (2 putaran). Siap ke writing-plans.
