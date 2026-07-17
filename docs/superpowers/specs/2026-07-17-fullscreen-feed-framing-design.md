# Fullscreen Feed Framing Design

## Context

Feed utama dan fullscreen yang dibuka dari halaman Postingan memakai
`FeedVideoPostView`, tetapi mengirim kebijakan framing yang berbeda.

- Feed utama memakai `FeedVideoFraming.mainFeed`, `BoxFit.cover`, dan
  `Alignment.topCenter`.
- Fullscreen dari Postingan tidak mengirim framing, sehingga memakai default
  `FeedVideoFraming.immersive` dengan `BoxFit.fitWidth`.

Pada layar yang lebih tinggi dari media 9:16, mode `fitWidth` meninggalkan
ruang hitam di bawah. Caption, social proof, dan rail kemudian terlihat berada
di panel hitam, berbeda dari Feed utama.

## Goal

Fullscreen dari alur Profile/Postingan harus mempunyai presentasi media yang
sama imersifnya dengan Feed utama:

- video memenuhi viewport dengan `BoxFit.cover`;
- video rata atas;
- tidak ada panel hitam khusus metadata di bawah;
- caption, social proof, rail, progress, dan product overlay tetap berada di
  atas video;
- perbedaan utama dari Feed hanya chrome fullscreen, seperti tombol kembali
  dan tidak adanya bottom navigation.

## Non-goals

Perubahan ini tidak mengubah:

- ownership atau lifecycle `VideoPlayerController`;
- coordinator, preload, autoplay, mute global, dan audio arbiter;
- gesture pause, double-tap like, pinch zoom, edge-swipe back, dan vertical
  paging;
- comment drawer dan compact comment preview;
- halaman Postingan inline;
- layout foto atau carousel;
- data post, produk, like, comment, follow, atau backend.

## Chosen Design

### Framing policy

Tambahkan nilai `fullscreenFeed` pada `FeedVideoFraming`.

| Mode | Media fit | Alignment | Bottom media inset |
| --- | --- | --- | --- |
| `mainFeed` | `BoxFit.cover` | `topCenter` | safe-area/nav geometry Feed |
| `fullscreenFeed` | `BoxFit.cover` | `topCenter` | `0` |
| `immersive` | `BoxFit.fitWidth` | `topCenter` | `0` |

`fullscreenFeed` dibuat terpisah dari `mainFeed` agar aturan bottom navigation
Feed tidak bocor ke route fullscreen.

### Call sites

Kedua jalur `_buildItem` pada `ScopedVideoFeedScreen` harus mengirim
`framing: FeedVideoFraming.fullscreenFeed`:

1. jalur legacy tanpa coordinator;
2. jalur managed dengan coordinator.

Dengan demikian hasil visual tidak berubah berdasarkan cara controller
dimiliki.

### Media rendering

`_MediaBackground` memperlakukan `mainFeed` dan `fullscreenFeed` sebagai
keluarga cover framing untuk video maupun thumbnail. Thumbnail dan player
harus memakai fit serta alignment yang sama agar tidak terjadi lompatan frame
saat controller selesai diinisialisasi.

Perhitungan `mediaBottomInset` tetap khusus `mainFeed`. `fullscreenFeed` tidak
mengurangi tinggi media karena route tersebut tidak memiliki bottom
navigation.

### Comment drawer

Saat comment drawer terbuka, `compactPreview` tetap menggunakan
`BoxFit.contain`. Animasi media mengecil dan membesar tidak mengambil kebijakan
cover fullscreen, sehingga perilaku drawer yang sudah stabil tidak berubah.

## Expected Cropping

Media 9:16 pada perangkat yang lebih tinggi dari 9:16 akan sedikit terpotong
di sisi kiri dan kanan. Ini disengaja agar media memenuhi route tanpa panel
hitam. Alignment tetap `topCenter`, sehingga posisi vertikal tidak bergeser ke
tengah.

## Error and Loading States

Thumbnail, spinner, retry, dan frozen frame tetap memakai alur yang ada.
Perubahan framing tidak boleh membuat controller baru atau mengubah timestamp.

## Tests

Tambahkan atau perluas widget test untuk membuktikan:

1. `fullscreenFeed` merender video dengan `BoxFit.cover` dan
   `Alignment.topCenter`;
2. `fullscreenFeed` tidak mempunyai bottom media inset;
3. thumbnail `fullscreenFeed` memakai kebijakan yang sama dengan video;
4. kedua jalur `ScopedVideoFeedScreen` memilih `fullscreenFeed`;
5. `mainFeed` tetap berhenti di atas bottom navigation;
6. compact comment preview tetap `BoxFit.contain`;
7. mode default `immersive` tetap `BoxFit.fitWidth` untuk consumer lain.

Jalankan focused widget tests untuk `FeedVideoPostView` dan
`ScopedVideoFeedScreen`, lalu `flutter analyze` pada file yang berubah.

## Acceptance Criteria

- Fullscreen yang dibuka dari Postingan tidak lagi mempunyai panel hitam
  metadata di bawah video.
- Media, caption, social proof, rail, progress, dan product overlay membentuk
  satu komposisi imersif seperti Feed utama.
- Fullscreen managed dan legacy mempunyai framing identik.
- Navigasi kembali tetap mengembalikan post dan timestamp yang benar.
- Tidak ada perubahan pada playback ownership, audio, comment drawer, atau
  Feed utama.
