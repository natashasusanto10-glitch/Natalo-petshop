# Migrasi Feed utama ke PostVideoCoordinator (Opsi D)

**Tanggal:** 2026-07-17
**Status:** DESAIN v2 — arsitektur matang (revisi 2026-07-17 menutup 6 gap dari review kedua: urutan rollback, gerbang collision, kontrak `clearActive()`, kontrak gesture transient, kontradiksi internal, kontrak session-factory Feed). Belum ada kode ditulis, menunggu greenlight terpisah untuk eksekusi.
**Keputusan desain terkunci:** `PlaybackSession` (interface abstrak) DIPERLUAS dengan 2 method transient-gesture (Opsi A dari 2 opsi yang dipertimbangkan — lihat §Kontrak API). Konsekuensi: **semua implementer interface ikut berubah**, bukan cuma `VideoPlayerSession`.
**File terdampak (nanti):**
- `flutter_app/lib/screens/feed_screen.dart` (2416 baris) — migrasi utama + wiring RouteAware/WidgetsBindingObserver level-screen (baru, lihat §Lingkup #7).
- `flutter_app/lib/features/feed/video/post_video_coordinator.dart` — tambah `clearActive()`, perluas interface `PlaybackSession` (2 method transient-gesture), method forwarding di coordinator.
- `flutter_app/lib/features/feed/video/video_player_session.dart` — implementasi konkret 2 method transient-gesture baru.
- `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` — long-press pindah dari `ctrl.pause()/setPlaybackSpeed()` langsung ke intent lewat coordinator saat managed.
- **3 file test fake `PlaybackSession`** (WAJIB ikut berubah karena interface abstrak berubah): `flutter_app/test/features/feed/video/post_video_coordinator_test.dart`, `flutter_app/test/screens/member_post_detail_screen_coordinator_test.dart`, `flutter_app/test/screens/scoped_video_feed_screen_test.dart`.

## Masalah

Ada dua jalur kepemilikan controller video yang hidup berdampingan:

| | Feed utama (`feed_screen.dart`) | Postingan/fullscreen (`member_post_detail_screen`, `scoped_video_feed_screen`) |
|---|---|---|
| Pemilik controller | **Legacy** — `FeedVideoPostView` bikin & pegang controller sendiri; preload via `Map<String,VideoPlayerController>` manual di `feed_screen` | **Managed** — `PostVideoCoordinator` (instance baru per screen) satu-satunya pemilik; view pinjam via `ownsController:false, playbackManagedExternally:true, coordinator:` |
| Refresh signed-URL saat init gagal | Ditambal manual (PR #140 — port "D4") | Bawaan sejak T4 |
| Retry/error surface | Custom (`_videoLoadFailed`, `_maybeInitVideo`, `_runInitVideo`) | `VideoPlayerSession.retry()` (T8) |
| Mute/volume live | `_onFeedMutedChangedLive` sendiri | `_onMutedChanged` di coordinator |
| Route-cover / audio-hantu guard | `_routeCovered`/`_appBackgrounded`/`_canAutoplayNow` sendiri, hidup di dalam widget | Primitif (`pauseAll()`/`resumeAll()`) disediakan coordinator, TAPI **wajib dipanggil manual** oleh screen via `WidgetsBindingObserver`+`RouteAware` sendiri (lihat `member_post_detail_screen:123,374,393,405` — bukan otomatis) |

**Pola yang berulang:** tiap kali ditemukan bug kelas ini di jalur legacy (race Feed→Profile, video gagal diputar tak bisa pulih, dll), solusinya **sudah ada** di coordinator — kita hanya menambalnya satu per satu ke legacy supaya menyusul. Ini duplikasi logika permanen: dua implementasi paralel yang harus tetap identik perilakunya, dikerjakan dan direview dua kali setiap kali ada bug kelas baru.

Opsi D = pindahkan `feed_screen.dart` supaya juga pakai `PostVideoCoordinator`, sehingga hanya ada **satu implementasi playback** (satu kelas kepemilikan-controller) dipakai di seluruh app — BUKAN satu instance global. Feed dan Postingan tetap punya instance `PostVideoCoordinator` masing-masing, terpisah per screen (lihat inventarisasi #7). "Satu mesin" yang dimaksud adalah kesamaan KODE/perilaku, bukan penyatuan RUNTIME lintas-screen.

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
9. **`attach()` HANYA untuk item aktif, BUKAN untuk seluruh jendela preload.** Diverifikasi persis dari `scoped_video_feed_screen._activateManaged` (`scoped_video_feed_screen.dart:414-448`): `coord.attach(...)` dipanggil SATU KALI untuk `postId` yang baru jadi aktif; item di jendela preload (`setPreloadWindow`) HANYA dapat sesi paused+muted+pinned — **tidak pernah** masuk `attachedViewIds`. Attach = "view ini sedang merender & boleh klaim audio/pin lebih kuat"; pinned-tanpa-attach = "sesi hidup untuk instant-play nanti, tapi bukan view aktif". Koreksi atas kalimat Lingkup poin 6 di bawah ("attach() HANYA untuk item aktif"), yang di v1 berbunyi ambigu.
10. **Tidak ada `clearActive()` di coordinator saat ini.** `setActive(String postId)` (`post_video_coordinator.dart:215`) mewajibkan ID non-null. Karena Feed campur video+foto, begitu item aktif PageView berpindah ke post **foto**, tak ada cara memberi tahu coordinator "tak ada video aktif sekarang" — risiko video sebelumnya tertinggal "aktif" (berpotensi bersuara) di belakang post foto. **Gap nyata yang harus ditutup SEBELUM swap widget (Lingkup #1 baru).**
11. **Gesture long-press (peek-pause + 2x-speed-hold) SEPENUHNYA nonaktif di mode managed.** `_onLongPressStart`/`_onLongPressEnd` (`feed_video_post_view.dart:2845,2884`) early-return kalau `_managed` — keputusan T2 yang disengaja demi keamanan Postingan (`ctrl.play/pause/setSpeed` langsung berisiko race). Tapi ini "Sprint 4 #1 signature gesture" Feed yang dipakai user hari ini. Kalau Feed migrasi apa adanya, **fitur ini hilang diam-diam**. Scrubber sudah aman (`managed:` param sudah ada → seek-only). Long-press BELUM punya jalur intent managed — harus dilengkapi SEBELUM swap, bukan sesudah.
12. **Ada telemetry collision yang sudah terinstrumentasi produksi.** `SocialVideoCollisionMetricSink` (`social_video_observation_metrics.dart`) mengirim event analytics `social_video_controller_collision` (media_key + controller_count + surface_names) tiap observer deteksi >1 controller hidup untuk media yang sama lintas surface. Ini bisa dipakai sebagai **gerbang rollout data-driven** (bukan cuma manual QA) untuk menaikkan flag default.

**Kesimpulan inventarisasi:** cakupan migrasi jauh lebih sempit dari perkiraan paling awal, TAPI bukan "satu file" — `scoped_video_feed_screen.dart` adalah **preseden struktural yang nyaris identik** (PageView video dengan preload adaptif dikelola coordinator, terbukti lolos T7 review), namun dua gap konkret (poin 10, 11) memaksa perubahan interface `PostVideoCoordinator`/`PlaybackSession` itu sendiri — yang beriak ke `video_player_session.dart` + 3 file test fake, plus wiring baru level-screen di `feed_screen.dart` (poin route-cover). Migrasi Feed = mem-port pola yang sudah ada DI `scoped_video_feed_screen`, PLUS menutup 2 gap kontrak yang belum pernah dibutuhkan sebelumnya karena Postingan/fullscreen tak punya mixed-media atau long-press gesture. Kedua gap ini pekerjaan berdiri sendiri (Lingkup #1-2), harus selesai + teruji SEBELUM swap widget `feed_screen`, bukan diselesaikan sambil lalu di tengahnya.

## Opsi yang dipertimbangkan (rekap keputusan sebelumnya)

Dibahas 2026-07-17 sebelum doc ini: Opsi A (tambal per-bug, sudah beberapa kali dijalankan: D4/#140, route-cover, dll), Opsi B (unifikasi partial), Opsi C (biarkan dua jalur, terima duplikasi permanen), **Opsi D (migrasi penuh, dokumen ini)**.

Keputusan: **Opsi D adalah arah jangka panjang yang benar**, tapi bukan patch — perlu direncanakan sebelum dieksekusi karena Feed adalah **permukaan tersibuk di app**. Dokumen ini adalah perencanaan itu. Kapan dieksekusi menunggu keputusan terpisah (lihat Non-goals).

## Rancangan migrasi

### Kontrak API baru (WAJIB presisi — ini yang paling sering jadi sumber bug migrasi)

**A. `PostVideoCoordinator.clearActive()`** — dipanggil saat item PageView aktif adalah post FOTO (bukan video). Kontrak lengkap (bukan cuma "pause+mute+null"):
1. Ambil sesi `_activePostId` lama (kalau ada) → `pause()` + `setVolume(0)`.
2. `_activePostId = null`.
3. **Naikkan `_playbackGeneration`** — ini yang membatalkan operasi `_claimAndPlay` manapun yang masih tertunda dari `setActive()` sebelumnya (guard `_canPlayEntry` sudah cek `generation == _playbackGeneration`, lihat `post_video_coordinator.dart:441-470` — jadi play yang di-enqueue sebelum `clearActive()` akan otomatis no-op begitu generation berubah, TAPI method ini tetap harus eksplisit set volume 0 + pause pada entry yang mungkin sudah terlanjur `play()` sebelum generation-check kedua kena).
4. **Lepas audio claim** — panggil `_releaseAudioClaim()` (bukan biarkan menggantung sampai focus-lost berikutnya).
5. Reset `_userPausedActive = false` (state pause-manual-user tidak relevan lagi untuk item yang sudah bukan aktif).
6. Naikkan `_playbackRevision.value++` (supaya listener registry-nya konsisten dengan `setActive()`).
7. Jalankan `_evict()` (sesi lama mungkin sekarang jadi kandidat eviction karena tak lagi aktif/pinned).

**Test wajib:** `setActive(A)` → SEGERA `clearActive()` sebelum `await` play A selesai (simulasikan race async) → assert A berakhir `paused == true, volume == 0` — bukan ikut ter-play oleh operasi lama yang menang race.

**B. `PlaybackSession` interface diperluas 2 method** (keputusan: **Opsi A** — perluas interface abstrak, bukan capability-check `is VideoPlayerSession`. Alasan: interface sudah kecil (5 method), menambah 2 lagi murah dibanding merusak prinsip "semua sesi punya kontrak sama"; kalau nanti fullscreen butuh gesture serupa, tinggal pakai tanpa refactor ulang):

```dart
abstract class PlaybackSession {
  // ...5 method existing (play/pause/seekTo/setVolume/dispose/position)...
  Future<void> beginTransientGesture(TransientGestureKind kind);
  Future<void> endTransientGesture();
}

enum TransientGestureKind { peekPause, doubleSpeed }
```

Jaminan yang WAJIB dipenuhi implementasi (`VideoPlayerSession`) + coordinator forwarding:
- **Swipe/keluar-item saat `doubleSpeed` aktif** → video WAJIB kembali ke speed 1x sebelum sesi dilepas/pause/detach (jangan biarkan speed 2x nyangkut ke sesi yang dipakai ulang).
- **Route ditutup (Feed→Profile) selama transient-gesture berlangsung** → `endTransientGesture()` di akhir long-press TIDAK BOLEH memicu resume — harus tetap tunduk ke `_routeCovered`/`_canAutoplayNow` yang sudah ada (transient-gesture bukan alasan menembus guard route-cover).
- **User-pause eksplisit tak boleh tertimpa** — kalau user sempat tap-pause di tengah/sebelum transient-gesture, `endTransientGesture()` tidak boleh otomatis resume play (harus cek `isUserPaused` sebelum resume).
- **Dispose selama gesture aktif tetap aman** — `dispose()` sesi harus bisa dipanggil kapan pun tanpa exception/state korup meski `beginTransientGesture` belum di-`end`.

**File terdampak untuk kontrak ini:** `post_video_coordinator.dart` (interface + forwarding), `video_player_session.dart` (implementasi), **3 file test fake** (harus implement 2 method baru — kesempatan sekaligus menambah test kasus di atas).

### Kontrak session-factory Feed (baru — sebelumnya tak eksplisit)

Saat `feed_screen` membuat `PlaybackSessionFactory` untuk instance coordinator-nya:
- **Hanya post `kind` video** yang boleh masuk ke `setPreloadWindow`/`setActive`/`attach` — post foto/carousel TIDAK PERNAH membuat sesi (guard di titik yang sama dengan filter `_visiblePosts` legacy, dipindah ke pemanggilan coordinator, bukan dihapus).
- **Lookup data post di dalam factory closure harus baca state TERBARU**, bukan menangkap list lama (`_visiblePosts`/`_posts`) di closure saat factory dibuat — kelas bug closure-stale-list yang umum di Flutter kalau factory dibuat sekali tapi list berubah (feed infinite-scroll/refresh).
- **Tag observasi pakai `SocialVideoSurface.mainFeed`** (`analyticsSurface: main_feed`) — bukan default/kosong, supaya telemetry collision (§Gerbang rollout di bawah) bisa membedakan sumber.
- **Pertahankan D4 (refresh signed-URL)** dan quality resolver (`videoQualityService.resolvePlaybackUrl`) di dalam session factory — ini yang selama ini jadi keunggulan coordinator dibanding legacy (PR #140); jangan sampai factory Feed yang baru malah lupa mewarisi ini.
- **Invariant jumlah sesi yang bisa diuji**: steady-state (setelah swipe settle) maksimal 4 sesi hidup (1 aktif + `maxPreloadSessions=3`); BOLEH sementara sampai 5 di tengah transisi swipe cepat (sebelum eviction lama selesai) — tapi harus turun ke ≤4 begitu settle. Test harus assert kedua kondisi ini secara terpisah (transient vs settled), bukan cuma cap keras `<=5` sepanjang waktu.

### Lingkup

1. **[PRASYARAT]** Tambah `clearActive()` di `PostVideoCoordinator` sesuai kontrak lengkap di atas + test race `setActive→clearActive`.
2. **[PRASYARAT]** Perluas `PlaybackSession` (interface + `VideoPlayerSession` + 3 fake test) dengan `beginTransientGesture`/`endTransientGesture`, penuhi 4 jaminan di atas. Ganti `_onLongPressStart`/`_onLongPressEnd` di `feed_video_post_view.dart` dari `ctrl.pause()/setPlaybackSpeed()` langsung ke intent lewat coordinator saat `_managed` (bukan lagi early-return kosong).
3. Punya satu `PostVideoCoordinator` instance per screen-lifetime, **di balik feature flag yang DIKUNCI sejak `initState`** (dibaca sekali, tak reaktif). Pola instance identik `member_post_detail_screen:196`.
4. `FeedVideoPostView` diinstansiasi dengan `ownsController:false, playbackManagedExternally:true, coordinator:` saat flag ON.
5. `_managePreloadWindow` diganti memanggil `coordinator.setActive(activePostId)` ATAU `coordinator.clearActive()` (kalau item aktif foto) + `coordinator.setPreloadWindow(targetIds)` — persis pola `scoped_video_feed_screen.dart:453-468`, `targetIds` dari `adaptiveVideoPreloadPolicy.offsets(...)` yang **sudah** dipakai (tak berubah). Ikuti Kontrak session-factory Feed di atas.
6. **`attach()` HANYA untuk item video yang benar-benar aktif** (satu panggilan, mirroring `_activateManaged`) — item di jendela preload **tidak** di-`attach()`, cukup lewat `setPreloadWindow` (pinned+paused+mute, tanpa `attachedViewIds`).
7. **[BARU]** Wire `WidgetsBindingObserver`+`RouteAware` di LEVEL `feed_screen` sendiri (screen ini belum punya sama sekali hari ini — logic route-cover legacy hidup di dalam widget, bukan screen), memanggil `coordinator.pauseAll()`/`resumeAll()` mengikuti pola `member_post_detail_screen:374,393,405` — supaya route-cover benar-benar berfungsi, bukan asumsi "built-in".
8. Hapus infrastruktur legacy yang jadi mati (`_preloadedControllers`/`_preloadedCachedPlayers` map, `_claimPreloadedVideo`, create/dispose manual) — **HANYA setelah flag di-hardcode ON permanen** (lihat Sequencing — bukan sekadar "setelah stabil" sambil flag mekanisme rollback masih ada).

### Yang TIDAK berubah (non-goals eksplisit)

- **Tidak** menyentuh struktur `FeedVideoPostView` di luar melengkapi intent gesture managed (Lingkup #2) — widget sudah siap selebihnya.
- **Tidak** mengubah `AdaptiveVideoPreloadPolicy` atau semantik jendela preload (sudah dipakai apa adanya).
- **Tidak** membangun warm-handoff Feed↔Postingan (dua coordinator instance tetap terpisah, lihat inventarisasi #7). Registry/handoff app-level dikerjakan terpisah nanti kalau ada kebutuhan produk konkret — di luar cakupan migrasi ini, jangan digabung. **Konsekuensi eksplisit:** collision LINTAS-SURFACE (Feed vs Postingan untuk post yang sama) TIDAK dijamin nol oleh migrasi ini — lihat Gerbang rollout.
- **Tidak** mengubah UI/animasi/gesture Feed secara terlihat — murni penggantian mesin kepemilikan controller + pemulihan gesture yang sempat hilang di mode managed.
- **Tidak** dikerjakan sebagai satu PR raksasa — lihat Sequencing.

### Titik risiko spesifik & mitigasi

1. **Feed adalah permukaan tersibuk** — regresi di sini terlihat semua user, semua waktu. *Mitigasi:* feature-flag dikunci sejak screen dibuat; nyalakan di build internal dulu; device-verify menyeluruh sebelum default true. **Rollback SELAMA flag masih hidup = flip flag; SETELAH flag+legacy dihapus = revert/redeploy versi sebelumnya, BUKAN flip flag** (lihat koreksi urutan di Sequencing — versi sebelumnya dari dokumen ini salah menaruh penghapusan legacy sebelum flag benar-benar dihapus).
2. **Ukuran `maxSessions=5` di coordinator** — Feed butuh: 1 aktif + hingga 3 preload = maksimal 4 slot steady-state, transient boleh sampai 5. **Sudah cukup, tak perlu diubah.**
3. **Mixed media (video+foto)** — `clearActive()` (Lingkup #1) menutup celah utamanya. **WAJIB test eksplisit video→foto→foreground sebelum swap widget**, termasuk kasus race `setActive→clearActive` di atas.
4. **Gesture regresi diam-diam** — long-press peek/2x-speed mati total di mode managed hari ini. **WAJIB dilengkapi (Lingkup #2) SEBELUM swap**, dengan 4 jaminan transient-gesture terpenuhi (test masing-masing).
5. **Route-cover TIDAK otomatis** — feed_screen belum punya wiring RouteAware/WidgetsBindingObserver level-screen (Lingkup #7). Tanpa ini, migrasi bisa lolos test unit tapi gagal di device real untuk skenario Feed→Profile persis seperti bug yang sudah kita tutup di jalur legacy.
6. **Cold-start & scroll cepat** — `scoped_video_feed_screen` sudah punya kasus serupa dan lolos T7 review; pola `_activateManaged` di-port apa adanya, bukan ditulis ulang.
7. **Cache-offline hydrate feed lama** (kelas bug D4/#140) — coordinator/`VideoPlayerSession` sudah punya D4 built-in via kontrak session-factory di atas, otomatis lebih baik dari legacy, bukan risiko baru.

### Gerbang rollout (diperbaiki — target lama "collision harus nol" tidak sesuai scope non-goals)

Karena Feed dan Postingan sengaja tetap dua instance coordinator terpisah (non-goal warm-handoff), menuntut **collision global nol** tidak realistis dan bertentangan dengan keputusan itu sendiri. Gerbang yang benar, granular per jenis:
- **Collision sesama-owner `main_feed`** (dua sesi video coordinator Feed sendiri untuk post yang sama) — **HARUS NOL**. Ini sinyal migrasi Feed itu sendiri rusak (bug nyata di dalam scope migrasi).
- **Collision lintas-surface** (`main_feed` vs `post_detail`/`fullscreen` untuk post yang sama, mis. user buka Postingan dari Profile sementara Feed masih di background) — **tidak boleh MENINGKAT dari baseline pra-migrasi**, boleh tetap ada (sudah kelas skenario yang ada sebelum migrasi juga, karena instance tetap terpisah).
- **Audio ganda (dua sumber bersuara bersamaan)** — **HARUS NOL, TANPA PENGECUALIAN**, terlepas dari collision controller-instance di atas. Ini dijamin `VideoAudioArbiter` (satu audio-focus-owner global lintas SEMUA instance coordinator) — invariant ini yang sebenarnya paling penting bagi user, bukan jumlah controller.
- **Collision global benar-benar nol** — baru bisa diwajibkan SETELAH app-level registry/handoff dibuat (Lingkup #8 lama/non-goal ini — proyek terpisah).

### Sequencing (8 langkah, urutan rollback DIPERBAIKI — lihat catatan ⚠️)

1. Tambahkan `clearActive()` (kontrak lengkap di atas) + test race `setActive→clearActive` + test video→foto→foreground.
2. Perluas `PlaybackSession` dengan transient-gesture (kontrak lengkap di atas) + update 3 fake test + lengkapi intent gesture managed di `feed_video_post_view.dart`.
3. Pasang coordinator Feed di balik feature flag, **default OFF**, dikunci sejak screen dibuat (belum dipakai widget — PR kecil, nol perubahan perilaku user-facing). Wire RouteAware/WidgetsBindingObserver level-screen (Lingkup #7) di langkah ini juga (di balik flag yang sama).
4. Swap instansiasi `FeedVideoPostView` ke mode managed di balik flag (masih default OFF, dites internal dengan flag di-ON-kan manual). **Hanya item video aktif yang `attach()`; item di jendela preload tetap pinned tapi TIDAK di-attach.**
5. Uji matriks dengan flag ON internal: iOS/Android, WiFi/4G, Data Saver, background/lock, Feed→Profile, **DAN periksa `social_video_controller_collision`** memakai Gerbang rollout granular di atas (bukan "nol global").
6. **Nyalakan flag DEFAULT TRUE** untuk semua user (map legacy MASIH ADA di titik ini — flag tetap jadi jalur rollback kalau ada laporan regresi) — observasi masa aman (collision sesama-owner nol, audio-ganda nol, jumlah sesi konsisten ≤4 steady-state).
7. **⚠️ HANYA setelah masa observasi #6 aman:** hapus feature flag DAN infrastruktur preload manual legacy (`_preloadedControllers`/`_preloadedCachedPlayers`/`_claimPreloadedVideo`) DALAM SATU PR YANG SAMA. Titik ini adalah pergantian mekanisme rollback: SEBELUM PR ini, rollback = flip flag; SESUDAH PR ini, rollback = revert/redeploy versi sebelumnya (flag sudah tak ada, jalur legacy sudah tak ada, flip flag tak lagi bermakna apa pun). *(Versi sebelumnya dari dokumen ini salah menaruh penghapusan legacy sebagai langkah terpisah setelah "flag ON stabil" TANPA menghapus flag itu sendiri — kontradiksi yang membuat rollback mustahil di titik itu. Sudah diperbaiki di sini.)*
8. App-level registry/handoff global (Feed↔Postingan warm handoff) dikerjakan **terpisah**, hanya bila memang dibutuhkan produk — bukan bagian migrasi ini.

Tiap langkah = PR terpisah, revert-able sendiri-sendiri (via flag untuk langkah 3-6, via git revert untuk langkah 7-8), gerbang verifikasi sebelum lanjut ke langkah berikutnya.

## Estimasi & keputusan yang masih terbuka

- **Kematangan arsitektur:** v2 (dokumen ini) menutup 6 gap dari review kedua — urutan rollback, gerbang collision granular, kontrak `clearActive()` lengkap, kontrak transient-gesture + keputusan Opsi A (perluas interface), 4 kontradiksi internal, kontrak session-factory Feed. Tidak ada lagi gap arsitektur yang diketahui terbuka.
- **Ukuran kerja:** sedang-besar — lebih besar dari perkiraan v1 karena Lingkup #1-2 (clearActive + transient-gesture interface) ternyata butuh perubahan interface abstrak + 3 file test fake, bukan cuma "port pola yang sudah ada". Tetap bukan "quick patch"; 8 langkah bertahap, masing-masing PR terpisah dengan gerbang sendiri.
- **Kapan dieksekusi:** BELUM diputuskan. Dokumen ini adalah *rencana*, bukan izin eksekusi. Perlu keputusan terpisah untuk mulai Langkah 1 — termasuk mempertimbangkan apakah `feed_screen.dart`/`post_video_coordinator.dart` sedang tenang dari aktivitas paralel (Codex atau lainnya) sebelum memulai, karena sequencing 8-langkah ini butuh beberapa PR berurutan di file yang sama.
- **Siapa mengerjakan tiap langkah:** subagent-driven per langkah (pola yang sudah terbukti di sesi-sesi sebelumnya — implement→review adversarial→fix→verify), bukan satu agen mengerjakan semua langkah sekaligus. Langkah 1-2 (kontrak API) cocok diverifikasi ekstra ketat (mis. review adversarial berbasis mutasi, seperti yang dipakai sesi ini untuk kasus lain) karena keduanya jadi fondasi seluruh langkah berikutnya.
