# Kolom Belanja Pet — Rotasi Saran, Allowlist Spesies, Gaya Kartu Beranda/Katalog

Revisi atas fitur Belanja yang sudah live (spec 2026-07-25-pets-belanja-design.md,
merged main 4c13ec3d), dipicu device-verify user: saran monoton (hampir semua dry
food), badge "Saran" berisiko salah klaim, dan gaya kartu belum konsisten dengan
Beranda/Katalog.

## Latar data produksi (diverifikasi 2026-07-26, read-only)

Produk aktif in-stock per spesies (match targetSpecies ∪ nama kategori):

| Spesies | Total | Rincian |
|---|---|---|
| Kucing | 380 | 369 Makanan Kucing, 8 Snack Kucing, 2 Pasir Kucing, 1 Obat & Suplemen (via targetSpecies) |
| Anjing | 256 | 234 Makanan Anjing, 21 Snack Anjing, 1 Obat & Suplemen (via targetSpecies) |
| Ikan | 47 | 38 Makanan Ikan, 9 Obat Ikan |
| Hamster / Kelinci | 0 via nama — tapi ada 6 Makanan Hewan Kecil + 1 Perlengkapan Hewan Kecil |
| Burung / Reptil | 0 / 3 — **spesies ini dihapus dari daftar** (keputusan user: hanya Kucing, Anjing, Hamster, Kelinci, Ikan) |

Hanya 2 dari 1307 produk punya `targetSpecies` terisi (2 Drontal, kategori
"Obat & Suplemen"). Penyebab monoton yang terverifikasi:

1. Pool netral hanya di-query kalau pool spesies < 8 → untuk Kucing/Anjing tak
   pernah terjadi (bukan masalah lagi — kategori netral dibuang, lihat Keputusan 2).
2. `POOL_TAKE = 40` + `orderBy createdAt desc` → hanya 40 produk terbaru yang
   pernah tampil; 200+ produk lain tak punya kesempatan.
3. Tidak ada kuota/interleave kategori → dry food menelan semua slot.

## Keputusan

### 1. Badge "Saran" dihapus tanpa pengganti

Hapus badge dari `_RailCard` (`pet_shopping_rail.dart`) termasuk suffix label
semantik `', saran produk'`. Pembeda fakta-vs-saran cukup lewat judul grup di
halaman penuh ("Pernah dipakai untuk {nama}" vs "Mungkin cocok untuk {nama}").
Di rail tidak ada pembeda apa pun. Alasan user: klaim per-produk bisa salah;
klaim per-kelompok ("mungkin cocok") jujur.

### 2. Pencocokan spesies: allowlist kategori eksplisit, tanpa netral, tanpa fuzzy

`lib/pet-shopping.ts` ditulis ulang:

- `PET_SPECIES = ["Kucing", "Anjing", "Hamster", "Kelinci", "Ikan"]`
  (Burung & Reptil dibuang).
- Peta eksplisit spesies → nama kategori (exact match, bukan `contains`):

  | Spesies | Kategori |
  |---|---|
  | Kucing | Makanan Kucing, Snack Kucing, Pasir Kucing |
  | Anjing | Makanan Anjing, Snack Anjing |
  | Ikan | Makanan Ikan, Obat Ikan |
  | Hamster | Makanan Hewan Kecil, Perlengkapan Hewan Kecil |
  | Kelinci | Makanan Hewan Kecil, Perlengkapan Hewan Kecil |

- `targetSpecies` (kalau terisi) menang mutlak atas peta kategori — inilah yang
  membuat 2 Drontal ("Obat & Suplemen", di luar allowlist) tetap tampil untuk
  Kucing/Anjing.
- Fallback kategori netral **dihapus total** (keputusan user). Konsekuensi:
  `Makanan Reptil` (3 produk) dan seluruh kategori Aquarium tidak mungkin bocor
  ke spesies mana pun karena tidak ada di allowlist siapa pun — mekanisme
  blacklist `PET_SPECIES` yang lama tidak dibutuhkan lagi.
- Pet dengan `type` di luar 5 spesies (data lama, mis. "Burung"): `suggested`
  kosong; section Belanja di profil tampil hanya kalau ada riwayat pakai
  (perilaku gating `d.isEmpty` yang sudah ada, tidak berubah).

### 3. Saran: interleave kategori + rotasi harian seeded (WIB)

