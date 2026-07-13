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

### T7 — Scoped fullscreen FULL-managed + preload next (mengganti pendekatan bertahap T3b)
Disetujui user 2026-07-13. Menggantikan T3b "hanya origin managed" → **SELURUH item scoped fullscreen managed saat coordinator ada** (ownership seragam, statis per item — hilangkan flip own-controller↔managed yang jadi sumber controller-ganda/audio-hantu).

Prinsip: **ownership seragam (semua managed), kepemilikan SESI on-demand.**
- Managed view mengadopsi sesi HANYA jika coordinator sudah punya sesi utk postId-nya (origin/active/hasil preloadNext). Belum ada → render thumbnail/frozen, TIDAK bikin controller.
- **KUNCI 1 (registry notifier):** managed view yang belum punya sesi harus TAHU saat coordinator kemudian membuat sesi utk postId-nya. Tak cukup cek `sessionFor` sekali di build. Coordinator WAJIB expose notifier — `Listenable` yang fire saat map sesi berubah, atau revision per-postId. View listen → re-cek `sessionFor(postId)` → adopt saat muncul. Ini yang bikin swipe-ke-preload instan (widget sudah mounted, adopt begitu sesi preload lahir).
- **KUNCI 2 (semua inactive detach, TERMASUK origin):** view yang jadi inactive WAJIB detach. Sesi origin tetap hidup karena `pinned`, BUKAN karena attachment. Ini menjaga makna "attached" jujur + cegah sesi transient ke-4 menetap saat 3 widget PageView mounted.
- **Urutan transisi halaman DETERMINISTIK** (onPageChanged): (1) pause+mute active lama; (2) buat/promosikan sesi halaman baru jadi active; (3) managed view halaman baru adopt sesi via notifier; (4) detach view lama; (5) tentukan+preloadNext (KECUALI Data Saver); (6) evict sesi yang bukan origin/active/next.
- **Data Saver:** semua tetap managed, `preloadNext` DILEWATI; swipe → coordinator baru bikin sesi utk item aktif saat itu (satu controller, loading singkat boleh). Menuntaskan D2.
- Maks 3 sesi logis: origin(A,pinned) + active(B) + next(C). Item bukan-role → dieviksi LRU.
- Fallback: `coordinator == null` (Postingan Terkait detail produk, deep link) → semua own-controller, TAK berubah.

### T8 — Retry di fullscreen (session revision + re-adopt)
Managed view mendengarkan SESI (bukan snapshot controller di initState). `VideoPlayerSession` naikkan `revision` setiap controller dibuat/diganti/gagal/sukses-retry. Revision berubah → view lepas listener controller lama + adopt controller baru. Tombol "Coba lagi" di managed view saat `hasError` → `session.retry()`; selama retry tampil thumbnail/frozen+loading; sukses → controller baru langsung dirender, coordinator terapkan active/mute. View TAK PERNAH dispose (ownership tetap coordinator). Sekaligus menutup risiko sisa T3b (controller null saat buka fullscreen → thumbnail diam).

**Acceptance T7+T8 (verbatim user):** tak ada 2 controller utk postId sama; swipe A→B pakai controller B ter-preload; maks 3 sesi hidup setelah swipe berkali-kali; Data Saver tak preload; error fullscreen punya "Coba lagi"; retry sukses tanpa kembali ke Postingan; controller hasil retry langsung terpasang ke managed view; mute konsisten tanpa audio background; kembali ke Postingan lanjut video A di timestamp terakhir.

## 4b. Refinement acceptance (user, 2026-07-13) — 12 poin + 5 delta

12 poin acceptance user memetakan ke task: (1) mute global→T2/T3+**D1**, (2) audio hantu→T3, (3) flow IG→T3, (4) handoff→T3, (5) coordinator lokal→T1/T3, (6) preload next→T3+**D2**, (7) fix autoplay macet→T2+**D3**, (8) cegah dobel init→T2, (9) HLS→T4+**D4**, (10) fix preload feed→T5, (11) lifecycle/ownership→T3+**D5**, (12) uji Android+iOS→§6.

Lima delta yang MEMPERLUAS scope dari plan awal:

