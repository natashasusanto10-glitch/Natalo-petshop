# Perawatan Anabulku — Form Dinamis per Kategori + Rekomendasi Obat — Design

Tanggal: 2026-07-24. Status: disetujui user (diskusi selesai, menunggu spec review sebelum writing-plans).

Susulan dari [2026-07-24-anabulku-tahap3-perawatan-design.md](2026-07-24-anabulku-tahap3-perawatan-design.md) (Tahap 3, sudah ada di kode: `PetCareFormScreen`, `PetCareRecord`, `pet-care-api`). Spec ini **tidak mengganti** Tahap 3, melainkan menambah field per kategori pada form yang sudah ada + fitur rekomendasi produk obat dari katalog Natalo.

## Ringkasan

Form "Catat Perawatan" saat ini seragam untuk semua 6 kategori (chip kategori, tanggal, foto besar, catatan, jadwal berikutnya). User ingin form **berubah bentuk sesuai kategori yang dipilih**, dengan dua kategori (Obat Cacing, Obat Kutu) disambungkan ke katalog produk Natalo supaya dosis pakai akurat (bukan tebakan), plus sistem merekomendasikan produk yang cocok secara otomatis berdasarkan berat badan pet.

Keputusan kunci hasil diskusi:
- Foto besar khusus "hasil grooming" **dihapus**. Semua kategori memakai satu foto opsional kecil (thumbnail) yang seragam.
- Berat badan pet adalah **field baru** (`Pet.weightKg` + riwayat), diisi lewat form Obat Cacing/Obat Kutu, bukan lewat Edit Profil.
- Brand/produk obat **dipilih dari katalog Natalo** (filter kategori+spesies+berat), dengan jalur ketik-manual untuk pembelian di luar Natalo.
- Data dosis per produk **diisi & disetujui admin saja** (perluasan AI generate-deskripsi yang sudah ada di admin web). App Flutter murni membaca data itu — **tidak ada pemanggilan AI dari app**.
- Sistem **otomatis merekomendasikan** 1 produk teratas yang cocok (kategori+spesies+berat) begitu berat terisi, untuk Obat Cacing maupun Obat Kutu (mekanisme sama, difilter kategori berbeda).

## Form — kolom tambahan per kategori

Field dasar (chip kategori, tanggal dilakukan, catatan, jadwal berikutnya) tidak berubah. Foto opsional kini seragam kecil (thumbnail ~56px) untuk semua kategori — blok foto besar lama dihapus.

| Kategori | Kolom tambahan | Catatan |
|---|---|---|
| Grooming | "Tempat grooming" (teks bebas + chip saran: tempat yang pernah diisi, "Natalo Petshop", "Di rumah") | Opsional |
| Obat Cacing | "Berat saat ini (kg)" (prefill dari berat terakhir) + pemilih produk (rekomendasi otomatis + daftar + manual) + kartu saran dosis | Lihat bagian Rekomendasi & Dosis |
| Obat Kutu | Sama seperti Obat Cacing, difilter kategori produk "obat kutu" | Kartu dosis visual dibedakan warnanya dari Obat Cacing (bukan beda logika) |
| Vaksin | "Nama vaksin" (teks bebas, mis. Rabies/Tricat) + "Dokter hewan/tempat" (teks bebas + chip saran riwayat) | Keduanya opsional |
| Periksa Dokter | "Keluhan/tujuan kunjungan" (teks bebas) + "Dokter hewan/tempat" (teks bebas + chip saran riwayat) | Label kategori **tetap "Periksa Dokter"** (user memutuskan tidak diganti nama) |
| Lainnya | Tidak ada tambahan | Tetap seperti sekarang |

Istilah **"Dokter Hewan"** dipakai konsisten sebagai label generik, bukan "Klinik" (keputusan user).

## Berat badan pet

