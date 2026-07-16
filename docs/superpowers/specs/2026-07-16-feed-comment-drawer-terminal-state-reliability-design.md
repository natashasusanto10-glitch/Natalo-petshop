# Feed Comment Drawer Terminal-State Reliability Design

**Date:** 2026-07-16
**Scope:** Comment drawer pada Feed untuk video, foto tunggal, dan carousel
**Status:** Approved design

## Relationship to Existing Specifications

Dokumen ini memperketat kontrak gesture dan lifecycle yang sudah ditetapkan di:

- `2026-07-15-comment-drawer-presentation-design.md`;
- `2026-07-16-feed-comment-drawer-parity-design.md`;
- `2026-07-16-feed-photo-comment-drawer-instagram-parity-design.md`.

Keputusan visual, data komentar, initial extent, linked media frame, serta batas
Feed versus halaman Postingan pada dokumen tersebut tetap berlaku. Dokumen ini
menjadi sumber kebenaran untuk terminal state, drag settlement, dan pemulihan
overlay Feed.

## Problem Statement

Comment drawer dapat berhenti sebagai sliver di bagian bawah setelah ditarik
turun. Pada kondisi lain drawer sudah tidak terlihat, tetapi aplikasi masih
menganggapnya terbuka. Akibatnya action rail, top chrome, bottom navigation,
dan vertical Feed paging tetap terkunci, sementara media masih menerima pinch
to zoom.

Ada tiga penyebab yang saling memperkuat:

1. `FeedCommentSheet` mengganti root layout ketika tinggi melintasi 104 logical
   pixels. Struktur normal memakai `Column`, sedangkan struktur ultra-compact
   memakai root `ListView`. Pergantian ini dapat meng-unmount gesture recognizer
   ketika jari masih menekan.
2. Drag dari handle dan drag dari isi komentar memiliki jalur penyelesaian yang
   berbeda. Jalur handle memanggil snap policy aplikasi; jalur internal
   `DraggableScrollableSheet` tidak selalu melakukannya.
3. Pergerakan programatik melalui `DraggableScrollableController.jumpTo()`
   tidak menjalankan snapping bawaan Flutter. Jika recognizer hilang sebelum
   drag-end, extent dapat tertinggal pada nilai arbitrer.

Guard video yang hanya menutup pada extent hampir nol tidak menangkap keadaan
yang berhenti sekitar batas layout 104 pixels. Jalur foto/carousel belum
memiliki terminal-extent guard setara.

## Mature Reels Interaction Contract

Reels dipakai sebagai referensi perilaku, bukan sebagai visual yang disalin.
Drawer hanya mempunyai tiga resting states:

- `closed`: drawer tidak terpasang dan Feed sepenuhnya interaktif;
- `initial`: drawer berhenti pada extent awal `0.60`;
- `expanded`: drawer berhenti pada maksimum yang menghormati top safe area.

`dragging`, `opening`, dan `closing` adalah transient states. Drawer boleh
berada di antara detent hanya selama transisi atau selama pointer masih aktif.
Setelah gesture selesai atau dibatalkan, drawer wajib mencapai salah satu dari
tiga resting states. Tidak ada partial resting state di bawah `initial`.

### Release Policy

- Downward fling atau release pada/bawah dismiss threshold menutup drawer.
- Release di atas dismiss threshold dan di bawah midpoint kembali ke `initial`.
- Upward fling atau release di atas midpoint menuju `expanded`.
- Pointer cancellation memakai policy yang sama dengan release berkecepatan
  nol.
- Gesture dari handle dan gesture dari isi komentar memakai fungsi keputusan
  yang sama.

Drawer tetap mengikuti jari secara kontinu. Penutupan terjadi setelah release,
cancel, atau penyelesaian gesture internal; bukan saat pointer baru melewati
threshold.

## Widget Architecture

### Stable Sheet Shell

`FeedCommentSheet` memakai satu shell stabil untuk seluruh tinggi:

- clip, background, dan drag handle tidak berganti identity;
- drag handle tidak berada di dalam cabang layout yang diganti pada 104 pixels;
- hanya body di bawah handle yang beradaptasi antara normal dan ultra-compact;
- scroll controller yang diberikan `DraggableScrollableSheet` tetap attached
  pada scrollable aktif;
- layout kecil tetap bebas overflow dan composer tetap dapat dijangkau.

Struktur ini menghilangkan unmount recognizer di tengah gesture. Menambahkan
`onVerticalDragCancel` tetap diperlukan sebagai pertahanan untuk cancellation
normal, tetapi bukan satu-satunya mekanisme recovery.

### Shared Settlement Policy

Satu helper/policy murni menentukan target berdasarkan extent, velocity, dan
maximum extent. Adapter foto/carousel dan video wajib memanggil policy yang
sama dari:

- drag-end handle;
- drag-cancel handle;
- penyelesaian drag milik scrollable/list;
- downward fling;
- defensive terminal-extent notification.

Presentation adapter tetap boleh memiliki controller sendiri selama migrasi,
tetapi tidak boleh mendefinisikan threshold atau keputusan settle sendiri.

### Terminal-Extent Guard

Kedua adapter memakai `DraggableScrollableNotification` dengan filter
`depth == 0`. Setelah drawer pernah mencapai visible extent, tercapainya
minimum extent harus meminta close lifecycle tepat satu kali.

Guard ini adalah defense in depth untuk gesture yang dimiliki list, pointer
yang hilang, atau controller yang menyelesaikan snap tanpa callback handle.
Guard tidak boleh menutup drawer selama opening animation melewati extent kecil.

## State Machine and Ownership

State machine Feed drawer adalah:

`closed -> opening -> open/dragging -> closing -> closed`

Aturannya:

