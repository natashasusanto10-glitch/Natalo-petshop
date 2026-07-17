# Migrasi Feed utama ke PostVideoCoordinator (Opsi D)

**Tanggal:** 2026-07-17
**Status:** DESAIN v3 — arsitektur matang (v2 menutup 6 gap dari review kedua: urutan rollback, gerbang collision, kontrak `clearActive()`, kontrak gesture transient, kontradiksi internal, kontrak session-factory Feed. v3 menutup 3 gap dari review ketiga: **race nyata di urutan `clearActive()`** — generation-bump WAJIB sinkron sebelum pause/mute, bukan sesudah; **transient-gesture butuh lease** beridentitas — analog `VideoAudioClaim` — bukan bare method tanpa token; **urutan attach/detach/dispose dieksplisitkan** jadi 4 sekuens konkret). Belum ada kode ditulis, menunggu greenlight terpisah untuk eksekusi.
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

**A. `PostVideoCoordinator.clearActive()`** — dipanggil saat item PageView aktif adalah post FOTO (bukan video). **Urutan berikut WAJIB persis begini** (ditemukan race nyata di v2: menaruh pause/mute SEBELUM generation-bump membuka celah — lihat penjelasan di bawah tabel):

**Fase sinkron (SATU pemanggilan `_guard(() {...})`, NOL `await` di dalamnya):**
1. `_activePostId = null`.
2. **Naikkan `_playbackGeneration`** SEGERA, sebelum apa pun lain — ini satu-satunya yang membatalkan operasi `_claimAndPlay` tertunda dari `setActive()` sebelumnya.
3. **Lepas audio claim** — `_releaseAudioClaim()` (sinkron, bukan lewat `await`).
4. Reset `_userPausedActive = false`.
5. Naikkan `_playbackRevision.value++`.
6. Jalankan `_evict()`.

**Fase asinkron (SETELAH fase sinkron selesai, via `_enqueuePlayback` — SAMA persis pola yang dipakai `setActive()` untuk mem-pause sesi sebelumnya, [:230-234](../../../flutter_app/lib/features/feed/video/post_video_coordinator.dart)):**
7. `_enqueuePlayback(() async { await oldEntry.session.setVolume(0); await oldEntry.session.pause(); })` — pause+mute sesi yang tadinya aktif, dikirim ke antrean serial, BUKAN di-`await` langsung di badan `clearActive()`.

**Kenapa urutan ini krusial (bug race di v2):** `_canPlayEntry` ([:441-447](../../../flutter_app/lib/features/feed/video/post_video_coordinator.dart)) membandingkan `generation` **parameter yang di-capture saat operasi di-enqueue** terhadap `_playbackGeneration` **field live** — generation bump hanya efektif membatalkan operasi lama kalau terjadi **sebelum** operasi lama sempat memeriksa ulang gate itu. `_guard` sendiri sinkron murni (`T Function()`, bukan `Future`). Kalau `clearActive()` menaruh `await pause()/setVolume(0)` LEBIH DULU (seperti v2), `await` itu menyerahkan kendali ke event loop — persis di celah itu, `_claimAndPlay` lama (dari `setActive()` sebelumnya, sudah di-enqueue via antrean serial `_playbackTail`) bisa lanjut jalan dan lolos gate SEBELUM generation sempat di-bump, lalu `play()` menang race. Fix: seluruh mutasi state (generation, activePostId, audio claim, revision, evict) **sinkron murni, nol await**, baru pause/mute entry lama dikirim ke antrean setelahnya.