Mengganti mekanisme pool tunggal 40-terbaru:

- **Query per kategori allowlist** (plus query targetSpecies-match), tanpa
  `orderBy createdAt` sebagai pembatas pool — urutan dasar deterministik
  (`createdAt desc, id` untuk tie-break stabil).
- **Filter stok di JS SEBELUM interleave/kuota** — bukan sesudah — supaya slot
  tidak bocor karena item kehabisan stok. Stok TIDAK PERNAH difilter di SQL
  (gotcha varian: `Product.stock = 0` untuk produk varian; pakai
  `effectiveStock`). Over-fetch per kategori (2× kebutuhan) untuk menutup
  item yang tersaring stok.
- **Exclusion produk terpakai** (`notIn: usedIds`) tetap berlaku, diterapkan di
  query per kategori; offset rotasi dihitung terhadap pool SETELAH exclusion +
  filter stok supaya tidak ada slot kosong.
- **Rotasi**: seed deterministik = FNV-1a 32-bit atas string
  `` `${petId}:${tanggalWIB}` `` (tanggal WIB format `YYYY-MM-DD`). Algoritma
  dipatok supaya test dan implementasi tidak bisa bergeser diam-diam.
  Tanggal WIB = UTC+7, dihitung dari konstanta offset di satu tempat, dan
  fungsi menerima `now: Date` sebagai parameter supaya bisa di-test. Tiap
  kategori diambil mulai dari indeks `seed % poolKategori.length` (wrap-around).
  Sifat yang dijamin (dan di-test): dalam satu hari WIB, hasil identik untuk
  request berulang (rail & grid konsisten by construction); hari berbeda →
  offset berbeda. Tidak ada janji panjang siklus di UI/kode.
- **Interleave, bukan blok**: hasil per kategori dijalin berselang secara
  round-robin proporsional (kategori dengan pool lebih besar mendapat giliran
  lebih sering, tapi tidak pernah dua slot berurutan dari kategori yang sama
  selama masih ada kategori lain yang tersisa). Batas total 12.
- Produk hasil `targetSpecies`-match diperlakukan sebagai "kategori" sendiri
  dalam interleave (prioritas giliran pertama — mereka sinyal terkuat).
- Semua logika seleksi (interleave, offset, seed, kuota) = fungsi murni di
  `lib/pet-shopping.ts`, di-unit-test dengan tanggal injeksi; route hanya
  menyediakan data.

Konsekuensi jujur: Hamster/Kelinci punya total 7 produk → grid menampilkan 7,
tidak dipaksa 12, rotasi tidak terasa. Tidak diisi produk kategori lain.

### 4. Jumlah item: grid 12, rail 6, rail = prefix grid

- `SUGGESTED_LIMIT` 8 → **12**.
- Rail profil: batas kartu 4 → **6**, aturan komposisi tetap (used dulu, saran
  mengisi sisa sampai 6). Saran yang tampil di rail = 6 pertama dari urutan
  `suggested` yang sama dengan grid — satu urutan dua panjang, konsistensi
  rail↔grid by construction.

### 5. Gaya kartu: rail = rail Beranda, grid = grid Katalog — TANPA badge

Keputusan user final: tanpa badge apa pun (tidak ada diskon/hemat/voucher/
rating/terjual). DTO ringan yang ada (`slug, name, imageUrl, effectivePrice,
inStock, hasVariants`) sudah cukup; bentuk API TIDAK berubah (selain jumlah
item, Keputusan 4). TIDAK ada ekstraksi `_HomeProductCard`; `home_screen.dart`,
`products_screen.dart`, `product_card.dart`, `compact_commerce_product_card.dart`
TIDAK disentuh (guard widget bersama). Token disamakan secara eksplisit di dua
widget Belanja, dengan komentar yang menunjuk sumber acuan:

- **Rail** (`pet_shopping_rail.dart`) — acuan kartu rail "Terlaris" Beranda
  (`_HomeProductCard` mode `railSlim`+`squareImage` semantik visualnya):
  kartu container putih (`cs.surface`) radius 8 dengan border tipis
  (`cs.outlineVariant`), foto 1:1 full-bleed `BoxFit.cover` (AppProductImage,
  radius atas mengikuti kartu), nama 13px `FontWeight.w600` maks 2 baris
  (tinggi baris di-reserve 31 supaya kartu seragam), harga `formatRupiah`
  14px `FontWeight.w900` `cs.onSurface` — harga final saja. Lebar kartu 150
  (identik rail "Terlaris").
  `kPetShoppingRailHeight` DIHITUNG ULANG mengikuti anatomi baru; skeleton
  digambar ulang dengan anatomi & tinggi identik (anti layout-jump).
