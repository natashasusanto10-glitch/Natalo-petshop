# Spec D — Tandai Orang di Halaman Edit Postingan + Fix Konsistensi Badge Video

**Status: Approved — siap masuk writing-plans**

## Latar belakang

Halaman edit postingan (`MemberPostEditScreen`, dibuka lewat menu "..." →
Edit di post sendiri) saat ini cuma punya baris **"Produk ditandai"**. Tidak
ada cara untuk menambah/menghapus orang yang ditandai setelah post
dipublish — padahal fitur tag orang (Spec B) sudah ada penuh di alur
*create* (foto: titik interaktif per-foto; video: daftar sederhana).

Terpisah, ditemukan juga inkonsistensi tampilan: badge "Ditandai" pada
video muncul baik di feed utama (scroll biasa) maupun di halaman postingan
(dibuka dari grid profil) — padahal untuk foto, pill tag cuma muncul di
halaman postingan, tidak pernah di feed utama. Ini beda dari Instagram,
yang cuma menampilkan sheet "In this reel" di halaman Post/Reel individual,
tidak pernah di feed Reels utama.

## Bagian 1 — Edit tandai orang

### Foto (termasuk carousel)

Tambah baris **"Orang ditandai"** di `MemberPostEditScreen`, sejajar
"Produk ditandai". Tap membuka `FeedTagPeopleScreen` (layar titik
interaktif per-foto yang sama dipakai saat create), diisi (`initialTags`)
dari `FeedTaggedUser` post ini yang sudah ada (`x`/`y`/`mediaIndex`
existing dipertahankan kalau tidak diubah user). User bisa geser titik,
tambah titik baru (tap foto → search), atau hapus titik. Hasil akhir:
`List<NewPostUserTag>` lengkap (replace total, bukan diff manual).

### Video

Baris "Orang ditandai" yang sama (tampilan identik dengan versi foto) —
tap membuka `FeedTagPeopleVideoScreen` (daftar sederhana, tanpa posisi),
diisi dari tagged users existing. User bisa tambah/hapus nama dari
daftar. Hasil akhir: `List<NewPostUserTag>` (semua `mediaIndex`/`x`/`y`
null, sesuai kontrak video yang sudah ada).

**Baris entry-point di UI sama untuk foto & video** (sama seperti
"Produk ditandai" — satu baris, satu label, chevron kanan); yang berbeda
cuma layar yang dibuka di baliknya, bercabang berdasarkan `widget.post.isVideo`.

### Kontrak simpan (Flutter → API)

`FeedService.updateMyPost` dapat parameter baru:

```dart
Future<bool> updateMyPost(
  String postId, {
  required String title,
  String? description,
  List<String>? productIds,
  List<NewPostUserTag>? taggedUsers,   // baru
}) async {
  ...
  body: {
    ...
    if (taggedUsers != null)
      'taggedUsers': taggedUsers.map((t) => {
        'userId': t.userId,
        if (t.mediaIndex != null) 'mediaIndex': t.mediaIndex,
        if (t.x != null) 'x': t.x,
        if (t.y != null) 'y': t.y,
      }).toList(),
  },
}
```

Kirim seluruh daftar tagged users terbaru (full replace), sama seperti
`productIds` sekarang — bukan diff tambah/hapus per-item.

### Backend — `PATCH /api/feed/posts/[id]`

Saat ini route ini (`app/api/feed/posts/[id]/route.ts`) cuma menangani
`title`/`description`/`productIds`. Tambah:

- Terima `body.taggedUsers` (array, opsional — kalau tidak dikirim, tagged
  users existing tidak disentuh).
- Reuse `parseTaggedUsersInput` (`lib/feed/tagged-users.ts`, sudah dipakai
  kedua create route) untuk validasi — dapat `mediaCount` dari jumlah media
  post ini, `isVideo` dari `post.isVideo`. Kalau parse gagal (`ok: false`),
  return 400 dengan `error` dari hasil parse (konsisten dengan create route).
- Di dalam `$transaction` yang sama dengan update `title`/`description`/
  `productIds`: `deleteMany` semua `FeedTaggedUser` post ini, lalu
  `createMany` dari hasil parse — pola replace total, sama seperti
  `resyncPostHashtags` yang baru dibuat untuk Spec C.
- Response `GET`/`PATCH` yang sudah men-serialize `taggedUsers` (baris 260
  di route yang sama) otomatis mencerminkan data baru — tidak perlu
  perubahan di situ.

### Batasan yang tetap berlaku

- Maksimal 20 orang per post (`MAX_TAGGED_USERS_PER_POST`, sudah ada di
  `lib/feed/tagged-users.ts`) — enforced oleh `parseTaggedUsersInput` yang
  di-reuse, tidak perlu re-implementasi limit.
- Satu orang cuma bisa ditandai sekali per post (`@@unique([feedPostId,
  taggedUserId])` di schema) — dedupe sudah ditangani `parseTaggedUsersInput`.

## Bagian 2 — Fix konsistensi badge video

`FeedVideoPostView` (dipakai di 2 tempat: `feed_screen.dart` untuk feed
utama, dan `scoped_video_feed_screen.dart` untuk halaman
postingan/reel individual) menerima parameter baru:

```dart
final bool showTaggedBadge; // default: true
```

- `feed_screen.dart` (feed utama): set eksplisit `showTaggedBadge: false`.
- `scoped_video_feed_screen.dart` (halaman postingan): biarkan default
  `true` (tidak perlu diubah).

Baris rendering `FeedTaggedBadge` (sekitar baris 3541 di
`feed_video_post_view.dart`) dibungkus tambahan kondisi
`widget.showTaggedBadge &&`. Tidak ada perubahan pada `_openTaggedUsersSheet`
atau state `_tags` — badge cuma disembunyikan secara visual di konteks feed
utama, data tetap dimuat sama seperti sekarang (murah, tidak perlu query
kondisional).

## Testing

- Backend: test untuk `PATCH /api/feed/posts/[id]` dengan `taggedUsers` —
  tambah tag baru, hapus tag, ganti tag, lebih dari 20 (harus 400), video
  vs foto (mediaIndex/x/y required vs diabaikan).
- Flutter: widget test `MemberPostEditScreen` — baris "Orang ditandai"
  muncul untuk foto & video, tap pada masing-masing membuka layar yang
  benar, hasil terkirim ke `updateMyPost`.
- Flutter: `FeedVideoPostView` — badge tidak dirender saat
  `showTaggedBadge: false`, dirender saat `true`/default.

## Di luar cakupan (tidak dikerjakan di spec ini)

- Tidak ada perubahan pada alur *create* post (Spec B sudah selesai).
- Tidak ada perubahan pada tampilan pill foto di halaman postingan (sudah
  benar, tidak disentuh).
- Tidak ada perubahan pada `FeedTaggedBadge`/sheet-nya sendiri (dipakai
  apa adanya, cuma soal kapan dirender).
