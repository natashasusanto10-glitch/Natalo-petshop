# Edit Postingan — gaya IG "Edit info" + unifikasi alur edit — Design

## Latar belakang

Halaman Postingan (`member_post_detail_screen.dart`), tombol "..." → "Edit caption", membuka `_EditCaptionSheet`: bottom sheet sederhana (judul + subtitle peringatan + satu `TextField` berkotak/filled dengan `hintText` + tombol Batal/Simpan). Dibandingkan dengan layar "Edit info" Instagram (full-screen, header X/centang, caption menempel tanpa kotak, baris-baris section polos), tampilan kita terasa jauh lebih sederhana dan salah gaya (masih pakai gaya kotak ber-placeholder yang sudah ditinggalkan desain lain di app ini).

Ditemukan saat eksplorasi: ada SATU LAGI layar edit post yang sudah dibangun lengkap — `MemberPostEditScreen` (`member_post_edit_screen.dart`), terdaftar sebagai route `/member/post-edit` di `main.dart:419` — tapi **tidak pernah dipanggil dari mana pun** di codebase (dead code). Layar ini punya cover thumbnail, caption editor, kartu kelola produk ditandai (`_TaggedProductsCard` + `_TaggedProductPickerSheet`), catatan review, tombol Simpan/Batal — tapi juga masih pakai gaya `TextField` berkotak (`filled: true`, `OutlineInputBorder`, `hintText`) yang sama masalahnya.

Konsekuensi penting yang ditemukan: `_EditCaptionSheet`'s save path (`_editCaption()` di `member_post_detail_screen.dart:658-684`) cuma PATCH langsung ke API — **tidak** sync ke `feedStore` — sedangkan `MemberPostEditScreen._save()` SUDAH sync ke `feedStore.applyPostUpdate(...)`, yang otomatis mempropagasi caption baru ke semua layar lain yang membaca `feedStore` (Feed, Postingan Saya, Detail manapun). Jadi alur lama berpotensi caption baru tidak langsung terlihat di layar lain sampai di-refresh manual — sebuah bug sync laten.

## Tujuan

1. Satu-satunya alur edit postingan di app ini adalah `MemberPostEditScreen` (dipakai dari titik masuk manapun) — hapus `_EditCaptionSheet` dan seluruh alur bottom-sheet-nya.
2. Restyle `MemberPostEditScreen` mengikuti bahasa visual IG "Edit info": full-screen (bukan sheet), header dengan tombol **X** (batal, kiri) + tombol **centang** bulat solid (simpan, kanan) menggantikan `AppBar` + tombol Simpan/Batal di bawah; caption `TextField` **tanpa kotak/placeholder-box** (borderless, menyatu dengan latar, menempel di sebelah thumbnail seperti menulis langsung di halaman).
3. Baris "Produk ditandai" jadi baris list polos (label + ringkasan pilihan + chevron), bukan kartu tebal `_TaggedProductsCard` — tapi FUNGSI kartu lama (buka `_TaggedProductPickerSheet`, tampilkan count) dipertahankan, cuma dibungkus tampilan baris.
4. Catatan review ("Catatan: perubahan pada postingan yang sudah tayang akan masuk review admin lagi...") **HANYA tampil untuk video** (`widget.post.isVideo == true`). Untuk foto/carousel, strip ini disembunyikan total — karena foto/carousel customer sekarang auto-ACTIVE (lihat `lib/feed/post-moderation.ts`, memory: "Feed auto-approve foto/carousel"), jadi perubahan pada foto/carousel TIDAK memicu status balik ke review.
5. Perilaku sync-ke-`feedStore` yang sudah benar di `MemberPostEditScreen._save()` **dipertahankan sepenuhnya** — termasuk logika `wasActive ? 'PENDING_REVIEW' : existing.status` untuk status. **Catatan penting:** logika reset-status-ke-review-ulang ini SAAT INI tidak membedakan video vs foto/carousel (selalu reset ke PENDING_REVIEW kalau `wasActive`). Sesuai poin 4 (tampilan notice), backend/logic status reset JUGA harus digerbang oleh `post.isVideo` — kalau foto/carousel yang di-edit, JANGAN reset status ke PENDING_REVIEW sama sekali (foto/carousel auto-approve, tidak perlu "review ulang").

## Arsitektur

### Entry point (unifikasi)

