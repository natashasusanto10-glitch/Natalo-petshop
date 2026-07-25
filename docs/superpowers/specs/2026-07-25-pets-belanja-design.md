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

### Keputusan tambahan hasil design review

7. **Angka kartu statistik** menghitung SEMUA yang pernah dipakai, termasuk brand manual — supaya angka selalu sama dengan jumlah baris yang user lihat di grup "Pernah dipakai". (Sebelumnya brand manual dikecualikan, yang bisa menampilkan "Belanja 0" padahal halaman berisi 5 baris.)
8. **Kartu statistik:** `Belanja` dan `Perawatan` bisa ditekan dengan afordans jelas (chevron + ripple + `Semantics(button: true)`); `Momen` diredupkan sebagai "belum aktif". Ini sekalian membenahi `Perawatan` yang sekarang sudah `onTap` tapi memakai `GestureDetector` tanpa ripple maupun semantics.
9. **Kartu di rail profil:** satu gesture per kartu — seluruh kartu tap → detail produk, TANPA tombol di dalamnya. Tombol "Beli lagi" hanya ada di halaman penuh yang ruangnya cukup untuk target ≥44pt.

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
    categoryLabel: string,     // "Obat Cacing" — konteks kenapa produk ini ada
  }>,
  manual: Array<{ brandText, lastUsedAt, categoryLabel }>,
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

1. **"Pernah dipakai untuk {nama}"** — fakta, tampilan paling kaya: baris penuh (bukan grid), thumbnail 56px, nama, harga, baris konteks "Obat Cacing · 3 bulan lalu", tombol "Beli lagi" di kanan. Brand manual jadi baris teks tanpa foto/harga dengan tombol "Cari di Natalo".
2. **"Mungkin cocok untuk {nama}"** — saran, tampilan lebih ringan/sekunder: grid 2 kolom, kartu tanpa baris konteks, header section berbobot lebih rendah daripada grup pertama.

Di bawah grup 2, satu CTA tenang **"Jelajahi produk lain"** → `/products` (Katalog) tanpa filter. Halaman ini scope-nya sengaja sempit (khusus {nama}), tapi tanpa CTA ini jadi jalan buntu kalau semua produk {nama} sudah tercatat via katalog dan tersedia stoknya — tak ada jalan keluar selain tombol back. CTA di-styling sekunder (teks/outline, bukan filled) supaya tidak bersaing dengan aksi utama "Beli lagi"/"Cari di Natalo" di atasnya.

### Aksi

- Beli lagi, produk biasa → `cartStore` + toast sukses.
- Beli lagi, produk varian (`hasVariants`) → `ProductVariantPickerSheet`.
- Stok habis → tombol TIDAK dimatikan; labelnya berubah jadi "Cari serupa" → katalog terfilter kategori produk itu. (Aturan restraint: hindari tombol mati yang tak bisa menjelaskan diri di layar sentuh.)
- "Cari di Natalo" → halaman produk dengan query `brandText`.
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
- Pet baru tanpa riwayat → "Pernah dipakai" jadi empty-state ramah, "Mungkin cocok" tetap terisi. Ini alasan utama dua grup dipisah.
- Produk pernah dipakai lalu dihapus/nonaktif → di-skip dari `used` **di server**, dan `usedCount` ikut turun. Penyaringan wajib di server supaya angka kartu statistik tak pernah beda dengan jumlah baris.
- Produk stok habis → tetap tampil di `used` (fakta riwayat), tombolnya berubah jadi "Cari serupa" (bukan tombol mati); **tidak** pernah masuk `suggested`.
- Pet milik user lain → 403, tidak membocorkan keberadaan pet.

## Di luar scope

Momen/Journey (spec sendiri), riwayat pembelian per-pet (butuh `petId` di `OrderItem` + pemilih pet di checkout), reminder/notifikasi belanja, langganan/auto-repeat order.

## Yang sudah ada (reuse, bukan bangun ulang)

`PetCareRecord.productId` + `brandText` (sudah terisi dari form Catat Perawatan), pola `care-recommendation` untuk query produk + `effectivePrice`/`effectiveStock` di `lib/product-dosage.ts`, `ProductVariantPickerSheet`, `AppProductImage`, `formatRupiah`, `cartStore`, kartu statistik `_StatCard` di `pet_profile_screen.dart`.

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

VERDICT: DESIGN CLEARED — semua temuan dilipat ke spec. Siap ke writing-plans.