- Field baru `Pet.weightKg` (double, opsional, null = belum pernah diisi) + tabel riwayat berat (dipakai untuk prefill "terakhir: X kg (tanggal)" dan berpotensi jadi grafik pertumbuhan di tahap Journey — di luar scope sini, cukup sediakan datanya).
- Diisi hanya lewat form Obat Cacing/Obat Kutu (bukan field baru di Edit Profil — sudah diputuskan user, opsi "di form perawatan" dipilih eksplisit).
- Saat record Obat Cacing/Obat Kutu disimpan dengan `weightKg` terisi: `Pet.weightKg` diperbarui + baris riwayat berat baru ditambahkan. Tidak menimpa riwayat lama.
- Field boleh dikosongkan (opsional) — kalau kosong, rekomendasi produk & kartu dosis tidak tampil (fallback: pemilih produk tanpa penyaringan berat, tanpa kartu dosis).

## Produk obat dari katalog Natalo

### Penandaan produk (Admin)

Produk butuh 3 atribut baru (nullable, backward-compatible, hanya relevan untuk produk kategori obat):
- `careCategory`: `'deworm' | 'flea' | null` — menandai produk ini obat cacing/kutu. Produk lain (non-obat) tetap `null`, tidak terpengaruh.
- `targetSpecies`: daftar spesies yang cocok (subset `kPetTypes`, mis. `['Anjing']`, `['Anjing','Kucing']`).
- `dosageRules`: daftar aturan dosis terstruktur — tiap aturan berisi rentang berat (`minKg`, `maxKg` opsional/tak terbatas) + teks anjuran pakai (mis. "1/2 tablet"). Disimpan sebagai JSON di kolom produk (pola sama `notificationPrefs` — JSON column, tidak perlu tabel relasi baru untuk data sekecil ini).

### Pengisian dosis (Admin, perluasan AI deskripsi)

- Endpoint AI generate-deskripsi yang sudah ada (`lib/ai/*`) diperluas: ketika produk berkategori obat (`careCategory` terisi), AI sekaligus mengembalikan draft `dosageRules` hasil ekstraksi dari info/deskripsi produk.
- Draft tampil di form admin sebagai field terpisah di bawah deskripsi (bukan auto-simpan) — **admin wajib review & simpan manual**, sama seperti alur deskripsi AI saat ini.
- Tombol "Ekstrak dosis dari deskripsi" tersedia terpisah untuk produk yang deskripsinya sudah ada tanpa generate ulang.
- Kalau AI tidak menemukan aturan pakai di deskripsi, field dikosongkan — bukan blocker, admin isi manual dari kemasan atau dibiarkan kosong (produk itu lalu jatuh ke fallback generik di app).
- Tidak ada endpoint/pemanggilan AI dari app Flutter untuk fitur ini.

### Pemilih produk & rekomendasi otomatis (App)

Saat kategori Obat Cacing/Obat Kutu dipilih dan berat terisi:

1. App memanggil endpoint pencarian produk `careCategory` yang sesuai + `targetSpecies` mengandung `Pet.type` + `dosageRules` mengandung rentang yang mencakup berat itu.
2. **Semua produk yang cocok ditampilkan sebagai satu daftar** (bukan 1 rekomendasi + sisanya disembunyikan) — supaya user dengan budget berbeda tetap bisa memilih sendiri. Urutan: stok tersedia dulu, lalu termurah ke termahal. Produk teratas boleh diberi badge kecil "Paling sesuai" (visual saja, tidak menyembunyikan yang lain), tapi semua item dalam daftar sama-sama bisa di-tap, ukuran & kejelasan tampilan setara.
3. Tap salah satu produk → kartu saran dosis di bawah pemilih otomatis terisi (anjuran pakai dari `dosageRules` produk itu, dihitung untuk berat pet).
4. Daftar produk kategori itu **tanpa** filter berat (untuk kasus berat belum diisi, atau user ingin lihat semua opsi termasuk yang di luar rentang dosis tercatat) tetap bisa diakses — mis. lewat "Lihat semua produk kategori ini".
5. Opsi "Ketik manual" selalu ada (untuk obat yang dibeli di luar Natalo) — dua field: "Nama brand" (teks bebas, wajib bila jalur manual dipilih) + **"Aturan pakai" (teks bebas, opsional)** untuk user mencatat dosis dari kemasan sendiri (catatan pribadi, bukan validasi sistem — field terpisah dari "Catatan" umum supaya tidak tumpang tindih). Kalau "Aturan pakai" kosong, tampil kartu fallback generik: "Dosis obat cacing/kutu umumnya dihitung per kg berat badan — cek kemasan atau tanya dokter hewan." Kalau diisi, isi field itu yang tampil di kartu & riwayat (label "Dicatat sendiri", bukan "Anjuran pakai" — supaya jelas ini bukan data resmi produk).
6. Kalau tidak ada produk yang cocok sama sekali (tidak ada hasil query): langsung tampil daftar produk kategori (tanpa badge) + opsi manual — tidak pernah kosong/error.