- `member_post_detail_screen.dart`: `_editCaption(int index)` diganti isinya — bukan lagi `showModalBottomSheet` dengan `_EditCaptionSheet`, tapi:
  ```dart
  final updated = await Navigator.pushNamed(
    context,
    '/member/post-edit',
    arguments: post,
  );
  ```
  Setelah kembali, TIDAK perlu lagi PATCH manual di sini (itu sudah dilakukan `MemberPostEditScreen`) — cukup refresh state lokal `_posts[index]` dari `feedStore.get(post.id)` kalau ada perubahan (pola serupa yang sudah dipakai `MemberPostEditScreen._save()` sendiri saat sync balik).
- `_PostMenuSheet` (menu "..." ) **tidak berubah** — masih mengembalikan `_PostMenuAction.edit`/`.delete`, cuma handler `.edit`-nya yang berubah isi implementasinya.
- Hapus total: class `_EditCaptionSheet` dan `_EditCaptionSheetState` dari `member_post_detail_screen.dart` (~baris 3121-3249) — tidak dipakai lagi di mana pun setelah perubahan ini.

### `MemberPostEditScreen` — restyle header

- Ganti `Scaffold.appBar` (AppBar dengan title "Edit Postingan") → `Scaffold.body` dibungkus `Column` dengan baris header custom di paling atas:
  ```dart
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _saving ? null : () => Navigator.pop(context),
      ),
      Text('Edit info', style: TextStyle(fontSize: 16, fontWeight: NataloWeight.strong)),
      _SaveCheckButton(saving: _saving, onTap: _saving ? null : _save),
    ],
  )
  ```
- `_SaveCheckButton`: lingkaran solid diameter 32, warna `NataloColors.primary` (brand blue, konsisten dengan tombol Simpan lama), isi `Icon(Icons.check_rounded, color: Colors.white, size: 18)` saat idle, `CircularProgressIndicator(strokeWidth: 2, color: Colors.white)` ukuran 16×16 saat `_saving == true`.
- Tombol `FilledButton('Simpan Perubahan')` dan `TextButton('Batal')` di bagian bawah `ListView` **dihapus total** — digantikan sepenuhnya oleh header X/centang.

### `MemberPostEditScreen` — caption tanpa kotak

- Hapus label terpisah `Text('Caption', ...)` di atas field (IG tidak punya label section untuk caption — caption langsung jadi konten utama).
- `TextField` untuk caption diubah dekorasinya:
  ```dart
  decoration: InputDecoration(
    hintText: 'Tulis caption...',
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    filled: false,
    contentPadding: EdgeInsets.zero,
    isDense: true,
  ),
  ```
  (Tidak ada lagi `filled: true`, `fillColor`, `OutlineInputBorder`.)
- Field ini diletakkan dalam `Row` di sebelah cover thumbnail (bukan di bawahnya seperti sekarang) — thumbnail 56×56 rounded-8 di kiri, `Expanded(child: TextField(...))` di kanan, meniru susunan IG persis. `minLines`/`maxLines`/`maxLength` (`_maxCaptionLength = 280`) tidak berubah.
- Teks "Video/Media tidak bisa diganti..." tetap ada, tapi dipindah jadi caption kecil DI BAWAH seluruh card (bukan langsung di bawah thumbnail seperti sekarang) — posisi presisinya fleksibel, prioritas utama adalah caption+thumbnail row yang meniru IG.

### `MemberPostEditScreen` — baris "Produk ditandai"

- `_TaggedProductsCard` (card tebal dengan border) diganti jadi `ListTile`-style row datar:
  ```dart
  InkWell(
    onTap: _saving ? null : onManage,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Produk ditandai'),
        Row(children: [
          Text(selectedCount == 0 ? 'Tambah' : '$selectedCount dipilih'),
          Icon(Icons.chevron_right_rounded),
        ]),
      ],
    ),
  )
  ```
  dipisah dari section caption dengan `Divider` tipis (`height: 1, color: cs.outlineVariant`), meniru pemisah antar-row IG.
- **Tidak ada perubahan fungsi**: `onManage` tetap memanggil `_openProductPicker()` yang membuka `_TaggedProductPickerSheet` yang sudah ada — TIDAK dibangun ulang.
- Ringkasan produk terpilih (foto-foto kecil/list nama yang sebelumnya mungkin ditampilkan di dalam `_TaggedProductsCard`) **dihilangkan dari row utama** (IG "Add product details" juga cuma baris ringkas + chevron, detail dilihat setelah tap) — kalau ada logic tampilan lain di `_TaggedProductsCard` yang bukan cuma count, itu dipindah ke DALAM `_TaggedProductPickerSheet` (yang sudah render list produk), bukan dihapus fungsinya.

