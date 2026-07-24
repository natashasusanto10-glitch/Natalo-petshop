# Anabulku Tahap 3 — Perawatan (riwayat + jadwal) — Design

Tanggal: 2026-07-24. Status: disetujui user (Desain C — agenda + hitung mundur, banner merah saat terlambat).

## Ringkasan

Fitur Perawatan untuk pet (Anabulku): **riwayat lengkap** perawatan per pet + **jadwal berikutnya** opsional per catatan, tampil **in-app saja** (tanpa push notification — bisa jadi Tahap 3b). Privat, hanya pemilik pet.

Keputusan user:
- Model data: **riwayat lengkap** (tabel baru `PetCareRecord`), bukan sekadar 2 field tanggal.
- Kategori (urutan prioritas): **Grooming, Obat Cacing, Obat Kutu, Vaksin, Periksa Dokter, Lainnya**. Periksa Dokter insidental (di Indonesia tidak rutin) — tanpa tekanan jadwal; field "jadwal berikutnya" opsional per catatan. "Lainnya" menampung operasi/lab/tes/dll.
- Reminder: in-app saja (badge status), tanpa push.
- Layout: **Desain C** — banner jadwal terdekat + kartu mini hitung-mundur + riwayat list; **banner merah saat terlambat, biru brand saat normal**.

## Data model (Prisma)

Tabel baru:

```prisma
model PetCareRecord {
  id        String    @id @default(cuid())
  petId     String
  pet       Pet       @relation(fields: [petId], references: [id], onDelete: Cascade)
  category  String    // 'grooming' | 'deworm' | 'flea' | 'vaccine' | 'vet' | 'other'
  doneAt    DateTime  // tanggal perawatan dilakukan
  note      String?   // catatan bebas, max 200 char (trim, kosong -> null)
  nextDueAt DateTime? // jadwal berikutnya, opsional
  createdAt DateTime  @default(now())

  @@index([petId, doneAt])
}
```

- Field lama `Pet.vaccineReminderAt` / `Pet.groomingReminderAt` **tidak dipakai** (tetap di schema, tidak dihapus di tahap ini — tidak ada konsumen).
- Field baru di `Pet` (info kesehatan statis, hasil banding referensi): `sterilized Boolean?` (null = belum diisi), `allergy String?` (max 100), `healthNote String?` ("kondisi khusus", max 150). Diedit lewat form Edit Pet, ikut `validatePetPayload`.
- "Jadwal terdekat" = record dengan `nextDueAt` terkecil yang belum di-supersede. Aturan supersede: `nextDueAt` sebuah record dianggap aktif selama **belum ada record lain kategori sama dengan `doneAt` >= record itu**. (Contoh: catat grooming baru → jadwal grooming lama otomatis dianggap selesai.)
- Migration: `CREATE TABLE IF NOT EXISTS`-style migration standar Prisma.

## API (Next.js, /api/member/pets/[id]/care)

Semua ber-auth member + cek kepemilikan pet (pola sama endpoint pets yang ada).

- `GET /api/member/pets/{id}/care` → `{ records: [...], upcoming: [...] }` — records urut `doneAt` desc; `upcoming` = daftar jadwal aktif (per kategori, hasil aturan supersede) urut `nextDueAt` asc, dihitung server-side.
- `POST /api/member/pets/{id}/care` → buat record `{ category, doneAt, note?, nextDueAt? }`. Validasi: category dalam set, doneAt wajib tanggal valid, note trim max 200, nextDueAt (jika ada) harus > doneAt.
- `DELETE /api/member/pets/{id}/care/{recordId}` → hapus record (konfirmasi di app).
- Edit record: **tidak ada di Tahap 3** (hapus + catat ulang; YAGNI).
- `GET /api/member/pets` (list) ditambah `careCount` per pet (untuk stat "Perawatan" di profil) + `nearestDue` (kategori+tanggal+overdue) untuk section ringkas — satu query agregat, tanpa N+1.

## Flutter — 4 permukaan

Font/spacing/warna WAJIB identik pola Anabulku yang ada (dikunci ke angka aktual di kode, bukan "kira-kira sama"):

