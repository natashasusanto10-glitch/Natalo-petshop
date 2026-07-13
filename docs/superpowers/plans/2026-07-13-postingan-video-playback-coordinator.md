# Plan — Postingan Video Playback Coordinator ("C-lite")

**Tanggal:** 2026-07-13
**Branch:** `claude/postingan-video-coordinator`
**Status:** Spesifikasi disetujui user (kontrak ownership dikunci); menunggu greenlight eksekusi.

## 1. Masalah (laporan user + audit)

Halaman **Postingan** (`flutter_app/lib/screens/member_post_detail_screen.dart`) — 4 keluhan user:

1. **Mute desync** — mute di Postingan tapi suara tetap keluar di Feed. `appSettingsStore.feedMuted` ditulis, tapi tidak ada listener yang re-apply volume ke controller yang sudah hidup. Fullscreen overlay hardcode `setVolume(1)` dan toggle mute-nya lokal.
2. **Audio hantu** — suara tiba-tiba terputar dari video lain di belakang. `_InlineVideoPlayer` (:2058-2297) hanya pakai `VisibilityDetector`, tanpa `RouteAware`/`WidgetsBindingObserver` (Feed sudah dapat fix ini di commit 86792b6e; Postingan belum).
3. **Grid → play harus instan** — KEPUTUSAN USER: autoplay TETAP (seperti IG), targetnya instan & bebas error. Grid sudah thumbnail-murni; tap pertama dari grid boleh loading (wajar, IG juga).
4. **Tap kedua → fullscreen lagging/buffering** — `_openScopedVideoFeed` (:604-674) membuang controller ter-buffer; `ScopedVideoFeedScreen` (scoped_video_feed_screen.dart:86-96) selalu kirim `preloadedController: null` → re-init + re-download dari nol.

Audit tambahan (semua terverifikasi ke kode):

- **A1 — Gate `_isPaused` salah kaprah:** video yang selesai init saat `isActive: false` di-set `_isPaused = !isPlaying` = true (feed_video_post_view.dart:548); saat jadi aktif, gate `!_isPaused` (:411) menolak play → video diam padahal user tidak pernah pause.
- **A2 — Inline Postingan tak cek setting/lifecycle:** hanya visibilitas ≥60% (:2086); abaikan feedAutoplay/data saver/background.
- **A3 — HLS lewat cache wrapper:** member_post_detail selalu `CachedVideoPlayerPlus` (:2031); feed utama sengaja skip wrapper untuk `.m3u8` (feed_video_post_view.dart:467-469). Kemungkinan akar "Video belum bisa diputar" (:2059) — dan error itu permanen tanpa retry.
- **A4 — Dobel inisialisasi:** `_maybeInitVideo` (:456) tanpa guard in-flight; tap saat loading bisa panggil lagi dari :1128 → dua controller / resource bocor.
- **A5 — Preload Feed utama kehilangan ownership:** controller diambil dari map via `remove()` di `build()` (feed_screen.dart:642); kalau parent rebuild tapi widget ber-key sama tetap hidup, controller baru terhapus dari map tanpa pernah diadopsi → controller yatim (tak pernah di-dispose, kandidat audio hantu).

## 2. Desain — Opsi C "C-lite": Playback Coordinator lokal

Ownership controller **tidak pernah berpindah**. Yang berpindah hanya tampilan aktif.

```
PostVideoCoordinator (milik MemberPostDetailScreen)
       │
       ├── owns SEMUA controller (satu-satunya pemanggil dispose)
       │
       ├── Inline view  : attached / dormant
       └── Fullscreen view (ScopedVideoFeedScreen → FeedVideoPostView)
                        : attached / detached
```

Scope: **lokal alur Postingan → fullscreen saja.** Feed utama TIDAK dimigrasi — hanya bug A5-nya diperbaiki di tempat. Coordinator ini jadi cetak biru kalau nanti Feed utama mau disatukan (bertahap, bukan sekarang).

### 2.1 Dua kontrak terpisah di FeedVideoPostView (KUNCI USER)

`ownsController: false` saja TIDAK cukup — itu cuma mencegah dispose, sementara widget masih bisa play/pause/seek/setVolume dari VisibilityDetector atau lifecycle internal. Dua flag:

- `ownsController` — siapa yang boleh **dispose**.
- `playbackManagedExternally` — siapa yang boleh **play/pause/seek/setVolume**.