**Test wajib:**
1. `setActive(A)` → SEGERA `clearActive()` sebelum operasi `_claimAndPlay(A)` yang ter-enqueue sempat jalan (simulasikan race — pastikan test benar-benar mengeksploitasi celah await, bukan cuma memanggil kedua method berurutan tanpa microtask di antaranya) → assert **A tidak pernah menerima panggilan `play()` sama sekali** (bukan cuma cek state akhir `paused==true,volume==0` — assert count `playCalls==0` pada fake session, karena state akhir yang benar bisa saja tercapai lewat urutan panggilan yang salah/kebetulan).
2. video→foto→foreground (dari risiko #3 di bawah).

**B. `PlaybackSession` interface diperluas 2 method — DIBUNGKUS LEASE** (keputusan: **Opsi A** — perluas interface abstrak, bukan capability-check `is VideoPlayerSession`. Direvisi dari v2: `endTransientGesture()` tanpa parameter tidak punya identitas — kalau A di-long-press-2x lalu user swipe ke B sebelum jari lepas, panggilan akhir bisa salah sasaran ke sesi B atau gagal mengembalikan A ke speed 1x. Fix: tiru pola `VideoAudioClaim` yang sudah ada dan terbukti — `claim()`/`.isCurrent`/`.release()` — bukan bare method):

```dart
abstract class PlaybackSession {
  // ...5 method existing (play/pause/seekTo/setVolume/dispose/position)...
  TransientGestureLease beginTransientGesture(TransientGestureKind kind);
}

enum TransientGestureKind { peekPause, doubleSpeed }

/// Analog VideoAudioClaim — token identitas yang membungkus postId, sesi,
/// generation-saat-begin, dan state playback awal. `endTransientGesture()`
/// jadi method PADA LEASE (bukan pada session), sehingga otomatis tak
/// berpengaruh kalau lease sudah using stale (sesi berbeda/sudah diganti).
abstract class TransientGestureLease {
  bool get isCurrent; // false kalau sesi sudah diganti/dievict/gesture lain menimpa
  Future<void> end(); // no-op kalau !isCurrent
}
```

Jaminan yang WAJIB dipenuhi implementasi (`VideoPlayerSession`/coordinator) — semua lewat mekanisme lease, BUKAN diasumsikan widget selalu sempat memanggil `end()` di waktu yang tepat:
- **Swipe/keluar-item saat `doubleSpeed` aktif** → video WAJIB kembali ke speed 1x sebelum sesi dilepas/pause/detach. Karena gesture Flutter BISA diinterupsi (kalah/menang arena ke drag PageView) sehingga `onLongPressEnd` **tidak selalu terpanggil**, jalur **detach/evict coordinator sendiri** (bukan cuma widget) harus memeriksa apakah entry yang mau di-detach/evict masih punya lease aktif → paksa `lease.end()` (restore speed 1x) SEBELUM detach/evict jalan.
- **`lease.isCurrent` palsu setelah swipe ke item lain** — begin lease di A menyimpan identitas sesi A; kalau setelah itu sesi A diganti/dievict/di-detach (karena user swipe ke B), `isCurrent` harus jadi `false`, sehingga `end()` yang terlambat dipanggil widget jadi no-op aman, TIDAK memengaruhi sesi B.
- **Route ditutup (Feed→Profile) selama gesture berlangsung** → `lease.end()` TIDAK BOLEH memicu resume — tetap tunduk ke `_routeCovered`/`_canAutoplayNow` yang sudah ada.
- **User-pause eksplisit tak boleh tertimpa** — state awal playback (playing/paused) di-capture SAAT `beginTransientGesture` dipanggil (bagian dari lease); `end()` mengembalikan ke state awal itu, BUKAN otomatis resume-play — kalau state awal sudah paused (user-pause), `end()` mengembalikan ke paused, bukan play.
- **Dispose selama gesture aktif tetap aman** — `session.dispose()` bisa dipanggil kapan pun; lease yang masih terbuka otomatis jadi `!isCurrent` (tak crash, tak memanggil method pada sesi yang sudah disposed).

**Test wajib:** A di-`beginTransientGesture(doubleSpeed)` → sebelum `end()`, sesi A di-evict/detach (simulasikan swipe cepat) → assert speed A ter-restore ke 1x DAN `lease.isCurrent == false` → panggil `lease.end()` (terlambat) → assert no-op, TIDAK ada efek pada sesi B yang sekarang aktif.

**File terdampak untuk kontrak ini:** `post_video_coordinator.dart` (interface + kelas lease + logic detach/evict yang memeriksa lease aktif), `video_player_session.dart` (implementasi), **3 file test fake** (harus implement method baru — kesempatan sekaligus menambah test kasus di atas).

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
2. **Video A → foto**: `coord.clearActive()` → (kalau A memang keluar window, bukan sekadar jadi non-aktif tapi masih di jendela preload backward) `coord.detach(viewIdA, A)`. `clearActive()` sendiri TIDAK memanggil detach, simetris dengan poin 1.
3. **Refresh/post dihapus dari list** (pull-to-refresh, infinite-scroll replace): `detach()`/hapus dari preload window untuk SEMUA postId yang tak lagi ada di list baru **SEBELUM** `_posts`/`_visiblePosts` ditukar ke list baru — mencegah coordinator menyimpan attach/pinned entry untuk postId yang sudah tak valid di UI (kelas bug "closure-stale-list" dari §Kontrak session-factory Feed, di sini dinyatakan sebagai urutan operasional konkret).
4. **Dispose screen**: `feed_screen.dispose()` memanggil `_videoCoordinator.dispose()` SEKALI — yang secara internal men-dispose SEMUA entry sesi (`post_video_coordinator.dart:370-389`, sudah invariant coordinator: "SATU-SATUNYA pemanggil `PlaybackSession.dispose`"). `FeedVideoPostView` instance manapun (managed) TIDAK PERNAH memanggil `session.dispose()` sendiri — sudah terjamin arsitektural oleh `ownsController:false`, tapi WAJIB jadi assertion eksplisit di test migrasi (mis. spy/counter di fake session: `disposeCallCount` dari widget harus selalu 0 saat managed).

### Lingkup

1. **[PRASYARAT]** Tambah `clearActive()` di `PostVideoCoordinator` sesuai kontrak lengkap di atas + test race `setActive→clearActive`.
2. **[PRASYARAT]** Perluas `PlaybackSession` (interface + `VideoPlayerSession` + 3 fake test) dengan `beginTransientGesture(kind) → TransientGestureLease` (`lease.end()`, bukan method terpisah di session), penuhi 4 jaminan di atas. Ganti `_onLongPressStart`/`_onLongPressEnd` di `feed_video_post_view.dart` dari `ctrl.pause()/setPlaybackSpeed()` langsung ke intent lewat coordinator (simpan lease saat begin, panggil `lease.end()` saat end) saat `_managed` (bukan lagi early-return kosong).
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

1. Tambahkan `clearActive()` dengan urutan sinkron-dulu-baru-enqueue yang benar (kontrak lengkap di atas) + test race `setActive→clearActive` yang membuktikan `playCalls==0` (bukan cuma cek state akhir) + test video→foto→foreground.
2. Perluas `PlaybackSession` dengan `TransientGestureLease` (kontrak lengkap di atas) + update 3 fake test + lengkapi intent gesture managed di `feed_video_post_view.dart` + test evict-saat-gesture-aktif (`lease.isCurrent` jadi false, `end()` terlambat = no-op).
3. Pasang coordinator Feed di balik feature flag, **default OFF**, dikunci sejak screen dibuat (belum dipakai widget — PR kecil, nol perubahan perilaku user-facing). Wire RouteAware/WidgetsBindingObserver level-screen (Lingkup #7) di langkah ini juga (di balik flag yang sama).
4. Swap instansiasi `FeedVideoPostView` ke mode managed di balik flag (masih default OFF, dites internal dengan flag di-ON-kan manual). Ikuti §Urutan attach/detach/dispose #1-2 persis (attach→setActive→detach / clearActive→detach).
5. Uji matriks dengan flag ON internal: iOS/Android, WiFi/4G, Data Saver, background/lock, Feed→Profile, **DAN periksa `social_video_controller_collision`** memakai Gerbang rollout granular di atas (bukan "nol global").
6. **Nyalakan flag DEFAULT TRUE** untuk semua user (map legacy MASIH ADA di titik ini — flag tetap jadi jalur rollback kalau ada laporan regresi) — observasi masa aman (collision sesama-owner nol, audio-ganda nol, jumlah sesi konsisten ≤4 steady-state).
7. **⚠️ HANYA setelah masa observasi #6 aman:** hapus feature flag DAN infrastruktur preload manual legacy (`_preloadedControllers`/`_preloadedCachedPlayers`/`_claimPreloadedVideo`) DALAM SATU PR YANG SAMA. Titik ini adalah pergantian mekanisme rollback: SEBELUM PR ini, rollback = flip flag; SESUDAH PR ini, rollback = revert/redeploy versi sebelumnya (flag sudah tak ada, jalur legacy sudah tak ada, flip flag tak lagi bermakna apa pun). *(Versi sebelumnya dari dokumen ini salah menaruh penghapusan legacy sebagai langkah terpisah setelah "flag ON stabil" TANPA menghapus flag itu sendiri — kontradiksi yang membuat rollback mustahil di titik itu. Sudah diperbaiki di sini.)*
8. App-level registry/handoff global (Feed↔Postingan warm handoff) dikerjakan **terpisah**, hanya bila memang dibutuhkan produk — bukan bagian migrasi ini.

Tiap langkah = PR terpisah, revert-able sendiri-sendiri (via flag untuk langkah 3-6, via git revert untuk langkah 7-8), gerbang verifikasi sebelum lanjut ke langkah berikutnya.

## Estimasi & keputusan yang masih terbuka

- **Kematangan arsitektur:** v3 (dokumen ini) menutup 9 gap total dari tiga putaran review — v2: urutan rollback, gerbang collision granular, kontrak `clearActive()`, kontrak transient-gesture (keputusan Opsi A), 4 kontradiksi internal, kontrak session-factory Feed. v3: race nyata di urutan sinkron/async `clearActive()`, lease beridentitas untuk transient-gesture (analog `VideoAudioClaim`), 4 sekuens attach/detach/dispose eksplisit. Tidak ada lagi gap arsitektur yang diketahui terbuka — dua putaran review berturut-turut tidak menemukan gap baru di luar penyempurnaan poin yang sudah ada.
- **Ukuran kerja:** sedang-besar — Langkah 1-2 (kontrak API `clearActive`+lease) kini kandidat kuat untuk **review adversarial berbasis mutasi** sebelum lanjut ke langkah berikutnya, karena keduanya fondasi seluruh migrasi dan sudah terbukti dua kali menyembunyikan race/gap halus pada percobaan spesifikasi pertama (v1→v2→v3). Tetap bukan "quick patch"; 8 langkah bertahap, masing-masing PR terpisah dengan gerbang sendiri.
- **Kapan dieksekusi:** BELUM diputuskan. Dokumen ini adalah *rencana*, bukan izin eksekusi. Perlu keputusan terpisah untuk mulai Langkah 1 — termasuk mempertimbangkan apakah `feed_screen.dart`/`post_video_coordinator.dart` sedang tenang dari aktivitas paralel (Codex atau lainnya) sebelum memulai, karena sequencing 8-langkah ini butuh beberapa PR berurutan di file yang sama.
- **Siapa mengerjakan tiap langkah:** subagent-driven per langkah (pola yang sudah terbukti di sesi-sesi sebelumnya — implement→review adversarial→fix→verify), bukan satu agen mengerjakan semua langkah sekaligus. Langkah 1-2 (kontrak API) cocok diverifikasi ekstra ketat (mis. review adversarial berbasis mutasi, seperti yang dipakai sesi ini untuk kasus lain) karena keduanya jadi fondasi seluruh langkah berikutnya.
