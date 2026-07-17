# Migrasi Feed utama ke PostVideoCoordinator (Opsi D)

**Tanggal:** 2026-07-17
**Status:** DESAIN v8 — arsitektur matang (v2: 6 gap; v3: 3 gap; v4: 2 gap; v5: 3 gap; v6: 2 gap; v7: 1 gap fundamental — lease/gate dipindah dari session ke coordinator. **v8 menutup 4 gap dari review kedelapan, 3 di antaranya P1**: (1) `end()` bisa stale-resume — gate dicek lalu `await` tanpa validasi ulang, sama seperti race `clearActive()` yang sudah ditutup tapi lupa diterapkan di sini; fix: reuse `_claimAndPlay` (sudah punya double-check pasca-await) alih-alih reimplementasi gate manual. (2) lease belum idempotent — panggilan `end()` kedua bisa jalan ulang; fix: `identical(entry.activeLease,this)` + `_endFuture` dibagi + `allowResume:false` menang permanen atas `true`. (3) `cleanupInFlight` bisa tertinggal SELAMANYA pada skenario detach→reattach-cepat→gesture-baru — kedua jalur pembersih generation-guard sama-sama bail-out; fix PALING KONSERVATIF: `beginTransientGesture` menolak (`null`) gesture baru selagi cleanup lama masih tertunda, menutup skenario di akar. (4) operasi begin (speed 2x) tak diserialkan dengan end (speed 1x) — bisa saling mendahului; fix: keduanya lewat `_enqueuePlayback` yang sama). Belum ada kode ditulis, menunggu greenlight terpisah untuk eksekusi.
**Keputusan desain terkunci:** `PlaybackSession` (interface abstrak) DIPERLUAS dengan **1 primitif trivial** (`setPlaybackSpeed(double)`) SAJA. Seluruh logika lease/gesture/gate (`beginTransientGesture`, `TransientGestureLease`, otoritas resume) **hidup di `PostVideoCoordinator`**, bukan di `PlaybackSession` (Opsi A tetap dipertahankan untuk perluasan interface abstrak, tapi cakupannya kini jauh lebih kecil — lihat §Kontrak API). Konsekuensi: `VideoPlayerSession` + 3 fake test cuma perlu implement 1 method sederhana, bukan seluruh mesin gesture.
**File terdampak (nanti):**
- `flutter_app/lib/screens/feed_screen.dart` (2416 baris) — migrasi utama + wiring RouteAware/WidgetsBindingObserver level-screen (baru, lihat §Lingkup #7).
- `flutter_app/lib/features/feed/video/post_video_coordinator.dart` — tambah `clearActive()`, tambah `beginTransientGesture(postId, kind)` + kelas privat lease + field `activeLease`/`cleanupInFlight`/`cleanupGeneration` di `_SessionEntry`, perluas interface `PlaybackSession` HANYA dengan `setPlaybackSpeed`.
- `flutter_app/lib/features/feed/video/video_player_session.dart` — implementasi `setPlaybackSpeed` (delegasi ke `VideoPlayerController.setPlaybackSpeed`, API yang sudah dipakai jalur legacy).
- `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` — long-press pindah dari `ctrl.pause()/setPlaybackSpeed()` langsung ke `widget.coordinator!.beginTransientGesture(postId, kind)` saat managed.
- **3 file test fake `PlaybackSession`** (WAJIB ikut berubah karena interface abstrak berubah, TAPI cakupannya kini kecil — cuma 1 method): `flutter_app/test/features/feed/video/post_video_coordinator_test.dart`, `flutter_app/test/screens/member_post_detail_screen_coordinator_test.dart`, `flutter_app/test/screens/scoped_video_feed_screen_test.dart`.

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

**B. Lease transient-gesture dipindah SEPENUHNYA ke `PostVideoCoordinator` — `PlaybackSession` cuma dapat 1 primitif trivial** (gap fundamental ditemukan di review ketujuh: v6 menaruh `beginTransientGesture()` di `PlaybackSession`/session, tapi narasi "otoritas resume" di v6 menuntut gate `_activePostId`/`_suspended`/`_userPausedActive` yang **hanya dipunyai coordinator** — `PlaybackSession` sengaja coordinator-agnostic (lihat komentar `PlaybackSessionFactory`: "Coordinator TIDAK tahu URL/detail video" — berlaku juga sebaliknya, session tidak tahu detail coordinator). Struktur kelas v6 secara arsitektur TIDAK BISA menegakkan narasinya sendiri; risiko implementer menyerahkan lease mentah ke widget dan resume tanpa cek live gate, memunculkan lagi kelas bug audio-hantu yang jadi topik utama sesi ini):

```dart
abstract class PlaybackSession {
  // ...5 method existing (play/pause/seekTo/setVolume/dispose/position)...
  Future<void> setPlaybackSpeed(double speed); // primitif SEDERHANA, tanpa konsep
                                                // lease/gesture/gate sama sekali —
                                                // sudah dipakai langsung ke
                                                // VideoPlayerController di jalur
                                                // legacy (feed_video_post_view.dart:
                                                // 2872,2918).
}

enum TransientGestureKind { peekPause, doubleSpeed }

/// Lease PUBLIK yang dilihat widget — TAPI instance konkretnya PRIVATE,
/// hanya dibuat oleh PostVideoCoordinator.beginTransientGesture(). Widget
/// TIDAK PERNAH bisa membuat/memegang lease session mentah.
abstract class TransientGestureLease {
  bool get isCurrent;
  Future<void> end({required bool allowResume});
}
```

Di `PostVideoCoordinator` (bukan lagi di session) — **direvisi lagi di v8 (review kedelapan menemukan 4 race lanjutan, 3 di antaranya P1)**: begin diserialkan lewat antrean yang sama dengan end (poin 4), `beginTransientGesture` menolak gesture baru selagi cleanup lama masih jalan (poin 3, paling konservatif — mencegah skenario orphan sepenuhnya alih-alih mencoba rekonsiliasi generasi tumpang tindih):
```dart
/// Satu-satunya cara membuat TransientGestureLease. Return null kalau
/// entry tak ditemukan/tak eligible ATAU entry masih punya cleanup/lease
/// tertunda dari siklus SEBELUMNYA (widget WAJIB menangani null — gesture
/// jadi no-op sesaat, bukan crash; kejadian sangat jarang, cuma saat
/// swipe-balik-lalu-langsung-gesture-lagi dalam window sangat sempit).
TransientGestureLease? beginTransientGesture(
  String postId,
  TransientGestureKind kind,
) {
  final entry = _entries[postId];
  if (entry == null) return null;
  if (entry.cleanupInFlight || entry.activeLease != null) return null;
  final generation = ++entry.cleanupGeneration;
  final lease = _CoordinatorTransientGestureLease(
    coordinator: this, postId: postId, entry: entry, generation: generation,
  );
  entry.activeLease = lease; // dilacak supaya detach() (§C) bisa force-end
                              // lease yang SAMA, bukan bikin cleanup terpisah.
  // Poin 4 fix: kirim perubahan speed/pause ke ANTREAN SERIAL yang SAMA
  // dipakai end() — supaya speed 2x (begin) DIJAMIN selesai sebelum speed
  // 1x (end) sempat dieksekusi, walau gesture berumur sangat pendek.
  _enqueuePlayback(() async {
    if (kind == TransientGestureKind.doubleSpeed) {
      await entry.session.setPlaybackSpeed(2.0);
    } else {
      await entry.session.pause();
    }
  });
  return lease;
}
```

**Kelas lease — idempotent + otoritas resume via `_claimAndPlay` (bukan reimplementasi gate manual):**
```dart
class _CoordinatorTransientGestureLease implements TransientGestureLease {
  _CoordinatorTransientGestureLease({
    required this.coordinator, required this.postId,
    required this.entry, required this.generation,
  });
  final PostVideoCoordinator coordinator;
  final String postId;
  final _SessionEntry entry;
  final int generation;
  Future<void>? _endFuture; // poin 2 fix: satu Future dibagi ke SEMUA
                             // pemanggil end() — kerja nyata jalan SEKALI,
                             // berapa kali pun end() dipanggil.
  bool _resumeVetoed = false; // poin 2 fix: allowResume:false PERMANEN
                               // mengalahkan true, walau true datang lebih
                               // dulu dan masih "sedang diproses".

  @override
  bool get isCurrent =>
      identical(coordinator._entries[postId], entry) &&
      entry.cleanupGeneration == generation &&
      identical(entry.activeLease, this); // poin 2 fix: cek identitas LEASE
                                            // sendiri, bukan cuma entry+gen —
                                            // supaya lease yang SAMA yang
                                            // sudah di-`end()` tak dianggap
                                            // current lagi oleh panggilan kedua.

  @override
  Future<void> end({required bool allowResume}) {
    if (!allowResume) _resumeVetoed = true;
    return _endFuture ??= _performEnd();
  }

  Future<void> _performEnd() {
    // Poin 4 fix (lanjutan): end juga lewat antrean serial YANG SAMA —
    // dijamin berjalan SETELAH operasi begin (speed 2x) di atas selesai,
    // karena FIFO ketat pada `_playbackTail`.
    return coordinator._enqueuePlayback(() async {
      if (!isCurrent) return; // sudah disusul gesture baru / entry lenyap
      entry.activeLease = null; // clear SEGERA, sinkron di awal closure.
      // Langkah 1 — speed SELALU balik ke 1x, TANPA SYARAT allowResume.
      await entry.session.setPlaybackSpeed(1.0);
      if (_resumeVetoed) return; // false menang, walau diminta belakangan.
      // Poin 1 fix: JANGAN reimplementasi gate+audio-claim+play manual —
      // pakai `_claimAndPlay` yang SUDAH benar (double-check `_canPlayEntry`
      // setelah tiap await internalnya). `_canPlayEntry` SUDAH mencakup
      // ketiga gate (post masih aktif, tak suspended, tak user-paused) —
      // tak perlu duplikasi cek manual. Generation BARU (bukan `generation`
      // milik lease yang sudah basi) supaya operasi lama tak menang race
      // kalau state berubah SELAGI `_performEnd()` masih di antrean.
      final freshGeneration = ++coordinator._playbackGeneration;
      await coordinator._claimAndPlay(entry, freshGeneration);
    });
  }
}
```

**Kontrak eksplisit:**
- **Widget HANYA menerima `TransientGestureLease` dari `coordinator.beginTransientGesture(postId, kind)`** — tak ada jalur untuk mendapat lease dari `PlaybackSession` langsung; interface session TIDAK PUNYA method gesture sama sekali.
- **`beginTransientGesture` return `null` kalau entry masih `cleanupInFlight` ATAU sudah punya `activeLease`** — mencegah dua siklus gesture tumpang tindih untuk entry yang sama, akar penyebab orphan `cleanupInFlight` (lihat §C poin 8).
- **`end()` idempotent** — panggilan kedua/berulang (natural dari widget + forced dari detach yang kebetulan nyaris bersamaan) mengembalikan `Future` yang SAMA; kerja nyata (speed-restore, gate-check, resume) jalan PERSIS SEKALI.
- **`allowResume:false` PERMANEN mengalahkan `true`** — walau `end(allowResume:true)` dipanggil lebih dulu dan closure-nya belum selesai, `end(allowResume:false)` yang menyusul tetap mem-veto resume (`_resumeVetoed` dicek di titik PALING AKHIR sebelum keputusan resume, bukan di-capture di awal).
- **Speed SELALU dikembalikan ke 1x** tanpa syarat `allowResume`, LEBIH DULU sebelum keputusan resume dievaluasi.
- **Resume (play) HANYA lewat `_claimAndPlay`** — bukan audio-claim+play manual yang diinline; ini menghindari duplikasi logika gate DAN otomatis mewarisi double-check pasca-`await` yang sudah terbukti benar di `_claimAndPlay`.
- **Cleanup akibat detach/evict (§C) SELALU memakai `allowResume: false`**, dan memanggil lease yang SAMA (`entry.activeLease`) — bukan membuat mekanisme cleanup terpisah dari lease yang mungkin masih dipegang widget.
- **Begin (speed 2x/pause) dan end (speed 1x) SAMA-SAMA lewat `_enqueuePlayback`** — FIFO ketat menjamin urutan penyelesaian, walau gesture berumur sangat pendek (tap-lepas cepat).

Jaminan lain yang WAJIB dipenuhi:
- **`lease.isCurrent` palsu setelah swipe ke item lain ATAU setelah `end()` pertama sukses** — kedua kasus dicek via kombinasi identity+generation+`identical(entry.activeLease, this)`.
- **Dispose selama gesture aktif tetap aman** — `session.dispose()` bisa dipanggil kapan pun; lease yang masih terbuka otomatis jadi `!isCurrent` (tak crash, tak memanggil method pada sesi yang sudah disposed).

**C. Barrier teardown asinkron — mekanisme KONKRET, bukan cuma "requirement" (gap ditemukan di v3: §B menyatakan "detach/evict coordinator paksa `lease.end()` SEBELUM detach/evict jalan" tanpa menentukan CARANYA — ternyata secara arsitektur TIDAK MUNGKIN begitu saja):**

Diverifikasi ke kode: `detach()` (`post_video_coordinator.dart:176`) dan `_evict()` (`:522`) keduanya **`void` sinkron murni**, dan `_evict()` men-dispose sesi via `unawaited(entry.session.dispose())` — fire-and-forget, `_entries.remove(id)` terjadi SEKETIKA (sinkron) sebelum dispose async selesai. `_isPinned()` (`:500-503`) cuma cek 3 himpunan statis (origin/active/preload) — **tak ada** konsep "cleanup sedang berjalan". Jadi tak ada tempat bagi `detach()`/`_evict()` yang sinkron untuk "menunggu" `lease.end()` yang asinkron sebelum lanjut membuang entry — kalau dipaksa `await` di dalam `detach()`, method itu jadi async dan meretakkan semua pemanggilnya (termasuk `scoped_video_feed_screen` yang sudah ada).

**Mekanisme yang benar (dua field + guard generation, minim ripple — direvisi lagi setelah review kelima menemukan entry bisa yatim permanen; direvisi LAGI di v7 karena generation kini dipegang lease itu sendiri, bukan dibuat ulang di detach()):**
1. Tambah `bool cleanupInFlight = false` DAN `int cleanupGeneration = 0` DAN `TransientGestureLease? activeLease` di `_SessionEntry`. `cleanupGeneration` dinaikkan **HANYA SEKALI** di `beginTransientGesture()` (§B) saat lease baru dibuat — `detach()` TIDAK menaikkannya lagi, cukup MEMBACA nilai yang sudah ada, supaya identitas "generasi gesture yang sama" konsisten antara widget yang masih pegang lease dan barrier detach() yang memaksanya berakhir.
2. `_evict()` (dan `_disposeStaleUnprotectedEntries()`) tambah guard: entry dengan `cleanupInFlight == true` **tidak** dibuang di pass ini — diperlakukan seperti pinned untuk keperluan eviction SAJA (tidak masuk `_isPinned()` yang sebenarnya, supaya tak mengubah semantik pin/window; cukup filter tambahan `!entry.cleanupInFlight` di titik seleksi stale-id).
3. `detach(viewId, postId)`: `attachedViewIds.remove(viewId)` tetap **sinkron seketika**. Kalau `entry.activeLease != null` (widget sedang memegang gesture aktif untuk entry ini): set `entry.cleanupInFlight = true`, capture `final generation = entry.cleanupGeneration;` (BACA nilai existing, JANGAN naikkan — generation sudah dinaikkan sekali oleh `beginTransientGesture()`), lalu:
   ```dart
   final lease = entry.activeLease!; // lease yang SAMA dipegang widget — bukan buat baru
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
5. **Kenapa `cleanupGeneration`, bukan `bool` polos:** `_SessionEntry` **dipakai ulang** per postId selama masih di `_entries` (`_ensureEntry:487-490` — kembalikan entry existing kalau ada, bukan buat baru). Guard `entry.cleanupGeneration == generation` di finally-block (poin 3) memastikan hanya siklus cleanup PALING BARU yang boleh membersihkan flag & memicu eviction.
6. Kalau entry TIDAK punya lease aktif (kasus normal, mayoritas), `detach()` berjalan persis seperti sekarang — nol overhead tambahan untuk jalur yang tak melibatkan gesture.
7. **Seluruh mutasi state cleanup (`cleanupInFlight=false`, `_disposeStaleUnprotectedEntries()`, `_evict()`) WAJIB dibungkus `_guard(() {...})`** (bug ditemukan di review keenam — bukan gaya penulisan, tapi kebenaran fungsional): `_registryRevision.value++` **hanya** di-flush oleh `_guard()`'s finally block (`_mutationDepth==0 && _registryDirty`, `:397-408`). Diverifikasi: **semua 7 titik pemanggilan** `_evict()`/`_disposeStaleUnprotectedEntries()` yang sudah ada di kode (`:147,169,182,209,237,276-277`) **selalu** terbungkus `_guard()`, tanpa kecuali. Kalau cleanup di fase asinkron (poin 3) memanggil method-method ini TANPA `_guard()` (seperti draf pseudocode v5), `_entries` termutasi & `_registryDirty` ter-set TRUE, tapi `_registryRevision.value++` **tak pernah terjadi** — widget managed yang men-`listen` `registryListenable` untuk adopsi-ulang sesi (mekanisme T7) tak pernah dapat notifikasi, berisiko menyimpan referensi ke sesi yang sudah dihapus/disposed selamanya.
8. **BUG DITEMUKAN review kedelapan — `cleanupInFlight` bisa tertinggal SELAMANYA (ditutup di ROOT, bukan direkonsiliasi):** Skenario yang tadinya mungkin: user long-press-2x di A (gen G1, `activeLease=lease1`) → swipe ke B (detach A: `cleanupInFlight=true`, capture generation G1, enqueue `lease1.end()`) → **SEBELUM** cleanup itu jalan, swipe balik ke A dengan cepat dan mulai gesture BARU (gen **G2**, `activeLease=lease2`) → cleanup lama akhirnya jalan: `lease1.end()` no-op (generation G2≠G1) DAN barrier `_guard()` di detach() JUGA early-return (guard yang sama di poin 3, generation mismatch) — **`cleanupInFlight` TAK PERNAH di-set `false`**, karena kedua jalur yang seharusnya membersihkannya sama-sama bail-out akibat generation tak cocok. Tanpa detach kedua yang kebetulan terjadi lagi, entry terlindung dari eviction **selamanya** — kebocoran nyata.
   **Fix dipilih (paling konservatif, menutup di akar):** `beginTransientGesture()` (§B) SEKARANG menolak (`return null`) membuat gesture baru kalau `entry.cleanupInFlight == true` ATAU `entry.activeLease != null` — skenario "gesture BARU mulai selagi cleanup LAMA masih tertunda" jadi TIDAK MUNGKIN terjadi sama sekali, bukan dicoba direkonsiliasi setelah kejadian. Konsekuensi UX: swipe-balik-lalu-langsung-gesture-lagi dalam jendela sangat sempit (durasi satu siklus `_enqueuePlayback`, biasanya sub-milidetik-hingga-beberapa-milidetik) membuat gesture baru sesaat tak berefek (widget dapat `null`, WAJIB menangani sebagai no-op) — tradeoff yang jauh lebih aman daripada entry bocor permanen. Guard generation di poin 3/5 TETAP dipertahankan sebagai lapisan pertahanan kedua (defense-in-depth) — kini jarang benar-benar diuji karena skenario pemicunya sudah tertutup di sini, tapi tak berbahaya membiarkannya (nol biaya tambahan, melindungi dari deviasi implementasi di masa depan).

**Test wajib (lease, diperluas lagi):**
1. A di-`beginTransientGesture(doubleSpeed)` → sebelum `end()`, sesi A di-`detach()` (simulasikan swipe cepat) → assert **A TIDAK langsung ter-dispose** (`disposeCallCount==0` segera setelah `detach()` return) → assert speed A ter-restore ke 1x DAN `lease.isCurrent == false` **setelah antrean serial di-flush** → assert A **sekarang** ter-dispose (`disposeCallCount==1`) — **WAJIB dites dengan total sesi hidup ≤ `maxSessions`** (skenario Feed tipikal), supaya kegagalan "`_evict()` sendirian tak berbuat apa-apa" akan terdeteksi test, bukan cuma lolos kebetulan karena skenario tes kebetulan sudah di atas ambang LRU.
2. Panggil `lease.end(allowResume: true)` (terlambat, sesudah kasus di atas — `isCurrent` sudah `false`) → assert no-op total, tak ada efek pada sesi B yang sekarang aktif (termasuk TAK memicu play meski `allowResume:true`).
3. **Race A→B→A→B**: begin gesture di A → detach A (cleanup #1 mulai, `allowResume:false`) → SEBELUM cleanup #1 selesai, attach+begin gesture BARU di A lagi (cleanup generation naik) → detach A lagi (cleanup #2 mulai, `cleanupGeneration` bertambah lagi) → flush antrean → assert cleanup #1 yang telat selesai TIDAK menimpa state cleanup #2 (final state entry konsisten dengan siklus TERAKHIR, bukan tercampur/rusak).
4. **Registry notification setelah cleanup async**: begin gesture di A → detach A → flush antrean sampai cleanup selesai → assert `coordinator.sessionFor(A) == null` DAN listener `registryListenable`/`registryRevision` benar-benar terpanggil (bukan cuma `_entries` yang berubah diam-diam tanpa notifikasi) — test ini yang akan gagal kalau `_guard()` di poin 7 terlewat.
5. **Otoritas resume — allowResume tak cukup sendirian**: A aktif & playing → mulai gesture `doubleSpeed` → SELAGI gesture berlangsung, route Profile dibuka (`_suspended`/route-covered jadi true) → user lepas jari secara natural, widget panggil `lease.end(allowResume: true)` → assert speed A kembali 1x TAPI A **TIDAK** resume play (tetap paused/mute) karena `_claimAndPlay` internal-nya menolak lewat `_canPlayEntry` — membuktikan keputusan resume live-evaluated saat `end()`, bukan berdasar snapshot kondisi saat `begin()`.
6. **Otoritas resume — user-pause menang**: A aktif & playing → mulai gesture → SELAGI gesture berlangsung, user tap-pause eksplisit di tempat lain (`_userPausedActive=true`) → lepas jari, `end(allowResume:true)` → assert TAK resume (state pause user dihormati, bukan ditimpa).
7. **Idempotency `end()`**: panggil `lease.end(allowResume:true)` DUA KALI berturut-turut (simulasikan double-dispatch) → assert kerja nyata (speed-restore, gate-check, resume) cuma jalan SEKALI (mis. `setPlaybackSpeed` invoked count == 1, bukan 2) DAN kedua panggilan mengembalikan `Future` yang identik/selesai bersamaan.
8. **`allowResume:false` menang atas `true` yang masih diproses**: panggil `lease.end(allowResume:true)` (belum selesai, masih di antrean) → SEBELUM selesai, panggil `lease.end(allowResume:false)` (mis. dari detach paksa) → flush antrean → assert TAK resume play, walau panggilan pertama minta `true`.
9. **`beginTransientGesture` menolak selagi cleanup pending**: begin gesture A → detach A (cleanup mulai, belum selesai) → SEBELUM cleanup selesai, panggil `beginTransientGesture(A, ...)` lagi → assert return `null` (bukan lease baru) — membuktikan skenario orphan poin 8 §C tak lagi bisa terjadi. Lanjutkan: flush antrean cleanup lama → assert `cleanupInFlight` akhirnya `false` (bukan tertinggal) → begin gesture baru di A sekarang berhasil (non-null).
10. **Begin-end diserialkan (speed tak terbalik)**: begin gesture `doubleSpeed` di A, LANGSUNG (tanpa flush apa pun) panggil `lease.end(allowResume:false)` (gesture sangat pendek) → flush antrean penuh → assert speed AKHIR A adalah `1.0`, BUKAN `2.0` — membuktikan operasi begin (speed→2x) selesai lebih dulu sebelum end (speed→1x) sempat dieksekusi, berkat FIFO `_enqueuePlayback` yang sama.

**File terdampak untuk kontrak ini:** `post_video_coordinator.dart` (SELURUH logika: `beginTransientGesture()`, kelas privat `_CoordinatorTransientGestureLease` dengan `end()` 6-langkah, field `cleanupInFlight`+`cleanupGeneration`+`activeLease` di `_SessionEntry` + guard eviction + `detach()` bercabang + pasangan `_disposeStaleUnprotectedEntries()`+`_evict()`), `video_player_session.dart` (implementasi TRIVIAL — cuma `setPlaybackSpeed(double)`, tanpa logika gesture/gate sama sekali), **3 file test fake** (kini HANYA perlu implement `setPlaybackSpeed` — beban jauh lebih ringan dibanding v6 yang menuntut seluruh lease/gate di tiap fake).

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
2. **[PRASYARAT]** Tambah `PostVideoCoordinator.beginTransientGesture(postId, kind) → TransientGestureLease?` + kelas privat lease dengan `end({required allowResume})` idempotent yang reuse `_claimAndPlay` untuk otoritas resume (§B) TERMASUK mekanisme barrier `cleanupInFlight`+`activeLease`+`_guard()` (§C) di `detach()`/`_evict()`. Perluas `PlaybackSession` HANYA dengan `setPlaybackSpeed(double)` (+ implementasi `VideoPlayerSession` + 3 fake test — beban kecil, cuma 1 method trivial). Ganti `_onLongPressStart`/`_onLongPressEnd` di `feed_video_post_view.dart` dari `ctrl.pause()/setPlaybackSpeed()` langsung ke `widget.coordinator!.beginTransientGesture(postId, kind)` (simpan lease saat begin, panggil `lease.end(allowResume:true)` saat lepas jari natural) saat `_managed` (bukan lagi early-return kosong).
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
2. Tambah `beginTransientGesture` + lease privat di coordinator + mekanisme barrier `cleanupInFlight`/`activeLease` (kontrak lengkap di atas) + perluas `PlaybackSession` cuma `setPlaybackSpeed` (update 3 fake test — beban kecil) + lengkapi intent gesture managed di `feed_video_post_view.dart` + test detach-saat-gesture-aktif (entry TIDAK langsung ter-dispose, `disposeCallCount==0` segera setelah `detach()`, baru ter-dispose setelah antrean cleanup selesai) + test `lease.isCurrent` jadi false, `end()` terlambat = no-op + test otoritas resume (route-covered/user-pause menang atas `allowResume:true`).
3. Pasang coordinator Feed di balik feature flag, **default OFF**, dikunci sejak screen dibuat (belum dipakai widget — PR kecil, nol perubahan perilaku user-facing). Wire RouteAware/WidgetsBindingObserver level-screen (Lingkup #7) di langkah ini juga (di balik flag yang sama).
4. Swap instansiasi `FeedVideoPostView` ke mode managed di balik flag (masih default OFF, dites internal dengan flag di-ON-kan manual). Ikuti §Urutan attach/detach/dispose #1-2 persis (attach→setActive→detach / clearActive→detach).
5. Uji matriks dengan flag ON internal: iOS/Android, WiFi/4G, Data Saver, background/lock, Feed→Profile, **DAN periksa `social_video_controller_collision`** memakai Gerbang rollout granular di atas (bukan "nol global").
6. **Nyalakan flag DEFAULT TRUE** untuk semua user (map legacy MASIH ADA di titik ini — flag tetap jadi jalur rollback kalau ada laporan regresi) — observasi masa aman (collision sesama-owner nol, audio-ganda nol, jumlah sesi konsisten ≤4 steady-state).
7. **⚠️ HANYA setelah masa observasi #6 aman:** hapus feature flag DAN infrastruktur preload manual legacy (`_preloadedControllers`/`_preloadedCachedPlayers`/`_claimPreloadedVideo`) DALAM SATU PR YANG SAMA. Titik ini adalah pergantian mekanisme rollback: SEBELUM PR ini, rollback = flip flag; SESUDAH PR ini, rollback = revert/redeploy versi sebelumnya (flag sudah tak ada, jalur legacy sudah tak ada, flip flag tak lagi bermakna apa pun). *(Versi sebelumnya dari dokumen ini salah menaruh penghapusan legacy sebagai langkah terpisah setelah "flag ON stabil" TANPA menghapus flag itu sendiri — kontradiksi yang membuat rollback mustahil di titik itu. Sudah diperbaiki di sini.)*
8. App-level registry/handoff global (Feed↔Postingan warm handoff) dikerjakan **terpisah**, hanya bila memang dibutuhkan produk — bukan bagian migrasi ini.

Tiap langkah = PR terpisah, revert-able sendiri-sendiri (via flag untuk langkah 3-6, via git revert untuk langkah 7-8), gerbang verifikasi sebelum lanjut ke langkah berikutnya.

## Estimasi & keputusan yang masih terbuka

- **Kematangan arsitektur:** v8 (dokumen ini) menutup 21 gap total dari delapan putaran review. v2-v6: lihat riwayat status di atas dokumen. v7: gap fundamental (lease/gate pindah session→coordinator). v8: 4 gap lanjutan (3 P1) — stale-resume di `end()` (fix: reuse `_claimAndPlay`), lease belum idempotent (fix: `_endFuture`+veto), `cleanupInFlight` bisa bocor permanen (fix: `beginTransientGesture` menolak overlap di akar), begin/end tak diserialkan (fix: satu antrean `_enqueuePlayback`). **Pola delapan putaran**: v2-v6 menyempurnakan detail konkurensi di struktur yang benar; v7 menemukan struktur kelasnya salah tempat; v8 menemukan bahwa struktur BARU v7 (yang secara arsitektur sudah benar) masih perlu state-machine yang benar-benar rapat — kepemilikan yang tepat (coordinator) adalah syarat PERLU tapi bukan CUKUP untuk bebas race; setiap operasi async di dalamnya tetap butuh diperlakukan dengan kedisiplinan sama seperti `clearActive()`/`_claimAndPlay` yang sudah lebih dulu terbukti benar. `§Kontrak API` tetap area kompleksitas tertinggi di seluruh migrasi.
- **Ukuran kerja:** sedang — Langkah 1-2 (kontrak API `clearActive`+`beginTransientGesture`+lease+barrier+otoritas-resume, semua di `post_video_coordinator.dart`) adalah fondasi paling berisiko (7 putaran review berturut-turut menemukan race/gap/struktur-kelas yang keliru di situ), **WAJIB review adversarial berbasis mutasi** sebelum lanjut ke langkah 3+, bukan sekadar review teks — dan sebaiknya diverifikasi TERPISAH dari langkah lain sebelum dianggap selesai, mengingat rekam jejak tujuh putaran. Pertimbangkan menulis test-nya lebih dulu (TDD). Tetap bukan "quick patch"; 8 langkah bertahap, masing-masing PR terpisah dengan gerbang sendiri.
- **Kapan dieksekusi:** BELUM diputuskan. Dokumen ini adalah *rencana*, bukan izin eksekusi. Perlu keputusan terpisah untuk mulai Langkah 1 — termasuk mempertimbangkan apakah `feed_screen.dart`/`post_video_coordinator.dart` sedang tenang dari aktivitas paralel (Codex atau lainnya) sebelum memulai, karena sequencing 8-langkah ini butuh beberapa PR berurutan di file yang sama.
- **Siapa mengerjakan tiap langkah:** subagent-driven per langkah (pola yang sudah terbukti di sesi-sesi sebelumnya — implement→review adversarial→fix→verify), bukan satu agen mengerjakan semua langkah sekaligus. Langkah 1-2 (kontrak API) cocok diverifikasi ekstra ketat (mis. review adversarial berbasis mutasi, seperti yang dipakai sesi ini untuk kasus lain) karena keduanya jadi fondasi seluruh langkah berikutnya.
