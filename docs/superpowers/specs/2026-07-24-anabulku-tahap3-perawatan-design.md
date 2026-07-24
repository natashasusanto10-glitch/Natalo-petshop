# Anabulku Tahap 3 — Perawatan (riwayat + jadwal) — Design

Tanggal: 2026-07-24. Status: disetujui user (Desain C — agenda + hitung mundur, banner merah saat terlambat).

## Ringkasan

Fitur Perawatan untuk pet (Anabulku): **riwayat lengkap** perawatan per pet + **jadwal berikutnya** opsional per catatan, tampil **in-app saja** (tanpa push notification — bisa jadi Tahap 3b). Privat, hanya pemilik pet.

Keputusan user:
- Model data: **riwayat lengkap** (tabel baru `PetCareRecord`), bukan sekadar 2 field tanggal.
- Kategori (urutan prioritas): **Grooming, Obat Cacing, Obat Kutu, Vaksin, Periksa Dokter**. Periksa Dokter insidental (di Indonesia tidak rutin) — tanpa tekanan jadwal; field "jadwal berikutnya" opsional per catatan.
- Reminder: in-app saja (badge status), tanpa push.
- Layout: **Desain C** — banner jadwal terdekat + kartu mini hitung-mundur + riwayat list; **banner merah saat terlambat, biru brand saat normal**.

## Data model (Prisma)

Tabel baru:

```prisma
model PetCareRecord {
  id        String    @id @default(cuid())
  petId     String
  pet       Pet       @relation(fields: [petId], references: [id], onDelete: Cascade)
  category  String    // 'grooming' | 'deworm' | 'flea' | 'vaccine' | 'vet'
  doneAt    DateTime  // tanggal perawatan dilakukan
  note      String?   // catatan bebas, max 200 char (trim, kosong -> null)
  nextDueAt DateTime? // jadwal berikutnya, opsional
  createdAt DateTime  @default(now())

  @@index([petId, doneAt])
}
```

- Field lama `Pet.vaccineReminderAt` / `Pet.groomingReminderAt` **tidak dipakai** (tetap di schema, tidak dihapus di tahap ini — tidak ada konsumen).
- "Jadwal terdekat" = record dengan `nextDueAt` terkecil yang belum di-supersede. Aturan supersede: `nextDueAt` sebuah record dianggap aktif selama **belum ada record lain kategori sama dengan `doneAt` >= record itu**. (Contoh: catat grooming baru → jadwal grooming lama otomatis dianggap selesai.)
- Migration: `CREATE TABLE IF NOT EXISTS`-style migration standar Prisma.

## API (Next.js, /api/member/pets/[id]/care)

Semua ber-auth member + cek kepemilikan pet (pola sama endpoint pets yang ada).

- `GET /api/member/pets/{id}/care` → `{ records: [...], upcoming: [...] }` — records urut `doneAt` desc; `upcoming` = daftar jadwal aktif (per kategori, hasil aturan supersede) urut `nextDueAt` asc, dihitung server-side.
- `POST /api/member/pets/{id}/care` → buat record `{ category, doneAt, note?, nextDueAt? }`. Validasi: category dalam set, doneAt wajib tanggal valid, note trim max 200, nextDueAt (jika ada) harus > doneAt.
- `DELETE /api/member/pets/{id}/care/{recordId}` → hapus record (konfirmasi di app).
- Edit record: **tidak ada di Tahap 3** (hapus + catat ulang; YAGNI).
- `GET /api/member/pets` (list) ditambah `careCount` per pet (untuk stat "Perawatan" di profil) + `nearestDue` (kategori+tanggal+overdue) untuk section ringkas — satu query agregat, tanpa N+1.

## Flutter — 3 permukaan

Font/spacing/warna WAJIB identik pola Anabulku yang ada: appBar ikut `appBarTheme` global (tanpa override), judul/nama `NataloWeight.strong`, caption `NataloWeight.body`, kartu `cs.surfaceContainerHighest` atau `cs.surface`+outlineVariant, radius 12–14, padding horizontal 20, brand `NataloColors.primary`.