- **D1 (poin 1) — Mute live di Feed utama juga.** Coordinator hanya Postingan-scoped; controller Feed utama TIDAK dikelolanya. Feed utama sekarang baca `feedMuted` cuma saat init/adopt (feed_video_post_view :544 dll), jadi mute dari layar lain tak berlaku ke controller feed yang sudah hidup. Fix: pasang listener `feedMuted` ringan di jalur Feed utama yang re-apply volume HANYA ke controller AKTIF feed (aturan sama §2.2: aktif ikut feedMuted, non-aktif tetap 0). Masuk **T5** (sudah menyentuh feed_screen). Verifikasi: mute di Postingan → Feed utama ikut senyap seketika (dan sebaliknya).
- **D2 (poin 6) — Data saver menonaktifkan preload.** `coordinator.preloadNext` di-skip saat `appSettingsStore.feedVideoQuality == 'data_saver'` (atau flag data-saver setara). Masuk **T3** (caller preloadNext cek setting sebelum panggil). Preload yang sudah terlanjur dibuang aman via LRU.
- **D3 (poin 7) — Autoplay OFF dihormati di Postingan.** `_InlineVideoPlayer` sekarang autoplay murni dari visibilitas ≥60% tanpa cek `feedAutoplay`. Fix: hormati `appSettingsStore.feedAutoplay` (kalau OFF → tampilkan thumbnail + tombol play, tidak auto-main; tetap boleh play saat user tap). Masuk **T3**. CATATAN: default autoplay ON = perilaku IG tetap; ini hanya menutup kebocoran saat user mematikan setting. (Menggeser A2 dari out-of-scope jadi IN-scope sebatas ini.)
- **D4 (poin 9) — Refresh signed URL expired.** Signed URL Bunny (`token=&expires=`) TIDAK bisa di-rewrite (video_quality_service :147); tidak ada refresh klien saat ini. Fix best-effort: pada error init yang teridentifikasi 403/expired, re-fetch URL video post dari API (kalau endpoint detail post mengembalikan URL bertanda-tangan segar) SEKALI, lalu retry; kalau tak ada endpoint/refresh gagal → jatuh ke tombol "Coba lagi". Masuk **T4**. Kalau ternyata endpoint refresh belum ada → dokumentasikan sebagai follow-up, JANGAN bikin backend baru di task ini.
- **D5 (poin 11) — Buka fullscreen internal TIDAK boleh mem-pause controller handoff.** `FeedVideoPostView` `didPushNext` (RouteAware) mem-pause saat route opaque didorong. Untuk controller pinjaman (`playbackManagedExternally: true`), pause itu HARUS jadi laporan ke coordinator — dan karena fullscreen = active baru pakai controller SAMA, coordinator tak mem-pause-nya. Kontrak dua-flag §2.1 sudah menutup ini; T3 wajib memverifikasi urutan: fullscreen attach ke controller asal SEBELUM inline dormant, dan tutup: fullscreen detach → inline re-attach (§2.6). Uji khusus: buka fullscreen tidak menimbulkan jeda/pause pada frame handoff.

## 4c. Deferred secara sadar (whole-branch review 2026-07-13)

- **Preload next-1 / D2 TIDAK di-wire (PARSIAL).** `coordinator.preloadNext` + slot-3 + skip-data-saver ADA & ter-unit-test di core, tapi tak dipanggil integrasi (T3b hanya me-manage item ORIGIN; sibling own-controller). Konsekuensi: swipe-ke-next di fullscreen tetap init own-controller (loading singkat). Acceptance §2.6 mengizinkan ini ("loading singkat, wajar"), jadi DITERIMA sebagai deferred — poin acceptance 6 (preload) & D2 belum fungsional. Follow-up bila device-verify menunjukkan swipe terlalu lambat: wire preloadNext dgn hati-hati agar tak dobel controller video sibling.
- **Error origin saat DI fullscreen = dead-end (RENDAH).** Tombol "Coba lagi" hanya di `_InlineVideoPlayer` (Postingan). Kalau origin error saat di fullscreen (managed view, controller null), user lihat thumbnail diam tanpa retry; `_adoptPreloadedController` jalan sekali di initState tanpa re-adopt di didUpdateWidget, jadi walau auto-retry sesi sukses fullscreen tak memungut controller baru. RENDAH: origin hampir selalu sudah play inline sebelum tap; user bisa back ke inline (ada retry). Follow-up/device-verify.

## 5. Out of scope

- Migrasi Feed utama ke coordinator (hanya fix A5 + D1 mute-live di tempat).
- Perubahan visual/desain apa pun.
- Perubahan perilaku autoplay default (tetap autoplay ON ala IG; D3 hanya menghormati saat user OFF-kan).
- Membuat endpoint/backend baru untuk refresh signed URL (D4 best-effort pakai yang ada; kalau tak ada → follow-up).

## 6. Verifikasi device (wajib sebelum rilis)

Android + iOS: mute di Postingan → buka Feed (senyap); buka post video → home/lock (senyap); tap video → fullscreen (instan, lanjut posisi); swipe 3–4 video di fullscreen lalu kembali (timestamp lanjut, tanpa layar hitam); matikan WiFi lalu buka post video (retry → error ramah, tidak permanen setelah WiFi nyala + coba lagi); video HLS di Postingan (tidak "Video belum bisa diputar").