## Data model (Prisma) — tambahan pada `PetCareRecord`

Field baru, semua opsional (backward-compatible dengan record Tahap 3 yang sudah ada):

```prisma
model PetCareRecord {
  // ...field existing dari Tahap 3 tidak berubah...
  productId   String?  // FK opsional ke Product, terisi bila brand dipilih dari katalog
  brandText   String?  // nama brand manual (dipakai bila productId null, obat dibeli di luar Natalo)
  dosageNote  String?  // "Aturan pakai" dicatat sendiri user (khusus jalur manual brandText, opsional)
  weightKg    Float?   // berat pet saat pencatatan (khusus deworm/flea)
  place       String?  // "tempat" — dipakai grooming (tempat grooming) & vaccine/vet (dokter hewan/tempat)
  vaccineName String?  // khusus kategori vaccine
  complaint   String?  // khusus kategori vet (keluhan/tujuan kunjungan)
}
```

Product (tambahan, semua nullable):

```prisma
model Product {
  // ...field existing tidak berubah...
  careCategory   String?  // 'deworm' | 'flea' | null
  targetSpecies  Json?    // string[] subset kPetTypes, null = semua spesies
  dosageRules    Json?    // [{ minKg: number, maxKg: number|null, instruction: string }]
}
```

## API — tambahan

- `POST /api/member/pets/{id}/care` (existing, Tahap 3) — payload bertambah field opsional `productId`, `brandText`, `weightKg`, `place`, `vaccineName`, `complaint`. Validasi: field khusus kategori (mis. `complaint`) tidak wajib walau kategori vet.
- Saat `weightKg` terisi pada kategori deworm/flea → server update `Pet.weightKg` + insert baris riwayat berat (tabel baru `PetWeightLog` atau kolom histori sederhana — detail teknis di plan, bukan blocker desain).
- `GET /api/products/care-recommendation?category=deworm&species=Anjing&weightKg=4.5` (baru) → daftar produk cocok urut stok+harga, dipakai app untuk rekomendasi. Tanpa hasil → array kosong (app fallback ke daftar biasa).
- Admin: endpoint AI generate-deskripsi existing diperluas menerima/mengembalikan `dosageRules` draft tambahan saat `careCategory` produk terisi.

## Di luar scope spec ini

- Tombol "Beli lagi" dari riwayat perawatan & pengingat jadwal yang menawarkan produk yang sama — didokumentasikan sebagai arah lanjutan, **ditunda ke tahap berikutnya**.
- Grafik pertumbuhan berat badan (Journey, Tahap 4+).
- Riwayat "tempat" lintas-pet (chip saran diambil dari riwayat pet yang sama saja, bukan gabungan semua pet user, untuk privasi & kesederhanaan).
- Edit record (tetap hapus + catat ulang, sesuai keputusan Tahap 3).

## Testing (arah, detail di plan)

- Unit: pemilihan produk rekomendasi (urutan stok/harga, filter spesies+berat), update `Pet.weightKg`+riwayat saat record deworm/flea disimpan, validasi payload field baru.
- Admin: ekstraksi `dosageRules` draft tidak auto-simpan tanpa aksi admin.
- Flutter widget test: form berubah sesuai kategori (5 varian kolom), kartu rekomendasi muncul/tidak muncul sesuai hasil query, fallback manual selalu tersedia.