Controller dari coordinator → `ownsController: false, playbackManagedExternally: true`. View hanya melaporkan intent (visible/hidden, user tap pause, route pushed/popped) ke coordinator; coordinator yang mengeksekusi. Default keduanya (jalur lama, fullscreen dibuka dari tempat lain tanpa Postingan): `ownsController: true, playbackManagedExternally: false` — perilaku sekarang, TIDAK berubah.

### 2.2 Aturan mute (KUNCI USER)

- Controller **aktif** mengikuti `feedMuted`: volume 0 atau 1.
- Semua controller **inactive/preload**: SELALU `paused + volume 0`.
- Preload → aktif: coordinator baru menerapkan nilai `feedMuted` saat itu.
- **Unmute global TIDAK boleh** membuat controller background naik ke volume 1.

Listener `feedMuted` hidup di coordinator (satu tempat). Toggle mute fullscreen menulis ke `appSettingsStore.setFeedMuted` (hapus state lokal + hardcode volume 1).

### 2.3 Slot controller: maks 3, eksplisit (KUNCI USER)

1. Controller **video asal** (untuk kembali ke Postingan).
2. Controller **video fullscreen aktif**.
3. Controller **satu video berikutnya** (preload: paused + muted).

Video asal sedang aktif → slot 1 dan 2 = controller sama. Swipe berkali-kali: controller yang bukan asal, bukan aktif, bukan next-preload → **langsung dieviction LRU**.

### 2.4 Pinned vs attached (KUNCI USER)

Refcount attachment TIDAK boleh langsung membuang controller saat sementara 0 di tengah transisi. Konsep `pinned`:

- Video asal **pinned** selama fullscreen terbuka.
- Video aktif **pinned**.
- Next preload **pinned** sampai window berubah.
- Attachment count hanya menandai "ada view yang sedang merender".
- **Dispose HANYA jika: tidak attached + tidak pinned + keluar window LRU.** Dan hanya coordinator yang memanggilnya.

### 2.5 Lifecycle (KUNCI USER)