- hanya presentation controller yang boleh mengubah phase dan extent;
- hanya satu close transition boleh aktif;
- semua close trigger masuk melalui satu idempotent close request;
- finalizer close boleh dipanggil berulang tanpa efek samping ganda;
- open request selama phase selain `closed` diabaikan;
- controller baru hanya dibuat setelah controller lama benar-benar selesai;
- extent session hanya menyimpan detent valid, bukan partial extent di bawah
  `initial`.

## Atomic Close Finalization

Close dianggap selesai hanya setelah seluruh operasi berikut terjadi sebagai
satu unit logis:

1. extent visual mencapai minimum atau fallback timeout berakhir;
2. drawer subtree di-unmount;
3. overlay/action rail lock dilepas;
4. top chrome dan bottom navigation dipulihkan;
5. vertical Feed paging diaktifkan kembali;
6. Android back closer dilepas;
7. keyboard focus dibersihkan;
8. video hanya dilanjutkan jika sebelumnya dijeda oleh drawer;
9. close completer diselesaikan tepat satu kali.

Adapter foto/carousel memperoleh Android back ownership yang setara dengan
video selama drawer aktif. iOS Feed tetap merupakan root tab; reliabilitasnya
berasal dari terminal-state invariant, bukan route pop yang tidak tersedia.

## Close Watchdog

Setiap close animation memiliki defensive completion berdasarkan durasi
animasi ditambah margin kecil. Jika controller detach atau callback animasi
tidak selesai, finalizer idempotent tetap dijalankan. Watchdog tidak boleh
mempercepat close normal atau memanggil overlay unlock dua kali.

## Media and Overlay Behavior

Linked media geometry yang sudah disetujui tidak berubah:

- media mengikuti top drawer selama opening, dragging, snapping, dan closing;
- foto/carousel tetap `BoxFit.contain` dan mempertahankan slide aktif;
- video mengikuti aturan pause pada maximum extent yang sudah ada;
- post overlay tidak tampil selama drawer secara logis aktif;
- tidak boleh ada keadaan media fullscreen dengan overlay Feed tetap terkunci.

Tap, pinch, caption, commerce, dan rail tidak diubah di luar kebutuhan untuk
memulihkan interaksi setelah drawer benar-benar closed.

## Error and Race Handling

- Controller detach ketika opening melakukan rollback atomik ke `closed`.
- Controller detach ketika closing langsung menjalankan finalizer.
- Drag-end, drag-cancel, min-extent notification, backdrop, dan Android back
  yang terjadi berdekatan hanya menghasilkan satu close transition.
- Keyboard show/hide tidak membuat detent baru atau double inset.
- Route deactivate/dispose membersihkan animation, watchdog, back closer, dan
  overlay lease.
- Reopen setelah recovery selalu dimulai dari `initial`, kecuali session
  menyimpan detent valid `expanded` sesuai kontrak yang sudah ada.

## Required Regression Tests

### Shared Sheet

- Drag handle melewati tinggi 104 pixels tanpa mengganti identity recognizer.
- `gesture.cancel()` menyelesaikan drawer ke target valid.
- Ultra-compact layout tidak overflow dan scroll controller tetap attached.
- Release di setiap sisi threshold menghasilkan `closed`, `initial`, atau
  `expanded`, tidak pernah partial resting extent.

### Photo and Carousel Feed

- Drag handle sampai bawah menutup drawer dan memanggil `onClosed` satu kali.
- Drag dari list/composer sampai minimum juga menutup drawer.
- Setelah close, action rail, top chrome, bottom navigation, dan vertical paging
  kembali aktif.
- Android back menutup drawer sebelum mengubah tab atau keluar aplikasi.
- Close lalu reopen kembali ke extent valid dan mempertahankan slide carousel.

### Video Feed

- Skenario handle, list-origin drag, dan pointer cancel sama dengan foto.
- Overlay lock dan Android back ownership selalu dilepas.
- Video tidak resume sebelum close finalization dan tidak menimpa manual pause.
- Perilaku initial/expanded serta linked media frame tidak mengalami regresi.

### Existing Surfaces

- Seluruh test drawer foto/video yang ada tetap lulus.
- Modal comment drawer halaman Postingan tetap memakai presentation lama dan
  tidak berubah.
- Analyzer untuk file yang disentuh bersih.

## Acceptance Criteria

1. Drawer Feed tidak dapat berhenti sebagai sliver atau invisible-open state.
2. Setelah pointer dilepas atau dibatalkan, extent selalu mencapai resting
   state valid.
3. Foto, carousel, dan video memakai release policy yang sama.
4. Drag dari handle dan drag dari isi komentar menghasilkan perilaku identik.
5. Rail, chrome, navigation, paging, playback lease, dan back ownership selalu
   kembali setelah close.
6. Tidak ada overflow atau flash saat drawer melintasi 104 pixels.
7. Reopen bekerja setelah setiap jalur close atau recovery.
8. Halaman Postingan dan backend komentar tidak berubah.

## Out of Scope

- Mengubah desain visual drawer, warna, typography, reaction bar, atau composer.
- Mengubah initial extent `0.60`, maximum safe-area extent, atau data komentar.
- Mengubah modal comment drawer pada halaman Postingan.
- Refactor umum Feed, media playback, carousel, atau navigation yang tidak
  diperlukan untuk terminal-state reliability.

## Framework References

- Flutter `DraggableScrollableSheet`: programmatic `jumpTo()` dan `animateTo()`
  tidak menerapkan snapping otomatis.
  <https://api.flutter.dev/flutter/widgets/DraggableScrollableSheet/snap.html>
- Flutter `DraggableScrollableNotification`: perubahan extent dapat diamati
  oleh ancestor dan difilter melalui notification depth.
  <https://api.flutter.dev/flutter/widgets/DraggableScrollableNotification-class.html>