### Catatan review — gating video-only

- Kondisi render notice review diubah dari:
  ```dart
  if (widget.post.statusInfo == FeedPostStatus.active)
  ```
  menjadi:
  ```dart
  if (widget.post.statusInfo == FeedPostStatus.active && widget.post.isVideo)
  ```
- Di `_save()`, baris:
  ```dart
  status: wasActive ? 'PENDING_REVIEW' : existing.status,
  ```
  diubah menjadi:
  ```dart
  status: (wasActive && widget.post.isVideo) ? 'PENDING_REVIEW' : existing.status,
  ```
  — foto/carousel yang sudah aktif TIDAK direset ke `PENDING_REVIEW` sama sekali saat caption/produk-nya diubah.
- Toast setelah simpan juga disesuaikan: pesan "Perubahan tersimpan. Postingan masuk review ulang." hanya muncul kalau `wasActive && widget.post.isVideo`; selain itu cukup "Perubahan tersimpan."

## Interaksi dengan backend

Spec ini **tidak mengubah** endpoint `feedService.updateMyPost(...)` maupun payload API — hanya logika CLIENT yang menentukan APAKAH client mengirim status reset. Perlu dicek saat implementasi: apakah backend (`/api/feed/posts/:id` PATCH) sendiri SUDAH punya guard serupa (foto/carousel tidak direset ke PENDING_REVIEW oleh server terlepas dari apa yang dikirim client) — kalau backend belum punya guard ini, ada risiko client mengirim field yang backend abaikan/override balik ke PENDING_REVIEW. Item ini WAJIB diverifikasi di awal implementasi (baca `lib/feed/post-moderation.ts` dan handler PATCH endpoint terkait) sebelum menganggap sisi client saja cukup — kalau ternyata backend architecture yang menentukan (bukan payload dari client), maka perubahan yang relevan ada di backend (Next.js), bukan di Flutter `_save()`.

## Testing

- Widget test baru/olah untuk `MemberPostEditScreen`:
  - Header menampilkan ikon X dan tombol centang bulat (bukan `AppBar` dengan title lama, bukan tombol Simpan Perubahan/Batal di bawah).
  - Tap X → `Navigator.pop` tanpa memanggil `_save`.
  - Tap centang → memanggil `_save()` (memverifikasi lewat spy/interaksi API atau state `_saving` berubah).
  - Caption `TextField` tidak lagi punya border/fill (uji lewat `find.byType(TextField)` → cek `InputDecoration.border is InputBorder.none` atau setara — atau uji visual golden).
  - Baris "Produk ditandai" tampil sebagai row (bukan Container/Card lama) dan tap memicu `_openProductPicker` seperti sebelumnya.
  - Notice review: render untuk `post.isVideo == true && statusInfo == active`; TIDAK render untuk `post.isVideo == false` (foto/carousel) meski `statusInfo == active`.
  - `_save()` mengirim/menghasilkan `status` tetap `existing.status` (tidak berubah ke PENDING_REVIEW) untuk kasus foto/carousel aktif; berubah ke PENDING_REVIEW untuk kasus video aktif — sama seperti sebelumnya.
- Update/hapus test lama yang menguji `_EditCaptionSheet` di `member_post_detail_screen.dart` punya test file — cari & sesuaikan (kemungkinan `member_post_detail_screen_test.dart` atau serupa) supaya tidak menguji sheet yang sudah dihapus; ganti dengan test yang menguji `_editCaption(index)` memicu navigasi ke route `/member/post-edit` dengan `arguments: post` yang benar.
- `flutter analyze` bersih, `flutter test` untuk file-file yang disentuh hijau semua.

## Yang TIDAK berubah (di luar cakupan)

- Endpoint/payload API `feedService.updateMyPost` — struktur data tidak berubah.
- `_TaggedProductPickerSheet` — sheet picker produk itu sendiri tidak di-redesign, cuma dipanggil dari row baru bukan card lama.
- Fitur-fitur IG "Edit info" yang tidak relevan dengan data model app ini (Tag people, Add location, Add AI Label, Content funding) — TIDAK ditambahkan, karena app ini tidak punya konsep tersebut untuk feed post. Cakupan hanya meniru BAHASA VISUAL (header X/centang, caption tanpa kotak, baris list polos), bukan replikasi 1:1 semua section IG.
- Video/foto media itu sendiri tetap tidak bisa diganti (upload ulang required) — tidak berubah.
