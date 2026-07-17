# Migrasi Feed utama ke PostVideoCoordinator (Opsi D)

**Tanggal:** 2026-07-17
**Status:** DESAIN v6 — arsitektur matang (v2: 6 gap; v3: 3 gap; v4: 2 gap; v5: 3 gap — pasangan `_disposeStaleUnprotectedEntries()`+`_evict()`, `cleanupGeneration`, capture `oldEntry` eksplisit. **v6 menutup 2 gap dari review keenam, keduanya serius**: **cleanup async WAJIB dibungkus `_guard()`** — `_registryRevision` cuma di-flush lewat `_guard()` (diverifikasi: SEMUA 7 pemanggil `_evict()`/`_disposeStaleUnprotectedEntries()` existing selalu ter-guard); tanpanya widget managed bisa menyimpan referensi sesi yang sudah dihapus, tak pernah dapat notifikasi re-adopsi; **otoritas resume lease dipindah SEPENUHNYA ke coordinator** — `end({required bool allowResume})`, resume nyata cuma terjadi kalau gate LIVE (post aktif, tak suspended/route-covered, tak user-pause — sama seperti `_canPlayEntry`) lolos SAAT `end()` dipanggil, BUKAN dari snapshot state saat `begin()`; cleanup akibat detach SELALU `allowResume:false`. Sekaligus menyederhanakan desain: lease tak perlu lagi menyimpan "state awal playback"). Belum ada kode ditulis, menunggu greenlight terpisah untuk eksekusi.
**Keputusan desain terkunci:** `PlaybackSession` (interface abstrak) DIPERLUAS dengan 1 method baru (`beginTransientGesture`) + kelas `TransientGestureLease` baru dengan `end({required bool allowResume})` (Opsi A dari 2 opsi yang dipertimbangkan — lihat §Kontrak API). Konsekuensi: **semua implementer interface ikut berubah**, bukan cuma `VideoPlayerSession`.
**File terdampak (nanti):**
- `flutter_app/lib/screens/feed_screen.dart` (2416 baris) — migrasi utama + wiring RouteAware/WidgetsBindingObserver level-screen (baru, lihat §Lingkup #7).
- `flutter_app/lib/features/feed/video/post_video_coordinator.dart` — tambah `clearActive()`, perluas interface `PlaybackSession` (`beginTransientGesture`) + kelas `TransientGestureLease`, method forwarding di coordinator.
- `flutter_app/lib/features/feed/video/video_player_session.dart` — implementasi konkret `beginTransientGesture`/`TransientGestureLease` baru.
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
2. **`FeedVideoPostView` SUDAH dual-mode.** Widget yang sama dipakai di feed (legacy) dan Postingan/fullscreen (managed) — parameter `ownsController`, `playbackManagedExternally`, `coordinator` sudah ada di constructor sejak T2. Migrasi **tidak perlu merombak struktur widget ini** — TAPI TETAP menyentuhnya untuk melengkapi intent gesture managed (long-press, lihat inventarisasi #11 & Lingkup #2 di bawah); klaim "widget tak tersentuh sama sekali" di versi awal dokumen ini keliru dan sudah diperbaiki.
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

**A. `PostVideoCoordinator.clearActive()`** — dipanggil saat item PageView aktif adalah post FOTO (bukan video). **Urutan berikut WAJIB persis begini** (ditemukan race nyata di v2: menaruh pause/mute SEBELUM generation-bump membuka celah — lihat penjelasan di bawah tabel):

**Fase sinkron (SATU pemanggilan `_guard(() {...})`, NOL `await` di dalamnya):**
0. **Capture `final oldEntry = _entries[_activePostId];` PALING AWAL, SEBELUM langkah 1** — kalau langkah ini terlewat dan `_activePostId` di-null-kan duluan, lookup `_entries[_activePostId]` di fase asinkron (langkah 7) akan gagal karena `_activePostId` sudah `null`. Kesalahan urutan yang gampang lolos kalau cuma ikut nomor tanpa baca catatan ini.
1. `_activePostId = null`.
2. **Naikkan `_playbackGeneration`** SEGERA, sebelum apa pun lain — ini satu-satunya yang membatalkan operasi `_claimAndPlay` tertunda dari `setActive()` sebelumnya.
3. **Lepas audio claim** — `_releaseAudioClaim()` (sinkron, bukan lewat `await`).
4. Reset `_userPausedActive = false`.
5. Naikkan `_playbackRevision.value++`.
6. Jalankan `_evict()`.

**Fase asinkron (SETELAH fase sinkron selesai, via `_enqueuePlayback` — SAMA persis pola yang dipakai `setActive()` untuk mem-pause sesi sebelumnya, [:230-234](../../../flutter_app/lib/features/feed/video/post_video_coordinator.dart)):**
7. `if (oldEntry != null) _enqueuePlayback(() async { await oldEntry.session.setVolume(0); await oldEntry.session.pause(); });` — pause+mute sesi yang tadinya aktif (pakai `oldEntry` hasil capture langkah 0, BUKAN lookup ulang `_entries[_activePostId]` yang sudah `null`), dikirim ke antrean serial, BUKAN di-`await` langsung di badan `clearActive()`.

**Kenapa urutan ini krusial (bug race di v2):** `_canPlayEntry` ([:441-447](../../../flutter_app/lib/features/feed/video/post_video_coordinator.dart)) membandingkan `generation` **parameter yang di-capture saat operasi di-enqueue** terhadap `_playbackGeneration` **field live** — generation bump hanya efektif membatalkan operasi lama kalau terjadi **sebelum** operasi lama sempat memeriksa ulang gate itu. `_guard` sendiri sinkron murni (`T Function()`, bukan `Future`). Kalau `clearActive()` menaruh `await pause()/setVolume(0)` LEBIH DULU (seperti v2), `await` itu menyerahkan kendali ke event loop — persis di celah itu, `_claimAndPlay` lama (dari `setActive()` sebelumnya, sudah di-enqueue via antrean serial `_playbackTail`) bisa lanjut jalan dan lolos gate SEBELUM generation sempat di-bump, lalu `play()` menang race. Fix: seluruh mutasi state (generation, activePostId, audio claim, revision, evict) **sinkron murni, nol await**, baru pause/mute entry lama dikirim ke antrean setelahnya.

**Test wajib:**
1. `setActive(A)` → SEGERA `clearActive()` sebelum operasi `_claimAndPlay(A)` yang ter-enqueue sempat jalan (simulasikan race — pastikan test benar-benar mengeksploitasi celah await, bukan cuma memanggil kedua method berurutan tanpa microtask di antaranya) → assert **A tidak pernah menerima panggilan `play()` sama sekali** (bukan cuma cek state akhir `paused==true,volume==0` — assert count `playCalls==0` pada fake session, karena state akhir yang benar bisa saja tercapai lewat urutan panggilan yang salah/kebetulan).
2. video→foto→foreground (dari risiko #3 di bawah).

**B. `PlaybackSession` diperluas 1 method baru (`beginTransientGesture`) + kelas `TransientGestureLease` baru — DIBUNGKUS LEASE, OTORITAS RESUME DI COORDINATOR** (koreksi editorial: dokumen sebelumnya bilang "2 method di `PlaybackSession`" — keliru, cuma `beginTransientGesture` yang jadi method interface; `end()` ada di kelas `TransientGestureLease`, bukan di `PlaybackSession`. Keputusan: **Opsi A** — perluas interface abstrak, bukan capability-check `is VideoPlayerSession`. Direvisi dari v2: `endTransientGesture()` tanpa parameter tidak punya identitas — kalau A di-long-press-2x lalu user swipe ke B sebelum jari lepas, panggilan akhir bisa salah sasaran ke sesi B atau gagal mengembalikan A ke speed 1x. Fix: tiru pola `VideoAudioClaim` yang sudah ada dan terbukti — `claim()`/`.isCurrent`/`.release()` — bukan bare method. **Direvisi lagi di v6 (gap ditemukan review keenam):** hanya COORDINATOR yang tahu apakah route sedang tertutup, post masih aktif, atau user sudah pause — widget/lease TIDAK boleh mengambil keputusan resume sendiri berdasar "state awal yang di-capture", karena state itu bisa basi di saat `end()` benar-benar dieksekusi):

```dart
abstract class PlaybackSession {
  // ...5 method existing (play/pause/seekTo/setVolume/dispose/position)...
  TransientGestureLease beginTransientGesture(TransientGestureKind kind);
}

enum TransientGestureKind { peekPause, doubleSpeed }

/// Analog VideoAudioClaim — token identitas yang membungkus postId + sesi.
/// `end()` ADA DI LEASE (bukan di session), sehingga otomatis tak
/// berpengaruh kalau lease sudah stale (sesi berbeda/sudah diganti).
/// TIDAK menyimpan "state awal playback" — keputusan resume dievaluasi
/// LIVE saat end() dipanggil, bukan dari snapshot beku saat begin().
abstract class TransientGestureLease {
  bool get isCurrent; // false kalau sesi sudah diganti/dievict/gesture lain menimpa

  /// [allowResume] SELALU wajib diisi eksplisit oleh pemanggil — tak ada
  /// default diam-diam. Speed SELALU dikembalikan ke 1x apa pun nilainya.
  /// Resume (play) HANYA terjadi kalau allowResume==true DAN gate live
  /// coordinator (post masih aktif, tak suspended/route-covered, user
  /// tak pause — sama seperti `_canPlayEntry`) semuanya lolos SAAT INI,
  /// bukan berdasar snapshot kapan `beginTransientGesture` dipanggil.
  /// No-op total kalau `!isCurrent`.
  Future<void> end({required bool allowResume});
}
```

**Otoritas resume — kontrak eksplisit (ditambahkan v6):**
- **Widget HANYA memakai lease yang dibungkus coordinator** — tak ada jalur pintas widget memanggil primitif playback session secara langsung untuk mengakhiri transient-gesture; semua lewat `lease.end(allowResume: ...)`.
- **Speed SELALU dikembalikan ke 1x**, terlepas dari `allowResume` — ini bukan keputusan yang digantung ke gate apa pun, video tak boleh nyangkut di speed 2x dalam kondisi APA PUN.
- **Resume (lanjut play) HANYA boleh kalau SEMUA**: `allowResume==true` DARI PEMANGGIL, post masih aktif (`identical` check terhadap `_activePostId`), coordinator tak suspended (route masih terlihat, bukan tertutup), DAN user belum pause eksplisit sejak itu — dievaluasi ulang **live** di dalam `end()`, memakai gate yang SAMA dengan `_canPlayEntry` (`:441-447`), BUKAN dari state yang di-snapshot saat `beginTransientGesture` dipanggil (snapshot itu bisa basi kalau `end()` dipanggil belakangan, mis. setelah swipe atau setelah route Profile dibuka).
- **Cleanup akibat detach/evict (§C) SELALU memakai `allowResume: false`** — detach berarti view ini bukan lagi yang aktif; sama sekali tak ada skenario sah untuk resume dari cleanup paksa coordinator.
- **Widget-triggered natural end** (user lepas jari tanpa interupsi) memakai `allowResume: true` — tapi resume TETAP hanya benar-benar terjadi kalau gate live di atas lolos; `allowResume:true` adalah *izin*, bukan *jaminan* resume.

Jaminan lain yang WAJIB dipenuhi implementasi (`VideoPlayerSession`/coordinator):
- **Swipe/keluar-item saat `doubleSpeed` aktif** → video WAJIB kembali ke speed 1x sebelum sesi benar-benar dibuang. Karena gesture Flutter BISA diinterupsi (kalah/menang arena ke drag PageView) sehingga `onLongPressEnd` **tidak selalu terpanggil**, coordinator (bukan cuma widget) harus menjamin ini — mekanisme konkret (`cleanupInFlight` + barrier via antrean serial) ada di **§C Barrier teardown asinkron** di bawah, karena `detach()`/`_evict()` yang sinkron tak bisa begitu saja "menunggu" `lease.end()` yang asinkron.
- **`lease.isCurrent` palsu setelah swipe ke item lain** — begin lease di A menyimpan identitas sesi A; kalau setelah itu sesi A diganti/dievict/di-detach (karena user swipe ke B), `isCurrent` harus jadi `false`, sehingga `end()` yang terlambat dipanggil widget jadi no-op aman, TIDAK memengaruhi sesi B.
- **Dispose selama gesture aktif tetap aman** — `session.dispose()` bisa dipanggil kapan pun; lease yang masih terbuka otomatis jadi `!isCurrent` (tak crash, tak memanggil method pada sesi yang sudah disposed).

**C. Barrier teardown asinkron — mekanisme KONKRET, bukan cuma "requirement" (gap ditemukan di v3: §B menyatakan "detach/evict coordinator paksa `lease.end()` SEBELUM detach/evict jalan" tanpa menentukan CARANYA — ternyata secara arsitektur TIDAK MUNGKIN begitu saja):**

Diverifikasi ke kode: `detach()` (`post_video_coordinator.dart:176`) dan `_evict()` (`:522`) keduanya **`void` sinkron murni**, dan `_evict()` men-dispose sesi via `unawaited(entry.session.dispose())` — fire-and-forget, `_entries.remove(id)` terjadi SEKETIKA (sinkron) sebelum dispose async selesai. `_isPinned()` (`:500-503`) cuma cek 3 himpunan statis (origin/active/preload) — **tak ada** konsep "cleanup sedang berjalan". Jadi tak ada tempat bagi `detach()`/`_evict()` yang sinkron untuk "menunggu" `lease.end()` yang asinkron sebelum lanjut membuang entry — kalau dipaksa `await` di dalam `detach()`, method itu jadi async dan meretakkan semua pemanggilnya (termasuk `scoped_video_feed_screen` yang sudah ada).

**Mekanisme yang benar (dua field + guard generation, minim ripple — direvisi lagi setelah review kelima menemukan entry bisa yatim permanen):**
1. Tambah `bool cleanupInFlight = false` DAN `int cleanupGeneration = 0` di `_SessionEntry` (generation, BUKAN bool polos — lihat alasan poin 4 di bawah).
2. `_evict()` (dan `_disposeStaleUnprotectedEntries()`) tambah guard: entry dengan `cleanupInFlight == true` **tidak** dibuang di pass ini — diperlakukan seperti pinned untuk keperluan eviction SAJA (tidak masuk `_isPinned()` yang sebenarnya, supaya tak mengubah semantik pin/window; cukup filter tambahan `!entry.cleanupInFlight` di titik seleksi stale-id).
3. `detach(viewId, postId)`: `attachedViewIds.remove(viewId)` tetap **sinkron seketika**. Kalau entry punya `TransientGestureLease` aktif (`isCurrent==true`): set `entry.cleanupInFlight = true`, capture `final generation = ++entry.cleanupGeneration;` (SEBELUM enqueue — ini kunci penyelesaian poin 4), lalu:
   ```dart
   _enqueuePlayback(() async {
     try {
       await lease.end(allowResume: false); // detach = bukan lagi view aktif; TAK PERNAH resume.
     } finally {
       // WAJIB dibungkus _guard() — lihat poin 7 di bawah (gap ditemukan
       // review keenam: _registryRevision HANYA di-flush oleh _guard(),
       // semua 7 pemanggil _evict()/_disposeStaleUnprotectedEntries()
       // existing di kode SELALU terbungkus _guard(). Tanpa ini, entry
       // termutasi tapi widget managed yang listen `registryListenable`
       // tak pernah dapat notifikasi → bisa nyimpen referensi sesi yang
       // sudah dihapus/disposed selamanya.
       _guard(() {
         // Hanya siklus cleanup PALING BARU untuk entry ini yang boleh
         // membersihkan flag + memicu eviction. Cegah siklus cleanup LAMA
         // (swipe A→B→A→B, entry sama dipakai ulang via _ensureEntry)
         // menimpa status siklus BARU yang mungkin sedang berjalan.
         if (!identical(_entries[postId], entry) ||
             entry.cleanupGeneration != generation) {
           return;
         }
         entry.cleanupInFlight = false;
         // WAJIB PASANGAN, bukan _evict() sendirian — lihat poin 4.
         _disposeStaleUnprotectedEntries();
         _evict();
       });
     }
   });
   ```
4. **Kenapa `_disposeStaleUnprotectedEntries()` + `_evict()` WAJIB dipanggil BERPASANGAN, bukan `_evict()` saja (bug ditemukan di v4 — celah nyata, bukan cuma soal gaya):** `_evict()` (`:522`) punya early-return `if (_entries.length <= maxSessions) return;` — untuk Feed yang biasanya jauh di bawah `maxSessions=5` sesi hidup bersamaan, memanggil `_evict()` sendirian **tidak berbuat apa-apa**, entry yang barusan selesai cleanup jadi **yatim permanen** di `_entries` (tak pernah ter-dispose, karena tak ada tekanan LRU yang memicunya). `_disposeStaleUnprotectedEntries()` (`:505`) yang TANPA gerbang `maxSessions` — membuang entry unpinned+unattached apa pun jumlah total sesi. Pola pasangan ini **sudah ada** persis di `setPreloadWindow` (`:276-277`, `_disposeStaleUnprotectedEntries(); _evict();` berurutan) — cukup direplikasi, bukan pola baru.
5. **Kenapa `cleanupGeneration`, bukan `bool` polos:** `_SessionEntry` **dipakai ulang** per postId selama masih di `_entries` (`_ensureEntry:487-490` — kembalikan entry existing kalau ada, bukan buat baru). Skenario nyata: user long-press-2x di A → swipe ke B (detach A, cleanup dimulai, `cleanupInFlight=true`) → swipe balik ke A dengan cepat (A jadi aktif lagi, mungkin mulai gesture BARU) → cleanup LAMA akhirnya selesai lewat antrean serial dan mencoba `entry.cleanupInFlight = false` — TANPA guard generation, ini bisa menimpa status siklus cleanup BARU yang sedang berjalan untuk entry YANG SAMA (`identical(_entries[postId], entry)` tetap true karena objek entry sama). Guard `entry.cleanupGeneration == generation` memastikan hanya siklus PALING BARU yang boleh membersihkan flag & memicu eviction; siklus lama yang sudah disusul jadi no-op diam di titik itu (finally tetap jalan, tapi kondisi di dalamnya gagal, jadi tak ada efek).
6. Kalau entry TIDAK punya lease aktif (kasus normal, mayoritas), `detach()` berjalan persis seperti sekarang — nol overhead tambahan untuk jalur yang tak melibatkan gesture.
7. **Seluruh mutasi state cleanup (`cleanupInFlight=false`, `_disposeStaleUnprotectedEntries()`, `_evict()`) WAJIB dibungkus `_guard(() {...})`** (bug ditemukan di review keenam — bukan gaya penulisan, tapi kebenaran fungsional): `_registryRevision.value++` **hanya** di-flush oleh `_guard()`'s finally block (`_mutationDepth==0 && _registryDirty`, `:397-408`). Diverifikasi: **semua 7 titik pemanggilan** `_evict()`/`_disposeStaleUnprotectedEntries()` yang sudah ada di kode (`:147,169,182,209,237,276-277`) **selalu** terbungkus `_guard()`, tanpa kecuali. Kalau cleanup di fase asinkron (poin 3) memanggil method-method ini TANPA `_guard()` (seperti draf pseudocode v5), `_entries` termutasi & `_registryDirty` ter-set TRUE, tapi `_registryRevision.value++` **tak pernah terjadi** — widget managed yang men-`listen` `registryListenable` untuk adopsi-ulang sesi (mekanisme T7) tak pernah dapat notifikasi, berisiko menyimpan referensi ke sesi yang sudah dihapus/disposed selamanya.

**Test wajib (lease, diperluas lagi):**
1. A di-`beginTransientGesture(doubleSpeed)` → sebelum `end()`, sesi A di-`detach()` (simulasikan swipe cepat) → assert **A TIDAK langsung ter-dispose** (`disposeCallCount==0` segera setelah `detach()` return) → assert speed A ter-restore ke 1x DAN `lease.isCurrent == false` **setelah antrean serial di-flush** → assert A **sekarang** ter-dispose (`disposeCallCount==1`) — **WAJIB dites dengan total sesi hidup ≤ `maxSessions`** (skenario Feed tipikal), supaya kegagalan "`_evict()` sendirian tak berbuat apa-apa" akan terdeteksi test, bukan cuma lolos kebetulan karena skenario tes kebetulan sudah di atas ambang LRU.
2. Panggil `lease.end(allowResume: true)` (terlambat, sesudah kasus di atas — `isCurrent` sudah `false`) → assert no-op total, tak ada efek pada sesi B yang sekarang aktif (termasuk TAK memicu play meski `allowResume:true`).
3. **Race A→B→A→B**: begin gesture di A → detach A (cleanup #1 mulai, `allowResume:false`) → SEBELUM cleanup #1 selesai, attach+begin gesture BARU di A lagi (cleanup generation naik) → detach A lagi (cleanup #2 mulai, `cleanupGeneration` bertambah lagi) → flush antrean → assert cleanup #1 yang telat selesai TIDAK menimpa state cleanup #2 (final state entry konsisten dengan siklus TERAKHIR, bukan tercampur/rusak).
4. **Registry notification setelah cleanup async**: begin gesture di A → detach A → flush antrean sampai cleanup selesai → assert `coordinator.sessionFor(A) == null` DAN listener `registryListenable`/`registryRevision` benar-benar terpanggil (bukan cuma `_entries` yang berubah diam-diam tanpa notifikasi) — test ini yang akan gagal kalau `_guard()` di poin 7 terlewat.
5. **Otoritas resume — allowResume tak cukup sendirian**: A aktif & playing → mulai gesture `doubleSpeed` → SELAGI gesture berlangsung, route Profile dibuka (`_suspended`/route-covered jadi true) → user lepas jari secara natural, widget panggil `lease.end(allowResume: true)` → assert speed A kembali 1x TAPI A **TIDAK** resume play (tetap paused/mute) karena gate live (`!_suspended`) gagal — membuktikan keputusan resume live-evaluated saat `end()`, bukan berdasar snapshot kondisi saat `begin()`.
6. **Otoritas resume — user-pause menang**: A aktif & playing → mulai gesture → SELAGI gesture berlangsung, user tap-pause eksplisit di tempat lain (`_userPausedActive=true`) → lepas jari, `end(allowResume:true)` → assert TAK resume (state pause user dihormati, bukan ditimpa).

**File terdampak untuk kontrak ini:** `post_video_coordinator.dart` (interface + kelas lease + field `cleanupInFlight`+`cleanupGeneration` di `_SessionEntry` + guard eviction + `detach()` bercabang + pasangan `_disposeStaleUnprotectedEntries()`+`_evict()`), `video_player_session.dart` (implementasi), **3 file test fake** (harus implement method baru — kesempatan sekaligus menambah test kasus di atas).

### Kontrak session-factory Feed (baru — sebelumnya tak eksplisit)

Saat `feed_screen` membuat `PlaybackSessionFactory` untuk instance coordinator-nya:
- **Hanya post `kind` video** yang boleh masuk ke `setPreloadWindow`/`setActive`/`attach` — post foto/carousel TIDAK PERNAH membuat sesi (guard di titik yang sama dengan filter `_visiblePosts` legacy, dipindah ke pemanggilan coordinator, bukan dihapus).
- **Lookup data post di dalam factory closure harus baca state TERBARU**, bukan menangkap list lama (`_visiblePosts`/`_posts`) di closure saat factory dibuat — kelas bug closure-stale-list yang umum di Flutter kalau factory dibuat sekali tapi list berubah (feed infinite-scroll/refresh).
- **Tag observasi pakai `SocialVideoSurface.mainFeed`** (`analyticsSurface: main_feed`) — bukan default/kosong, supaya telemetry collision (§Gerbang rollout di bawah) bisa membedakan sumber.
- **Pertahankan D4 (refresh signed-URL)** dan quality resolver (`videoQualityService.resolvePlaybackUrl`) di dalam session factory — ini yang selama ini jadi keunggulan coordinator dibanding legacy (PR #140); jangan sampai factory Feed yang baru malah lupa mewarisi ini.
- **Invariant jumlah sesi yang bisa diuji**: steady-state (setelah swipe settle) maksimal 4 sesi hidup (1 aktif + `maxPreloadSessions=3`); BOLEH sementara sampai 5 di tengah transisi swipe cepat (sebelum eviction lama selesai) — tapi harus turun ke ≤4 begitu settle. Test harus assert kedua kondisi ini secara terpisah (transient vs settled), bukan cuma cap keras `<=5` sepanjang waktu.

### Urutan attach/detach/dispose (eksplisit — sebelumnya cuma tersirat "mirip _activateManaged")

Empat sekuens WAJIB, semua sudah punya preseden terverifikasi di kode existing, tinggal dinyatakan eksplisit sebagai acceptance-criteria migrasi Feed:

1. **Video A → video B** (transisi antar-video): `coord.attach(viewIdB, B)` → `coord.setActive(B)` → `coord.detach(viewIdA, A)`. Persis urutan `scoped_video_feed_screen._activateManaged` ([:423-441](../../../flutter_app/lib/screens/scoped_video_feed_screen.dart)) — attach BARU dulu, baru detach LAMA. `setActive()` sendiri TIDAK memanggil detach (simetris dengan `clearActive()` yang juga tidak memanggil detach — lihat §Kontrak API — detach selalu tanggung jawab TERPISAH si pemanggil, bukan efek samping implisit method aktivasi).
2. **Video A → foto**: `coord.clearActive()` → `coord.detach(viewIdA, A)` **SELALU, TAK BERSYARAT** (koreksi dari draft sebelumnya yang membuatnya bersyarat "kalau keluar window" — salah, dan tidak konsisten dengan poin 1: `attach`/`detach` menandakan "view ini SEDANG AKTIF merender", bukan "post ini masih relevan/di-preload". Verifikasi ke `_activateManaged`: `detach(prevId)` di sana **tanpa syarat apa pun** selain `prevId != postId` — tak ada cek "masih di window"). Kalau A masih diinginkan tetap hidup untuk preload-backward, itu murni urusan `setPreloadWindow(...)` (pin) yang dipanggil TERPISAH SETELAH detach — pin tak butuh attach. `clearActive()` sendiri TIDAK memanggil detach, simetris dengan poin 1.
3. **Refresh/post dihapus dari list** (pull-to-refresh, infinite-scroll replace): `detach()`/hapus dari preload window untuk SEMUA postId yang tak lagi ada di list baru **SEBELUM** `_posts`/`_visiblePosts` ditukar ke list baru — mencegah coordinator menyimpan attach/pinned entry untuk postId yang sudah tak valid di UI (kelas bug "closure-stale-list" dari §Kontrak session-factory Feed, di sini dinyatakan sebagai urutan operasional konkret).
4. **Dispose screen**: `feed_screen.dispose()` memanggil `_videoCoordinator.dispose()` SEKALI — yang secara internal men-dispose SEMUA entry sesi (`post_video_coordinator.dart:370-389`, sudah invariant coordinator: "SATU-SATUNYA pemanggil `PlaybackSession.dispose`"). `FeedVideoPostView` instance manapun (managed) TIDAK PERNAH memanggil `session.dispose()` sendiri — sudah terjamin arsitektural oleh `ownsController:false`, tapi WAJIB jadi assertion eksplisit di test migrasi (mis. spy/counter di fake session: `disposeCallCount` dari widget harus selalu 0 saat managed).

### Lingkup

1. **[PRASYARAT]** Tambah `clearActive()` di `PostVideoCoordinator` sesuai kontrak lengkap di atas + test race `setActive→clearActive`.
2. **[PRASYARAT]** Perluas `PlaybackSession` (interface + `VideoPlayerSession` + 3 fake test) dengan `beginTransientGesture(kind) → TransientGestureLease` (`lease.end({required allowResume})`, bukan method terpisah di session), penuhi kontrak otoritas-resume + jaminan lain di §B TERMASUK mekanisme barrier `cleanupInFlight`+`_guard()` (§C) di `detach()`/`_evict()`. Ganti `_onLongPressStart`/`_onLongPressEnd` di `feed_video_post_view.dart` dari `ctrl.pause()/setPlaybackSpeed()` langsung ke intent lewat coordinator (simpan lease saat begin, panggil `lease.end(allowResume:true)` saat lepas jari natural) saat `_managed` (bukan lagi early-return kosong).
3. Punya satu `PostVideoCoordinator` instance per screen-lifetime, **di balik feature flag yang DIKUNCI sejak `initState`** (dibaca sekali, tak reaktif). Pola instance identik `member_post_detail_screen:196`.
4. `FeedVideoPostView` diinstansiasi dengan `ownsController:false, playbackManagedExternally:true, coordinator:` saat flag ON.
5. `_managePreloadWindow` diganti memanggil urutan §Urutan attach/detach/dispose #1/#2 (attach→setActive→detach ATAU clearActive→detach) + `coordinator.setPreloadWindow(targetIds)` — `targetIds` dari `adaptiveVideoPreloadPolicy.offsets(...)` yang **sudah** dipakai (tak berubah). Ikuti Kontrak session-factory Feed di atas. Refresh/replace list post ikuti §Urutan #3 (detach sebelum swap list).
6. **`attach()` HANYA untuk item video yang benar-benar aktif** (satu panggilan, mirroring `_activateManaged`) — item di jendela preload **tidak** di-`attach()`, cukup lewat `setPreloadWindow` (pinned+paused+mute, tanpa `attachedViewIds`). Dispose screen ikuti §Urutan #4 (coordinator satu-satunya pemanggil dispose sesi).
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
4. **Gesture regresi diam-diam** — long-press peek/2x-speed mati total di mode managed hari ini. **WAJIB dilengkapi (Lingkup #2) SEBELUM swap**, dengan kontrak otoritas-resume + jaminan lain di §B terpenuhi (test masing-masing).
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

1. Tambahkan `clearActive()` dengan urutan sinkron-dulu-baru-enqueue yang benar (kontrak lengkap di atas) + test race `setActive→clearActive` yang membuktikan `playCalls==0` (bukan cuma cek state akhir) + test video→foto→foreground.
2. Perluas `PlaybackSession` dengan `TransientGestureLease` + mekanisme barrier `cleanupInFlight` (kontrak lengkap di atas) + update 3 fake test + lengkapi intent gesture managed di `feed_video_post_view.dart` + test detach-saat-gesture-aktif (entry TIDAK langsung ter-dispose, `disposeCallCount==0` segera setelah `detach()`, baru ter-dispose setelah antrean cleanup selesai) + test `lease.isCurrent` jadi false, `end()` terlambat = no-op.
3. Pasang coordinator Feed di balik feature flag, **default OFF**, dikunci sejak screen dibuat (belum dipakai widget — PR kecil, nol perubahan perilaku user-facing). Wire RouteAware/WidgetsBindingObserver level-screen (Lingkup #7) di langkah ini juga (di balik flag yang sama).
4. Swap instansiasi `FeedVideoPostView` ke mode managed di balik flag (masih default OFF, dites internal dengan flag di-ON-kan manual). Ikuti §Urutan attach/detach/dispose #1-2 persis (attach→setActive→detach / clearActive→detach).
5. Uji matriks dengan flag ON internal: iOS/Android, WiFi/4G, Data Saver, background/lock, Feed→Profile, **DAN periksa `social_video_controller_collision`** memakai Gerbang rollout granular di atas (bukan "nol global").
6. **Nyalakan flag DEFAULT TRUE** untuk semua user (map legacy MASIH ADA di titik ini — flag tetap jadi jalur rollback kalau ada laporan regresi) — observasi masa aman (collision sesama-owner nol, audio-ganda nol, jumlah sesi konsisten ≤4 steady-state).
7. **⚠️ HANYA setelah masa observasi #6 aman:** hapus feature flag DAN infrastruktur preload manual legacy (`_preloadedControllers`/`_preloadedCachedPlayers`/`_claimPreloadedVideo`) DALAM SATU PR YANG SAMA. Titik ini adalah pergantian mekanisme rollback: SEBELUM PR ini, rollback = flip flag; SESUDAH PR ini, rollback = revert/redeploy versi sebelumnya (flag sudah tak ada, jalur legacy sudah tak ada, flip flag tak lagi bermakna apa pun). *(Versi sebelumnya dari dokumen ini salah menaruh penghapusan legacy sebagai langkah terpisah setelah "flag ON stabil" TANPA menghapus flag itu sendiri — kontradiksi yang membuat rollback mustahil di titik itu. Sudah diperbaiki di sini.)*
8. App-level registry/handoff global (Feed↔Postingan warm handoff) dikerjakan **terpisah**, hanya bila memang dibutuhkan produk — bukan bagian migrasi ini.

Tiap langkah = PR terpisah, revert-able sendiri-sendiri (via flag untuk langkah 3-6, via git revert untuk langkah 7-8), gerbang verifikasi sebelum lanjut ke langkah berikutnya.

## Estimasi & keputusan yang masih terbuka

- **Kematangan arsitektur:** v6 (dokumen ini) menutup 16 gap total dari enam putaran review. v2: urutan rollback, gerbang collision granular, kontrak `clearActive()`, kontrak transient-gesture (keputusan Opsi A), 4 kontradiksi internal, kontrak session-factory Feed. v3: race sinkron/async `clearActive()`, lease beridentitas, 4 sekuens attach/detach/dispose. v4: detach video→foto tak bersyarat, barrier teardown asinkron konkret. v5: pasangan `_disposeStaleUnprotectedEntries()`+`_evict()`, `cleanupGeneration`, capture `oldEntry` eksplisit. v6: cleanup async wajib `_guard()` (registry-notification silently broken tanpanya), otoritas resume dipindah penuh ke coordinator via `allowResume`+gate-live (bukan snapshot state). **Pola enam putaran ini sendiri adalah sinyal penting**: setiap putaran menemukan detail implementasi konkurensi yang terlewat (bukan kesalahan arah arsitektur) — bidang yang paling banyak dikoreksi berulang-ulang adalah persis `§Kontrak API` (clearActive + lease + barrier + otoritas resume), yang berarti area itu punya kompleksitas konkurensi tertinggi di seluruh migrasi dan LAYAK diberi waktu/perhatian ekstra saat implementasi nanti, bukan ditulis cepat lalu diperbaiki lewat hotfix.
- **Ukuran kerja:** sedang-besar — Langkah 1-2 (kontrak API `clearActive`+lease+barrier+otoritas-resume) adalah fondasi paling berisiko (5 putaran review berturut-turut menemukan race/gap halus di situ), **WAJIB review adversarial berbasis mutasi** sebelum lanjut ke langkah 3+, bukan sekadar review teks. Pertimbangkan bahkan menulis test-nya lebih dulu (TDD) mengingat kompleksitas konkurensinya. Tetap bukan "quick patch"; 8 langkah bertahap, masing-masing PR terpisah dengan gerbang sendiri.
- **Kapan dieksekusi:** BELUM diputuskan. Dokumen ini adalah *rencana*, bukan izin eksekusi. Perlu keputusan terpisah untuk mulai Langkah 1 — termasuk mempertimbangkan apakah `feed_screen.dart`/`post_video_coordinator.dart` sedang tenang dari aktivitas paralel (Codex atau lainnya) sebelum memulai, karena sequencing 8-langkah ini butuh beberapa PR berurutan di file yang sama.
- **Siapa mengerjakan tiap langkah:** subagent-driven per langkah (pola yang sudah terbukti di sesi-sesi sebelumnya — implement→review adversarial→fix→verify), bukan satu agen mengerjakan semua langkah sekaligus. Langkah 1-2 (kontrak API) cocok diverifikasi ekstra ketat (mis. review adversarial berbasis mutasi, seperti yang dipakai sesi ini untuk kasus lain) karena keduanya jadi fondasi seluruh langkah berikutnya.