- **Grid** (`pet_shopping_screen.dart`, grup "Mungkin cocok") — acuan grid
  produk Katalog: 2 kolom, gap 6, kartu putih radius 8 + border
  `cs.outlineVariant` + shadow `0x08000000` blur 10 offset (0,4), foto 1:1
  full-bleed cover, nama 13px w600 height 1.25 tinggi dipaku 34, harga 16px
  `FontWeight.w900` `cs.onSurface`; di atas kanal latar abu
  `commerceGridSurfaceTint(context)` (helper bersama yang sudah ada di
  `compact_commerce_product_card.dart`) — kanal abu membungkus grup saran di
  halaman penuh. Layout tetap manual Column/Row-Expanded (BUKAN
  `GridView.count` + `childAspectRatio` — regresi overflow text-scale yang
  sudah diperbaiki di 88e5b381 tidak boleh kembali).
- **Section Belanja di profil pet** (`pet_profile_screen.dart`): rail diberi
  strip latar abu yang sama (`commerceGridSurfaceTint`) selebar section,
  supaya kartu putih menonjol — di atas latar putih halaman, kartu putih
  tanpa kanal abu tidak terbaca sebagai kartu.
- Grup "Pernah dipakai" (baris full-width + tombol Beli lagi/Cari serupa)
  TIDAK berubah di revisi ini.
- **Tap kartu** (rail & grid saran): seluruh kartu satu gesture → detail
  produk via `openPetShoppingProduct` (fetch-by-slug), TIDAK berubah.
- **CTA "Jelajahi produk lain"** di bawah grup saran DIPERTAHANKAN, posisinya
  di bawah grid, di luar kanal abu (kanal abu membungkus grid saja).
- Skeleton rail & grid mengikuti anatomi baru.

### 6. Placeholder "Segera hadir" di profil pet

Kartu "Segera hadir — Journey dan Belanja untuk {nama} akan muncul di sini"
sudah usang (Belanja sudah live tepat di atasnya). Diubah menjadi:

> **Segera hadir** — Momen {nama} akan muncul di sini.

("Momen" saja; Journey = nama lama fitur yang sama. Belanja dihapus dari teks.)
Posisi kartu tetap. Nama pet diinterpolasi seperti sekarang.

## Non-goals

- Tidak menyentuh alur Beli lagi / Cari serupa / variant picker.
- Tidak menambah badge atau data baru ke DTO.
- Tidak menyentuh grup "Pernah dipakai".
- Tidak ada migration DB, tidak ada kolom baru (seed dihitung, bukan disimpan).
- Tidak menyentuh search Beranda/Produk (larangan tetap).
- Tidak menangani backfill `targetSpecies`/kategorisasi produk (tugas admin).

## Testing

- `tests/pet-shopping.test.ts` ditulis ulang: allowlist per spesies (termasuk
  Hamster/Kelinci → Hewan Kecil), targetSpecies menang atas allowlist,
  interleave tidak menghasilkan dua slot berurutan satu kategori selama masih
  ada alternatif, determinisme seed (tanggal sama → hasil sama; tanggal beda →
  offset beda), batas WIB (23:59 WIB vs 00:01 WIB hari berikutnya = seed beda;
  16:59 UTC vs 17:01 UTC = ganti hari WIB), filter stok sebelum kuota.
- `tests/pet-shopping-route.test.ts`: limit 12, exclusion usedIds tetap,
  invariant `usedCount` tetap, gotcha stok varian tetap, dan **rail-prefix**:
  komposisi dipanggil dua kali dengan input & tanggal sama → 6 item pertama
  `suggested` identik (menjaga janji rail = prefix grid).
- Flutter: test rail (tanpa badge "Saran"; 6 kartu; anatomi kartu baru — nama
  13/w600, harga 14px w900 onSurface; skeleton tinggi = rail), test grid (kanal abu,
  2 kolom, tanpa badge), test profil (teks placeholder baru "Momen {nama}",
  tidak lagi menyebut Belanja), regresi text-scale 1.3 untuk grid.