### 1. Section "Perawatan" di PetProfileScreen

Menggantikan bagian kartu "Segera hadir" (kartu segera-hadir tetap ada tapi teksnya tinggal "Journey dan Belanja"). Isi:
- Header baris: "Perawatan" (13/strong) + "Lihat semua" (11/strong, brand) → push halaman Perawatan.
- Kartu jadwal terdekat (maks 2): ikon kategori + judul + tanggal + badge. **Terlambat** = kartu tint merah (`cs.errorContainer`-style: merah muda bg + teks merah tua) + badge merah; **Segera** (≤14 hari) = badge biru; selain itu netral.
- "TERAKHIR DICATAT": 2 baris riwayat terakhir polos (ikon 15 + teks 11/body).
- Stat "Perawatan" di `_StatsRow` menampilkan `careCount` dan bisa di-tap → halaman Perawatan.
- Kosong total (belum ada record): section menampilkan satu kartu ajakan "Catat perawatan pertama {nama}" (netral, ikon + teks 12) → buka form.

### 2. Halaman "Perawatan {nama}" (PetCareScreen, baru)

- AppBar global, judul `Perawatan {nama}`.
- **Banner jadwal terdekat** (hanya jika ada jadwal): kartu besar radius 14, isi label kecil "JADWAL TERDEKAT", judul kategori 20/strong, badge status + tanggal + aksi "Tandai selesai".
  - Normal/Segera: bg `NataloColors.primary`, teks putih (dark mode: sama, brand tetap terbaca).
  - **Terlambat: bg merah** (`NataloColors`/theme error solid), teks putih, badge "Terlambat N hari".
  - "Tandai selesai": membuat record baru kategori sama dengan `doneAt` = hari ini (note kosong), lalu bottom-sheet ringan menawarkan jadwal berikutnya (+1 bulan / +3 bulan / pilih tanggal / lewati). Jadwal lama otomatis tersupersede.
- **Kartu mini** (baris horizontal, maks 2-3): jadwal aktif lain per kategori — ikon + label kategori 10/body + "N hari lagi" 12.5/strong. Terlambat → angka merah.
- **Riwayat**: label kecil "RIWAYAT" + list kronologis desc — tile ikon kotak 30 (bg primarySoft / brandBlue-alpha di dark) + judul kategori 13/strong + tanggal • note (11.5/body, onSurfaceVariant). Long-press / tombol titik-tiga → hapus (dialog konfirmasi pola app).
- **FAB** brand `+` → form Catat Perawatan.
- Chip filter kategori di bawah appBar: Semua (default) + 5 kategori urutan prioritas. Filter client-side.
- Empty state (tanpa record & tanpa jadwal): ilustrasi ikon + teks ajakan + tombol "Catat perawatan" (pola empty state Anabulku).
- Loading: shimmer pola app; error: error-view unify pola app.

### 3. Form "Catat Perawatan" (bottom sheet penuh atau layar, ikut pola PetFormScreen)

- Jenis perawatan: 5 chip pilih-satu (urutan: Grooming, Obat Cacing, Obat Kutu, Vaksin, Periksa Dokter), tinggi ≥44 tap target, gaya `_GenderChip` yang ada.
- Tanggal dilakukan: date picker (default hari ini, tidak boleh masa depan).
- Catatan: TextField opsional max 200 (perhatikan gotcha fillColor global: filled:false/transparent bila di atas permukaan berwarna).
- Jadwal berikutnya (opsional): chip shortcut `+1 bulan`, `+3 bulan`, `Pilih tanggal`, bisa dikosongkan (khusus Periksa Dokter memang biasanya kosong).
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

Push notification/cron (Tahap 3b), edit record, lampiran foto pada record, Journey/Belanja (Tahap 4-5), route publik.