- `MemberPostDetailScreen` **membuat dan men-dispose** coordinator.
- Halaman meneruskan event background/foreground + route visibility (RouteAware + WidgetsBindingObserver terdaftar SEKALI di level halaman, bukan per-item).
- Fullscreen melaporkan item aktif + route visibility ke coordinator.
- Inline dan fullscreen DILARANG mendaftarkan lifecycle observer untuk controller yang sama secara terpisah.
- Background / route tertutup → coordinator pause semua miliknya (menutup audio hantu #2).

### 2.6 Alur handoff

1. Inline play di Postingan (controller milik coordinator, inline attached).
2. Tap → fullscreen: inline jadi **dormant** (lepas tampilan + berhenti lapor visibilitas; tampilkan frozen frame/thumbnail), fullscreen attach ke **controller yang sama** → tanpa inisialisasi ulang → **instan**.
3. Swipe di fullscreen: video asal di-pause tapi tetap pinned; next video pakai slot preload (kalau sudah siap → cepat; belum → loading singkat, wajar).
4. Fullscreen ditutup: fullscreen detach; inline yang masih hidup re-attach controller yang sama di timestamp terakhir. Inline sudah keluar viewport/dispose → coordinator yang memutuskan nasib controller (aturan 2.4).

## 3. Acceptance criteria (verbatim dari user)

- Masuk fullscreen **instan** — tanpa buffering ulang pada tap kedua.
- Kembali ke Postingan **melanjutkan timestamp yang sama**.
- Re-attach boleh loading sangat singkat; inline menampilkan frozen frame/thumbnail selama itu.
- **Nol** audio hantu, **nol** double controller, **nol** double-dispose.
- Tap pertama dari grid boleh loading (grid tetap thumbnail murni — sesuai IG).
- Mute/unmute di mana pun langsung konsisten di semua permukaan; unmute tidak membocorkan audio background.
- Video swipe-berikutnya tidak lagi "stuck diam" (gate A1 fix).
- "Video belum bisa diputar" tidak lagi permanen (HLS fix + retry).

## 4. Task breakdown

### T1 — PostVideoCoordinator core + unit test
File baru: `flutter_app/lib/features/feed/video/post_video_coordinator.dart`.
Kelas murni-logika (inject factory pembuat controller biar bisa dites tanpa plugin): slot/pinned/LRU (§2.3–2.4), attach/detach + refcount, mute rules (§2.2) dengan listener `feedMuted`, API intent (reportVisible/reportHidden/userTogglePlay/setActive/preloadNext), pause-all untuk lifecycle. Unit test per aturan: eviction, pinned melindungi saat attachment 0, unmute tak menyentuh background, dispose tunggal.

### T2 — Kontrak FeedVideoPostView: `ownsController` + `playbackManagedExternally` (+ fix A1, A4)
`feed_video_post_view.dart`:
- Tambah dua flag (§2.1), default perilaku lama.
- `playbackManagedExternally: true` → VisibilityDetector/lifecycle/tap-pause jadi *laporan* ke callback coordinator, bukan panggilan langsung ke controller; dispose dilewati bila `ownsController: false`.
- **Fix A1:** `_isPaused` hanya boleh true dari aksi user eksplisit — jangan diturunkan dari `!isPlaying` pasca-init (:548); gate :411 pakai sumber yang benar.
- **Fix A4:** guard in-flight di `_maybeInitVideo` (flag `_initInFlight`, panggilan kedua no-op / menunggu).
Widget test regresi: init-saat-inactive lalu jadi aktif → play; tap ganda saat loading → satu controller.

### T3 — Integrasi Postingan: inline dormant + fullscreen borrow
- `member_post_detail_screen.dart`: `_InlineVideoPlayer` pindah ke controller pinjaman dari coordinator; mode dormant (frozen frame) saat fullscreen buka; lifecycle level-halaman (§2.5); `_openScopedVideoFeed` mengoper coordinator + id video asal; hapus `_FullscreenInlineVideoOverlay` (dead code) sekalian.
- `scoped_video_feed_screen.dart`: terima coordinator opsional; item = video asal → attach controller coordinator (`ownsController:false, playbackManagedExternally:true`); item lain → cek slot preload; tanpa coordinator → fallback perilaku sekarang.
- Preload next-1 (paused+muted) dikelola coordinator saat fullscreen aktif.

### T4 — HLS tanpa cache wrapper + auto-retry di Postingan (fix A3 + error permanen)
`member_post_detail_screen.dart` `_initialize()`: URL `.m3u8` → `VideoPlayerController.networkUrl` langsung (samakan pola feed_video_post_view :467-469), MP4 tetap cached. Auto-retry 1–2× backoff sebelum menyerah ke "Video belum bisa diputar" + tombol coba-lagi tetap. (Setelah T3, init ini hidup di coordinator — T4 dikerjakan di jalur init final.)

### T5 — Fix A5: ownership preload di Feed utama (terpisah, di tempat)
`feed_screen.dart` (:641-646): jangan `remove()` dari map di `build()`. Handoff harus terkonfirmasi: konsumsi map saat state penerima benar-benar mengadopsi (callback/claim eksplisit), atau key-kan sehingga rebuild tak menjatuhkan controller; controller tak teradopsi wajib di-dispose oleh pemilik map. TIDAK migrasi ke coordinator.

### T6 — Regression + analyze
`flutter analyze` bersih + seluruh suite test (target: semua hijau, ±202+ test). Gotcha test: jangan `pumpAndSettle` dengan shimmer — bounded pump loop + `SharedPreferences.setMockInitialValues`.

Urutan: T1 → T2 → T3 → T4 (T5 paralel kapan saja) → T6.

## 5. Out of scope

- Migrasi Feed utama ke coordinator (hanya fix A5 di tempat).
- Perubahan visual/desain apa pun.
- Perubahan perilaku autoplay (tetap autoplay ala IG — keputusan user).
- Perbaikan `feedAutoplay`/data-saver di luar jalur yang lewat coordinator (A2 tercakup sebatas lifecycle+mute; setting autoplay Postingan mengikuti perilaku sekarang).

## 6. Verifikasi device (wajib sebelum rilis)

Android + iOS: mute di Postingan → buka Feed (senyap); buka post video → home/lock (senyap); tap video → fullscreen (instan, lanjut posisi); swipe 3–4 video di fullscreen lalu kembali (timestamp lanjut, tanpa layar hitam); matikan WiFi lalu buka post video (retry → error ramah, tidak permanen setelah WiFi nyala + coba lagi); video HLS di Postingan (tidak "Video belum bisa diputar").
