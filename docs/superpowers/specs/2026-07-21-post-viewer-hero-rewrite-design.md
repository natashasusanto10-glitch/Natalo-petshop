# Design — PostViewerRoute: rewrite transisi grid→viewer ke Hero bawaan Flutter

Tanggal: 2026-07-21
Status: Menunggu review user

## Latar belakang

Dua engine transisi custom (`PostPageZoomRoute` di PR #206 dan `OriginExpansionRoute` lama) gagal berulang di device — 5+ ronde fix lolos test + review adversarial tapi gejala device identik: tidak ada efek hero, layar beku/ghost menelan sentuhan, back tidak kembali ke grid, video glitch. Akar kelasnya sama: **sinkronisasi manual** (ukur geometri sendiri, budget waktu, state machine 8-fase, gesture kustom) yang bergantung timing frame device dan tidak tereproduksi di test. Keputusan user: ganti engine ke `Hero` bawaan Flutter — framework yang mengukur dan menerbangkan, kelas bug sinkronisasi hilang, mode gagalnya jinak (fade, bukan beku).

## Keputusan produk (sudah diputuskan user)

- **Cakupan:** SEMUA alur grid→viewer sekaligus: Postingan dari Profil sendiri (`member_screen`), Profil publik (`public_profile_screen`), Postingan Saya (`member_posts_screen`), dan Postingan Tersimpan. `PostPageZoomRoute` dan `OriginExpansionRoute` dihapus. Composer `+` BUKAN alur grid→viewer (tidak ada media bersama yang bisa terbang) — dia pindah ke route fade/slide standar tanpa hero, supaya `OriginExpansionRoute` tetap bisa dihapus total.
- **Rasa transisi:** shared-element ala IG/TikTok — hanya media yang terbang tile↔slot; chrome (header/caption/tombol aksi) fade di posisi final. Sesuai mockup yang disetujui.
- **Tile tak terlihat saat back:** fade halus (tanpa terbang). Grid tetap di-scroll ke posisi post aktif supaya post terlihat setelah back — tapi TANPA menunggu render; kalau tile tidak sempat ada, hero otomatis fade.
- **Branch:** PR #206 ditutup, mulai branch baru bersih dari `main`. Yang berguna (koordinator video, test tertentu) dipetik satu-satu.

## Arsitektur

### 1. `PostViewerRoute` — satu route standar untuk semua origin

`PageRoute` standar (turunan `MaterialPageRoute`/`PageRouteBuilder` dengan transisi fade untuk chrome) — TANPA state machine, TANPA session readiness, TANPA gesture kustom. Barrier/opaque default framework. Semua origin memanggil route yang sama lewat helper bersama (`post_gallery_opener.dart` yang ada dipertahankan sebagai pintu).

### 2. Hero pairing

- **Tile grid** dibungkus `Hero(tag: '<scope>/<postId>')` + `transitionOnUserGestures: true`.
- **Slot media viewer** dibungkus `Hero` dengan tag yang SAMA + `transitionOnUserGestures: true`.
- **Scope tag per permukaan** (WAJIB — tag duplikat membuat hero mati diam-diam tanpa error): `profile/<postId>`, `publicProfile/<userId>/<postId>`, `myPosts/<postId>`, `saved/<postId>`. Viewer menerima scope dari origin pemanggil dan memakainya untuk semua tag hero-nya.
- `flightShuttleBuilder` custom: menerbangkan widget media (foto = gambar ter-cache yang sama; video = `VideoPlayer(controller)` yang sama) dengan `borderRadius` tile yang melebur (lerp) ke radius slot. Konten di-cover-fit selama penerbangan (`fit: BoxFit.cover` dalam `ClipRRect` beranimasi) supaya subjek tidak melar.

### 3. Chrome fade

Halaman viewer dirender penuh di posisi final sejak awal; `FadeTransition` route menganimasi opacity chrome 0→1 mengikuti animasi route. Hero terbang DI ATAS kedua halaman (overlay framework) sehingga media tidak pernah dobel: slot media viewer otomatis dikosongkan framework selama penerbangan (perilaku bawaan Hero).

### 4. Reverse target = post aktif (pengganti `session.freeze()`)

- Viewer melacak post yang sedang tampil (mekanisme visibility yang sudah ada di `member_post_detail_screen` dipertahankan, dipangkas dari urusan readiness).
- Tag `Hero` slot media viewer SELALU mengikuti post aktif — di-update saat post aktif berganti (bukan saat pop). Dengan begitu saat pop dimulai, framework mencari pasangan tag post aktif di grid.
- Saat pop dimulai, origin men-scroll grid ke indeks post aktif (mekanisme `ensureProfileTileVisible` yang sudah ada — minimal-move, jumpTo, tanpa animasi, tanpa menunggu). Kalau tile ter-render → hero terbang pulang. Kalau tidak → framework otomatis fade (tidak ada pasangan tag). Keduanya sah; TIDAK ADA kode yang menunggu/mem-block pop.

### 5. Video

Koordinator video existing (controller tunggal, `ownsController`/`playbackManagedExternally`) dipertahankan apa adanya. Kontrak bebas-glitch tetap: apa yang DIGAMBAR tidak di-gate `playbackAllowed`; surface video tampil selama controller initialized. Shuttle memakai controller yang sama → satu texture sepanjang buka/tutup, tanpa swap thumbnail.

### 6. Gesture back

- iOS: edge-swipe standar `CupertinoRouteTransitionMixin` (didapat gratis dari PageRoute standar). Hero ikut teranimasi karena `transitionOnUserGestures: true` di KEDUA sisi.
- Android: Predictive Back standar framework. Tidak ada `WidgetsBindingObserver` kustom.

### 7. Yang dihapus

- `post_page_zoom_route.dart`, `post_page_zoom_geometry.dart`, `post_page_zoom_transition.dart`, `post_page_zoom_back_gesture.dart`, `post_detail_transition_session.dart`, `profile_post_source_adapter.dart` (+ test-testnya) — seluruh engine PR #206.
- `origin_expansion_route.dart` (+ test) — engine lama.
- Semua channel session di `member_post_detail_screen` (readiness budget, settle, suppression, slot report, controller report) — layar viewer jadi jauh lebih sederhana.
- Yang DIPERTAHANKAN: koordinator video, `ensureProfileTileVisible`, visibility tracker post aktif, `post_gallery_opener.dart` (disesuaikan), layar-layar itu sendiri.

## Mode gagal & mitigasi

| Kondisi | Perilaku | Kenapa aman |
|---|---|---|
| Tile tujuan belum ter-render saat pop | Fade halus otomatis (framework tidak menemukan pasangan tag) | Keputusan produk; tidak ada kode menunggu |
| Tag duplikat (2 permukaan memuat post sama) | Dicegah dengan scope per permukaan | Tanpa scope, hero mati diam-diam |
| Gesture back iOS | `transitionOnUserGestures: true` dua sisi | Default `false` = fade polos saat swipe |
| Video mid-flight | Controller sama di shuttle | Satu texture, tanpa thumbnail swap |
| Reduced motion (a11y) | `Hero` mengikuti durasi route; route memakai durasi/kurva standar — bila `disableAnimations`, framework memangkas sendiri | Tidak butuh branch khusus |

## Non-tujuan

- TIDAK menyentuh transisi feed utama, Detail Produk, atau fullscreen video (route lain).
- TIDak mengubah tata letak halaman viewer/grid — murni transisi.
- TIDAK ada preload/prefetch baru.

## Testing

TDD (RED→GREEN) per unit:
1. Tag hero terpasang benar + ter-scope di keempat origin grid (widget test per origin); composer `+` terbuka via route fade standar tanpa hero.
2. `transitionOnUserGestures: true` di kedua sisi (assert properti).
3. Tag viewer mengikuti post aktif saat scroll antar post (retarget sebelum pop).
4. Pop dengan tile ter-render → hero flight terjadi (frame tengah: ada widget shuttle); pop dengan tile absen → fade tanpa error.
5. Video: controller yang sama dipakai tile → shuttle → slot (same-instance assertion, pola test regresi video yang sudah ada).
6. Grid di-scroll ke post aktif saat pop (reuse test `ensureProfileTileVisible`).
7. Regresi: suite `test/screens/` + `test/features/feed/` hijau; goldens di-regenerate untuk halaman yang berubah.

Verifikasi akhir: `flutter analyze` bersih, `dart format`, `git diff --check`, lalu device-verify iOS + Android (checklist: buka hero dari keempat origin grid, back ke tile A dan ke tile B jauh, swipe-back iOS, Predictive Back Android, post video buka/tutup, Postingan Tersimpan, composer fade).

## Risiko yang diterima secara sadar

- Rasa penerbangan hero bawaan (kurva `Hero.createRectTween` default / `MaterialRectArcTween`) mungkin butuh tuning kecil supaya senyaman IG — itu polish visual, bukan risiko beku.
- Sebagian besar kode PR #206 (±14 ribu baris) dibuang — sunk cost yang disadari; pelajaran teknisnya terdokumentasi di memory proyek.
