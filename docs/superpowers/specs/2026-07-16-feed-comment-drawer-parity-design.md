# Feed Comment Drawer Parity Design

## Tujuan

Menyamakan presentation dan interaksi comment drawer untuk seluruh media di
Feed: video, foto tunggal, dan carousel. Media di belakang drawer boleh berbeda,
tetapi controller, state machine, transform, snap, scrim, keyboard, dismiss,
dan lifecycle harus sama.

Drawer pada halaman Postingan/detail tetap memakai presentation modal yang
sudah ada dan berada di luar scope perubahan ini.

## Masalah Saat Ini

Video Feed mengelola drawer langsung di `FeedVideoPostView` dengan state machine
lengkap, `DraggableScrollableController`, keyboard inset, drag offset, overlay
lock, dan `_CommentVideoFrame`.

Foto/carousel Feed memakai `FeedReelsCommentSurface`, sebuah state machine
kedua yang memiliki perhitungan transform, min extent, snap sizes, keyboard,
dan lifecycle berbeda. Walaupun konten komentar sama-sama memakai
`FeedCommentSheet`, presentation layer yang berbeda menyebabkan pengalaman
foto/carousel tidak sama dengan video.

## Arsitektur yang Disetujui

Ekstrak presentation drawer Feed menjadi komponen bersama yang memiliki satu
controller dan satu state machine. Komponen ini bertanggung jawab atas:

- fase `closed`, `opening`, `open`, dan `closing`;
- controller dan extent drawer;
- initial, minimum, maksimum, dan snap extent;
- animasi buka/tutup;
- drag pada handle dan list;
- dismiss melalui drag, scrim, tombol close, dan back;
- scrim serta penyerapan pointer saat drawer aktif;
- keyboard inset dan composer;
- session extent serta pemulihan state;
- callback ketika drawer mencapai maksimum;
- transform media berdasarkan extent dan drag offset.

Video, foto, dan carousel memasok renderer media sebagai `child`. Komponen
bersama tidak mengetahui apakah child adalah `VideoPlayer`, foto, atau
`PageView`.

## Perilaku Visual

Saat drawer dibuka dari Feed:

1. Drawer bergerak dari bawah menuju initial extent dengan durasi dan curve yang
   sama untuk semua media.
2. Media mengecil dan terdorong ke atas menggunakan transform yang sama.
3. Scrim meningkat sesuai progress drawer.
4. Drawer dapat ditarik ke maksimum dan kembali ke initial extent.
5. Tarikan ke bawah melewati dismiss threshold menutup drawer.
6. Keyboard menggeser drawer/composer tanpa menghasilkan double inset.
7. Foto/carousel mempertahankan rasio, posisi slide, dan `PageController`.
8. Gesture horizontal carousel tetap berfungsi ketika drawer tertutup; saat
   drawer aktif, gesture vertikal menjadi milik drawer.

Nilai extent, duration, curve, threshold, scale, translate, dan opacity harus
berasal dari konstanta/helper bersama, bukan diduplikasi per jenis media.

## Integrasi Video

Perilaku playback tetap dimiliki `FeedVideoPostView` melalui callback dari
drawer bersama:

- pause saat drawer menutup media pada extent yang ditentukan;
- resume hanya jika video sebelumnya berhak autoplay dan drawer tidak lagi
  menutupnya;
- managed/coordinator dan `VideoAudioClaim` tetap menjadi sumber kebenaran;
- tidak menambahkan pemanggilan `VideoPlayerController.play()` langsung.

Ekstraksi tidak boleh mengubah perilaku audio, route coverage, lifecycle app,
atau transparent bottom sheet yang telah dilindungi tes.

## Integrasi Foto dan Carousel

`_PhotoCarouselPostView` menggunakan komponen drawer bersama yang sama dengan
video. State lokal hanya menyimpan kebutuhan media dan interaksi post; tidak
lagi memiliki implementasi presentation drawer alternatif.

Membuka dan menutup komentar tetap mengatur overlay state milik parent agar
navigasi Feed tidak menangkap swipe vertikal selama drawer aktif.

## Halaman Postingan

`member_post_detail_screen.dart` dan `showFeedCommentDrawer()` tetap memakai
modal drawer halaman Postingan. Komponen modal tersebut tidak dipindahkan ke
state machine Feed dan tidak menerima transform media Feed.

## Pengujian

Regression test harus membuktikan:

- video dan foto memakai presentation drawer bersama;
- initial/max/min extent dan snap target sama;
- transform media pada extent yang sama menghasilkan scale/translate yang sama;
- foto/carousel mengecil dan terdorong ketika drawer naik;
- drag-dismiss, scrim tap, close, dan reopen bekerja;
- keyboard tidak menambah inset dua kali;
- carousel mempertahankan slide aktif;
- video pause/resume tidak mengalami regresi;
- drawer halaman Postingan tetap modal dan tidak berubah.

Tes Feed video yang ada tetap harus lulus. Tes foto drawer diperluas agar
memverifikasi paritas, bukan hanya keberadaan `FeedCommentSheet`.

## Kriteria Selesai

Perbaikan selesai ketika video, foto, dan carousel di Feed menunjukkan perilaku
drawer identik pada skenario yang sama, seluruh tes relevan lulus, analyzer tidak
memiliki error baru, dan tidak ada perubahan presentation pada halaman
Postingan.
