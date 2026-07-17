# Migrasi Feed utama ke PostVideoCoordinator (Opsi D)

**Tanggal:** 2026-07-17
**Status:** DESAIN — belum ada kode ditulis, menunggu greenlight terpisah untuk eksekusi.
**File terdampak (nanti):** `flutter_app/lib/screens/feed_screen.dart` (2416 baris, migrasi utama) + `flutter_app/lib/features/feed/video/post_video_coordinator.dart` (tambah `clearActive()`) + `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` (lengkapi intent gesture managed long-press, bukan rombak struktur).

## Masalah

Ada dua jalur kepemilikan controller video yang hidup berdampingan:

| | Feed utama (`feed_screen.dart`) | Postingan/fullscreen (`member_post_detail_screen`, `scoped_video_feed_screen`) |
|---|---|---|
| Pemilik controller | **Legacy** — `FeedVideoPostView` bikin & pegang controller sendiri; preload via `Map<String,VideoPlayerController>` manual di `feed_screen` | **Managed** — `PostVideoCoordinator` (instance baru per screen) satu-satunya pemilik; view pinjam via `ownsController:false, playbackManagedExternally:true, coordinator:` |
| Refresh signed-URL saat init gagal | Ditambal manual (PR #140 — port "D4") | Bawaan sejak T4 |
| Retry/error surface | Custom (`_videoLoadFailed`, `_maybeInitVideo`, `_runInitVideo`) | `VideoPlayerSession.retry()` (T8) |
| Mute/volume live | `_onFeedMutedChangedLive` sendiri | `_onMutedChanged` di coordinator |
| Route-cover / audio-hantu guard | `_routeCovered`/`_appBackgrounded`/`_canAutoplayNow` sendiri | Built-in |

**Pola yang berulang:** tiap kali ditemukan bug kelas ini di jalur legacy (race Feed→Profile, video gagal diputar tak bisa pulih, dll), solusinya **sudah ada** di coordinator — kita hanya menambalnya satu per satu ke legacy supaya menyusul. Ini duplikasi logika permanen: dua implementasi paralel yang harus tetap identik perilakunya, dikerjakan dan direview dua kali setiap kali ada bug kelas baru.

Opsi D = pindahkan `feed_screen.dart` supaya juga pakai `PostVideoCoordinator`, sehingga hanya ada **satu** mesin pemilik-controller di seluruh app.

## Inventarisasi kondisi nyata (diverifikasi 2026-07-17, bukan dari ingatan)

Sebelum menilai risiko, berikut fakta yang diperiksa langsung ke kode saat ini (`origin/main` di `f6f90387`+):

1. **`feed_screen.dart` 100% legacy** — nol referensi `coordinator:`/`playbackManagedExternally`/`ownsController` di instansiasi `FeedVideoPostView`.
2. **`FeedVideoPostView` SUDAH dual-mode.** Widget yang sama dipakai di feed (legacy) dan Postingan/fullscreen (managed) — parameter `ownsController`, `playbackManagedExternally`, `coordinator` sudah ada di constructor sejak T2. **Migrasi tidak perlu menyentuh widget ini** — hanya bagaimana `feed_screen.dart` menginstansiasinya dan mengelola lifecycle-nya.
3. **Jendela preload SUDAH dibagi antara legacy dan managed** (temuan paling penting, mengubah kalkulasi risiko dari diskusi sebelumnya):
   - `AdaptiveVideoPreloadPolicy.offsets(...)` (`adaptive_video_preload_policy.dart`) adalah objek **tunggal, sudah dipakai KEDUANYA**: `feed_screen._managePreloadWindow` (legacy) DAN `scoped_video_feed_screen` (managed, fullscreen).
   - `PostVideoCoordinator.setPreloadWindow(Iterable<String>)` **sudah** mendukung jendela multi-item (bukan cuma "next" tunggal seperti asumsi lama) — capped `maxPreloadSessions = 3`, dipanggil persis dengan output `adaptiveVideoPreloadPolicy.offsets(...)` di `scoped_video_feed_screen.dart:453-468`.
   - Artinya: **semantik jendela preload feed (forward 2 + backward 1, network/data-saver-aware) sudah punya implementasi coordinator yang terbukti jalan** di fullscreen. Migrasi bukan "rancang ulang windowing", tapi "port pemanggilan yang sudah ada".
4. **`SocialVideoSessionObserver` bukan milik jalur legacy.** `VideoPlayerSession` (kelas sesi milik coordinator) sudah memanggil `_observe(...)` sendiri di titik lifecycle-nya (init/attach/dispose) — observer sudah "paham" sesi coordinator. Observasi **tidak hilang** saat migrasi; hook `observeFeedControllerDisposed` dkk. di `feed_video_post_view.dart` yang ditemukan sebelumnya khusus untuk bookkeeping jalur **legacy lokal** (`_localInitController`) — akan otomatis tak terpakai (dan bisa dihapus) begitu feed pindah ke managed.
5. **`VideoAudioArbiter` sudah menjembatani KEDUA jalur** — dipakai di `feed_video_post_view.dart` (baris ~628, legacy claim) DAN `post_video_coordinator.dart` (managed claim). Motivasi "audio hantu lintas-jalur" untuk migrasi **sudah tertutup lewat arbiter**, bukan alasan mendesak lagi.
6. **`PostVideoWarmHandoff`** (one-shot ownership transfer profile-grid→post-detail) **ortogonal** — dipakai `member_posts_screen`, `member_screen`, `public_profile_screen`, TIDAK oleh `feed_screen`. Tak ada interaksi yang perlu didesain.
7. **Feed dan Postingan TIDAK saling navigasi hari ini** — tap video di Feed tidak membuka `member_post_detail_screen` (Postingan dibuka dari Profile/"Postingan Saya", bukan dari Feed). `member_post_detail_screen` bikin `PostVideoCoordinator` baru per instance screen (baris 196). **Migrasi Feed tidak butuh desain handoff lintas-screen** — cukup beri `feed_screen` coordinator instance-nya sendiri, pola identik dengan yang sudah dipakai `member_post_detail_screen`.
8. **Feed = PageView CAMPURAN** (video + foto/carousel), beda dari `scoped_video_feed_screen` yang video-only. Coordinator hanya perlu tahu post video (`kind` video); post foto tetap di luar coordinator sepenuhnya (sama seperti sekarang — legacy juga sudah harus memfilter `_visiblePosts` untuk video-only saat preload).
9. **`attach()` HANYA untuk item aktif, BUKAN untuk seluruh jendela preload.** Diverifikasi persis dari `scoped_video_feed_screen._activateManaged` (`scoped_video_feed_screen.dart:414-448`): `coord.attach(...)` dipanggil SATU KALI untuk `postId` yang baru jadi aktif; item di jendela preload (`setPreloadWindow`) HANYA dapat sesi paused+muted+pinned — **tidak pernah** masuk `attachedViewIds`. Attach = "view ini sedang merender & boleh klaim audio/pin lebih kuat"; pinned-tanpa-attach = "sesi hidup untuk instant-play nanti, tapi bukan view aktif". Koreksi atas kalimat Lingkup poin 5 di bawah, yang sebelumnya berbunyi ambigu.
10. **Tidak ada `clearActive()` di coordinator saat ini.** `setActive(String postId)` (`post_video_coordinator.dart:215`) mewajibkan ID non-null. Karena Feed campur video+foto, begitu item aktif PageView berpindah ke post **foto**, tak ada cara memberi tahu coordinator "tak ada video aktif sekarang" — risiko video sebelumnya tertinggal "aktif" (berpotensi bersuara) di belakang post foto. **Gap nyata yang harus ditutup SEBELUM swap widget (Lingkup #1 baru).**
11. **Gesture long-press (peek-pause + 2x-speed-hold) SEPENUHNYA nonaktif di mode managed.** `_onLongPressStart`/`_onLongPressEnd` (`feed_video_post_view.dart:2845,2884`) early-return kalau `_managed` — keputusan T2 yang disengaja demi keamanan Postingan (`ctrl.play/pause/setSpeed` langsung berisiko race). Tapi ini "Sprint 4 #1 signature gesture" Feed yang dipakai user hari ini. Kalau Feed migrasi apa adanya, **fitur ini hilang diam-diam**. Scrubber sudah aman (`managed:` param sudah ada → seek-only). Long-press BELUM punya jalur intent managed — harus dilengkapi SEBELUM swap, bukan sesudah.
12. **Ada telemetry collision yang sudah terinstrumentasi produksi.** `SocialVideoCollisionMetricSink` (`social_video_observation_metrics.dart`) mengirim event analytics `social_video_controller_collision` (media_key + controller_count + surface_names) tiap observer deteksi >1 controller hidup untuk media yang sama lintas surface. Ini bisa dipakai sebagai **gerbang rollout data-driven** (bukan cuma manual QA) untuk menaikkan flag default.

**Kesimpulan inventarisasi:** cakupan migrasi jauh lebih sempit dari perkiraan awal. `scoped_video_feed_screen.dart` adalah **preseden struktural yang nyaris identik** — PageView video dengan preload adaptif dikelola coordinator — dan sudah terbukti jalan (lolos T7 review + device-considerations). Migrasi Feed pada dasarnya **mem-port pola yang sudah ada**, diperkecil scope ke satu file (`feed_screen.dart`), bukan merancang mekanisme baru. Tapi ada **dua gap konkret** (poin 10, 11) yang harus ditutup lebih dulu sebagai pekerjaan berdiri sendiri — bukan diselesaikan sambil lalu di tengah swap widget.

## Opsi yang dipertimbangkan (rekap keputusan sebelumnya)

Dibahas 2026-07-17 sebelum doc ini: Opsi A (tambal per-bug, sudah beberapa kali dijalankan: D4/#140, route-cover, dll), Opsi B (unifikasi partial), Opsi C (biarkan dua jalur, terima duplikasi permanen), **Opsi D (migrasi penuh, dokumen ini)**.

Keputusan: **Opsi D adalah arah jangka panjang yang benar**, tapi bukan patch — perlu direncanakan sebelum dieksekusi karena Feed adalah **permukaan tersibuk di app**. Dokumen ini adalah perencanaan itu. Kapan dieksekusi menunggu keputusan terpisah (lihat Non-goals).

## Rancangan migrasi

### Lingkup

Ubah `feed_screen.dart` + `post_video_coordinator.dart` + `feed_video_post_view.dart` (gesture-intent saja) agar:
1. **[PRASYARAT]** Tambah `clearActive()` di `PostVideoCoordinator` — pause+mute sesi aktif (kalau ada) tanpa membuat sesi baru, `_activePostId = null`. Dipanggil saat item PageView aktif adalah post **foto** (bukan video).
2. **[PRASYARAT]** Lengkapi jalur intent gesture managed untuk long-press peek-pause + 2x-speed-hold — ganti panggilan `ctrl.pause()/setPlaybackSpeed()` langsung dengan intent lewat coordinator (pola sama seperti scrubber `managed:` param), supaya perilaku Sprint 4 #1 tidak hilang saat migrasi.
3. Punya satu `PostVideoCoordinator` instance per screen-lifetime, **di balik feature flag yang DIKUNCI sejak `initState`** (dibaca sekali, tak reaktif — hindari state coordinator setengah-matang akibat toggle di tengah lifecycle). Pola instance identik `member_post_detail_screen:196`.
4. `FeedVideoPostView` diinstansiasi dengan `ownsController:false, playbackManagedExternally:true, coordinator:` saat flag ON.
5. `_managePreloadWindow` diganti memanggil `coordinator.setActive(activePostId)` ATAU `coordinator.clearActive()` (kalau item aktif foto) + `coordinator.setPreloadWindow(targetIds)` — persis pola `scoped_video_feed_screen.dart:453-468`, `targetIds` dari `adaptiveVideoPreloadPolicy.offsets(...)` yang **sudah** dipakai (tak berubah).
6. **`attach()` HANYA untuk item video yang benar-benar aktif** (satu panggilan, mirroring `_activateManaged`) — item di jendela preload **tidak** di-`attach()`, cukup lewat `setPreloadWindow` (pinned+paused+mute, tanpa `attachedViewIds`). Ini yang benar, BUKAN "semua item jendela di-attach".
7. Hapus infrastruktur legacy yang jadi mati (`_preloadedControllers`/`_preloadedCachedPlayers` map, `_claimPreloadedVideo`, create/dispose manual) — **belakangan**, di PR terpisah setelah swap terbukti stabil (lihat Sequencing).

### Yang TIDAK berubah (non-goals eksplisit)

- **Tidak** menyentuh struktur `FeedVideoPostView` di luar melengkapi intent gesture managed (poin 2) — widget sudah siap selebihnya.
- **Tidak** mengubah `AdaptiveVideoPreloadPolicy` atau semantik jendela preload (sudah dipakai apa adanya).
- **Tidak** membangun warm-handoff Feed↔Postingan (dua coordinator instance tetap terpisah). Registry/handoff app-level dikerjakan terpisah nanti kalau ada kebutuhan produk konkret — di luar cakupan migrasi ini, jangan digabung.
- **Tidak** mengubah UI/animasi/gesture Feed secara terlihat — murni penggantian mesin kepemilikan controller + pemulihan gesture yang sempat hilang di mode managed.
- **Tidak** dikerjakan sebagai satu PR raksasa — lihat Sequencing.

### Titik risiko spesifik & mitigasi

1. **Feed adalah permukaan tersibuk** — regresi di sini terlihat semua user, semua waktu. *Mitigasi:* feature-flag dikunci sejak screen dibuat (bukan live-toggle); nyalakan di build internal dulu; device-verify menyeluruh sebelum default true; rollback = flip flag, bukan revert kode.
2. **Ukuran `maxSessions=5` di coordinator** — Feed butuh: 1 aktif + hingga 3 preload (`maxPreloadSessions=3`) = maksimal 4 slot bersamaan, muat di bawah 5. **Sudah cukup, tak perlu diubah** — divalidasi dari konstanta yang ada, bukan asumsi.
3. **Mixed media (video+foto)** — `clearActive()` (Lingkup #1) adalah penutup celah utamanya; tanpanya, transisi video→foto→foreground adalah skenario audio-hantu paling mungkin lolos ke produksi. **WAJIB ada test eksplisit video→foto→foreground sebelum swap widget.**
4. **Gesture regresi diam-diam** — long-press peek/2x-speed mati total di mode managed hari ini. **WAJIB dilengkapi (Lingkup #2) SEBELUM swap**, bukan ditemukan lewat laporan user pasca-rilis.
5. **Cold-start & scroll cepat** — `scoped_video_feed_screen` sudah punya kasus serupa dan lolos T7 review; pola `_activateManaged` (pause+mute lama → setActive baru → adopt via notifier → detach lama → preload → evict, urutan deterministik) di-port apa adanya, bukan ditulis ulang.
6. **Cache-offline hydrate feed lama** (kelas bug D4/#140) — coordinator/`VideoPlayerSession` sudah punya D4 built-in, otomatis lebih baik dari legacy, bukan risiko baru.

### Sequencing (8 langkah, tiap langkah punya gerbang verifikasi sendiri)

1. Tambahkan `clearActive()` di coordinator + test unit **video→foto→foreground** eksplisit (menutup risiko #3 di atas SEBELUM kode lain disentuh).
2. Lengkapi jalur intent gesture managed (long-press peek-pause + 2x-speed) supaya tak ada regresi fitur saat migrasi.
3. Pasang coordinator Feed di balik feature flag yang dikunci sejak screen dibuat (belum dipakai widget — PR kecil, mudah direview, nol perubahan perilaku user-facing).
4. Swap instansiasi `FeedVideoPostView` ke mode managed di balik flag. **Hanya item video aktif yang `attach()`; item di jendela preload tetap pinned tapi TIDAK di-attach.**
5. Uji matriks: iOS/Android, WiFi/4G, Data Saver, background/lock, Feed→Profile (race yang sudah ditutup di jalur legacy), **DAN periksa event analytics `social_video_controller_collision`** (harus nol untuk cohort ber-flag).
6. Nyalakan flag default TRUE setelah collision nol (terverifikasi lewat analytics, bukan cuma manual QA) dan jumlah sesi (`_entries.length`) konsisten dengan ekspektasi (≤5, evict berjalan benar) selama masa observasi.
7. Baru hapus infrastruktur preload manual Feed (`_preloadedControllers`/`_preloadedCachedPlayers`/`_claimPreloadedVideo`) — di PR terpisah, setelah flag ON stabil.
8. App-level registry/handoff global (Feed↔Postingan warm handoff) dikerjakan **terpisah**, hanya bila memang dibutuhkan produk — bukan bagian migrasi ini.

Tiap langkah = PR terpisah, revert-able sendiri-sendiri, gerbang verifikasi sebelum lanjut ke langkah berikutnya.

## Estimasi & keputusan yang masih terbuka

- **Ukuran kerja:** sedang — lebih kecil dari perkiraan diskusi sebelumnya berkat temuan #3 (jendela preload sudah dibagi) dan #7 (tak ada handoff lintas-screen yang perlu didesain). Tetap bukan "quick patch" karena menyentuh 2400 baris file tersibuk.
- **Kapan dieksekusi:** BELUM diputuskan. Dokumen ini adalah *rencana*, bukan izin eksekusi. Perlu keputusan terpisah untuk mulai Tahap 1.
- **Siapa mengerjakan tiap tahap:** subagent-driven per tahap (pola yang sudah terbukti di sesi-sesi sebelumnya — implement→review adversarial→fix→verify), bukan satu agen mengerjakan semua tahap sekaligus.