| Elemen | Token |
|---|---|
| AppBar | `appBarTheme` global saja, tanpa override (18/w700, flat+hairline) |
| Judul section (mis. "Perawatan", "Pet Saya") | 13–17/`NataloWeight.strong`, sesuai level (lihat per-layar di bawah) |
| Caption/label/subjudul | 11–12.5/`NataloWeight.body`, warna `cs.onSurfaceVariant` |
| Nama pet di kartu | 15/`NataloWeight.strong` (padding horizontal 20, sama file `anabulku_screen.dart`) |
| Kartu list pet | minHeight 72, padding 12, radius 16, `cs.surface`+`Border.all(cs.outlineVariant)`+shadow tipis (black 0.05, blur 3) |
| Chip kategori/status | 10–11/`NataloWeight.strong`, radius 999, tinggi visual sama `_GenderChipMini`/`_NeutralChip` |
| Kartu section/jadwal | radius 12–14, `cs.surfaceContainerHighest` (netral) atau tint merah/biru theme-aware (lihat tabel status) |
| Padding horizontal halaman | 20 (sama semua layar Anabulku) |
| Brand | `NataloColors.primary` (#1E5FBF) |

Semua nilai di atas diambil langsung dari `anabulku_screen.dart` dan `pet_profile_screen.dart` saat ini — implementasi tidak boleh memperkenalkan ukuran font/weight/radius baru di luar tabel ini tanpa alasan kuat.

### 0. Halaman list Anabulku (AnabulkuScreen, update)

- **Chip jadwal di kartu pet**: tile pet menampilkan chip tambahan bila punya jadwal (`nearestDue` dari endpoint list): "Obat Cacing • 4 hari lagi" (netral/biru) atau merah bila terlambat. Tanpa jadwal → tanpa chip (tampilan sekarang).
- **Section "Jadwal Terdekat"** di bawah daftar pet (hanya bila ada minimal 1 jadwal, gabungan semua pet): baris `{NamaPet} — {Kategori}` + tanggal + badge hari-lagi/terlambat, urut `nextDueAt` asc, maks 3 + "Lihat semua" tidak perlu (tap baris → PetCareScreen pet terkait). Gaya baris sama dengan riwayat (ikon kotak 30).

### 1. Section "Perawatan" di PetProfileScreen

Menggantikan bagian kartu "Segera hadir" (kartu segera-hadir tetap ada tapi teksnya tinggal "Journey dan Belanja"). Isi:
- Header baris: "Perawatan" (13/strong) + "Lihat semua" (11/strong, brand) → push halaman Perawatan.
- Kartu jadwal terdekat (maks 2): ikon kategori + judul + tanggal + badge. **Terlambat** = kartu tint merah (`cs.errorContainer`-style: merah muda bg + teks merah tua) + badge merah; **Segera** (≤14 hari) = badge biru; selain itu netral.
- "TERAKHIR DICATAT": 2 baris riwayat terakhir polos (ikon 15 + teks 11/body).
- Stat "Perawatan" di `_StatsRow` menampilkan `careCount` dan bisa di-tap → halaman Perawatan.
- Kosong total (belum ada record): section menampilkan satu kartu ajakan "Catat perawatan pertama {nama}" (netral, ikon + teks 12) → buka form.
- **Baris info kesehatan** (di bawah bio, hanya field yang terisi): "Steril: Ya/Belum", "Alergi: {allergy}", "Kondisi: {healthNote}" — teks 12/body dengan label 12/strong, gaya baris ringkas (bukan kartu). Diedit lewat form Edit Pet (toggle Steril + 2 TextField opsional).

### 2. Halaman "Perawatan {nama}" (PetCareScreen, baru)

- AppBar global, judul `Perawatan {nama}`.
- **Banner jadwal terdekat** (hanya jika ada jadwal): kartu besar radius 14, judul kategori 20/strong, badge status + tanggal + aksi "Tandai selesai". Label kecil di atas judul mengikuti status:
  - Normal/Segera: label "JADWAL TERDEKAT", bg `NataloColors.primary`, teks putih (dark mode: sama, brand tetap terbaca).
  - **Terlambat**: label **"SUDAH LEWAT JADWAL"**, bg merah (`NataloColors`/theme error solid), teks putih, badge "Terlambat N hari".
  - "Tandai selesai": membuat record baru kategori sama dengan `doneAt` = hari ini (note kosong), lalu bottom-sheet ringan menawarkan jadwal berikutnya (+1 bulan / +3 bulan / pilih tanggal / lewati). Jadwal lama otomatis tersupersede.
- **Kartu mini** (baris horizontal, maks 2-3): jadwal aktif lain per kategori — ikon + label kategori 10/body + "N hari lagi" 12.5/strong. Terlambat → angka merah.
- **Riwayat**: label kecil "RIWAYAT" + list kronologis desc — tile ikon kotak 30 (bg primarySoft / brandBlue-alpha di dark) + judul kategori 13/strong + tanggal • note (11.5/body, onSurfaceVariant). Long-press / tombol titik-tiga → hapus (dialog konfirmasi pola app).
- **FAB** brand `+` → form Catat Perawatan.
- Chip filter kategori di bawah appBar: Semua (default) + 6 kategori urutan prioritas (…, Periksa Dokter, Lainnya). Filter client-side.
- Empty state (tanpa record & tanpa jadwal): ilustrasi ikon + teks ajakan + tombol "Catat perawatan" (pola empty state Anabulku).
- Loading: shimmer pola app; error: error-view unify pola app.

### 3. Form "Catat Perawatan" (bottom sheet penuh atau layar, ikut pola PetFormScreen)

- Jenis perawatan: 6 chip pilih-satu (urutan: Grooming, Obat Cacing, Obat Kutu, Vaksin, Periksa Dokter, Lainnya), tinggi ≥44 tap target, gaya `_GenderChip` yang ada.
- Tanggal dilakukan: date picker (default hari ini, tidak boleh masa depan).
- Catatan: TextField opsional max 200 (perhatikan gotcha fillColor global: filled:false/transparent bila di atas permukaan berwarna).
- Jadwal berikutnya (opsional): chip shortcut `+1 bulan`, `+3 bulan`, `Pilih tanggal`, bisa dikosongkan (khusus Periksa Dokter memang biasanya kosong).
- Foto (opsional, maks 1): tombol "Tambah foto" — pilih dari galeri/kamera, compress (engine compress yang sama dengan foto pet), lalu **disimpan LOKAL di HP** (keputusan user, bukan server): salin ke `ApplicationDocumentsDirectory/pet_care/{recordId}.jpg` setelah POST sukses (recordId dari respons). Server tidak tahu soal foto (tanpa field baru). Thumbnail kecil di riwayat bila file ada; tap → lihat penuh. Hapus record → file ikut dihapus. Ganti HP/reinstall → foto hilang, record tetap utuh tanpa indikasi error.
- Simpan → POST, pop dengan hasil, list refresh; snackbar sukses pola app.

### Motion & aksesibilitas

- Entrance staggered fade+slide (pakai pola `_Entrance` PetProfileScreen persis: 520ms easeOutCubic, delay 90ms), reduced-motion aware.
- Badge/warna tidak jadi satu-satunya penanda status: teks "Terlambat N hari" / "N hari lagi" selalu ada.
- Dark mode: tint merah & biru pakai token theme (`cs.error*`, brandBlue alpha) — tidak ada hardcode grey/putih.

## Status & aturan tampilan

| Kondisi | Aturan |
|---|---|
| Terlambat | `nextDueAt` < hari ini → merah (banner solid merah; kartu section profil tint merah; badge "Terlambat N hari") |
| Segera | ≤ 14 hari lagi → badge biru "N hari lagi" |
| Normal | > 14 hari → netral, teks tanggal saja |
| Tanpa jadwal | tidak tampil di banner/kartu mini; hanya di riwayat |

## Testing

- Unit: aturan supersede + kalkulasi upcoming (server), validasi payload (category/doneAt/nextDueAt/note).
- Flutter widget test: banner merah vs biru, empty state, tandai-selesai flow (mock service), filter chip.
- `flutter analyze` + suite existing hijau.

## Di luar scope Tahap 3

Push notification/cron (Tahap 3b), edit record, upload foto record ke server (foto lokal-only per keputusan user; bisa di-upgrade sinkron nanti), Journey/Belanja (Tahap 4-5), route publik. Hasil banding referensi yang **sengaja tidak dimasukkan** (keputusan user): Dokumen Kesehatan, Grafik Berat Badan; ditunda: detail terstruktur per catatan (klinik/dokter/batch — cukup catatan bebas), tampilan kalender bulanan.
