// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// In-memory [VideoPlayerPlatform]. `manualInit` mode holds the
/// `initialized` event until [emitInitialized] is called — this lets a test
/// keep a controller "loading" while it probes the double-init guard (A4).
/// `createCount` proves how many native players were ever spun up.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({this.manualInit = false});

  final bool manualInit;
  final Map<int, StreamController<VideoEvent>> _streams = {};
  final Map<int, Duration> _positions = {};
  int _nextId = 0;
  int createCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => _create();

  Future<int?> _create() async {
    createCount++;
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    if (!manualInit) {
      stream.add(VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(720, 1280),
        duration: const Duration(seconds: 10),
      ));
    }
    return id;
  }

  /// Release the held `initialized` event for every live player.
  void emitInitialized() {
    for (final stream in _streams.values) {
      stream.add(VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(720, 1280),
        duration: const Duration(seconds: 10),
      ));
    }
  }

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}

/// Pretends nothing is cached so `cached_video_player_plus` falls straight
/// through to `VideoPlayerController.networkUrl` (our fake platform).
class _NoopCacheManager implements CacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
          {bool ignoreMemCache = false}) async =>
      null;

  @override
  Future<FileInfo> downloadFile(String url,
          {String? key, Map<String, String>? authHeaders, bool force = false}) =>
      Completer<FileInfo>().future;

  @override
  Future<void> removeFile(String key) async {}

  @override
  Future<void> emptyCache() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopMetadataStorage implements IVideoPlayerMetadataStorage {
  final Map<String, int> _store = {};

  @override
  Set<String> get keys => _store.keys.toSet();

  @override
  Future<int?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, int value) async => _store[key] = value;

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> erase() async => _store.clear();
}

FeedPost _fakeVideoPost({
  String id = 'post-1',
  double aspectRatio = 0.5625,
  bool hls = false,
}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    // HLS (.m3u8) sengaja BYPASS cache wrapper (feed_video_post_view :isHls)
    // → plain VideoPlayerController.networkUrl → langsung ke fake platform.
    // MP4 lewat CachedVideoPlayerPlus yang download-gated (tak cocok untuk
    // menguji jalur init controller di widget test).
    'videoUrl': hls
        ? 'https://example.com/$id.m3u8'
        : 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': aspectRatio,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  testWidgets('FeedVideoPostView renders without preloaded controller',
      (tester) async {
    // VisibilityDetector schedules its own throttled update Timer; under
    // FakeAsync test time that Timer can still be pending at teardown and
    // trip flutter_test's "timer still pending" assertion. Disabling the
    // throttle interval makes updates fire synchronously on paint instead.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(),
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    // pumpAndSettle can hang here — AppProductImage shimmer never settles
    // (documented flaky trap in this repo). Use a bounded pump loop instead,
    // matching the existing pattern in test/feed_post_preview_screen_test.dart.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FeedVideoPostView), findsOneWidget);
  });

  // Aturan fit ala IG Reels: video ±9:16 → cover full-bleed (crop tipis);
  // video lebih pendek (4:5 / square / landscape) → contain letterbox,
  // supaya tidak terasa "zoom". Diverifikasi lewat thumbnail background
  // (jalur pra-video), yang WAJIB mengikuti aturan yang sama dengan
  // player supaya tidak ada lompatan cover→contain saat video siap.
  Future<BoxFit?> pumpAndReadThumbFit(
      WidgetTester tester, double aspectRatio) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(aspectRatio: aspectRatio),
          isActive: false,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .where((w) => w.imageUrl.endsWith('.jpg'));
    return images.isEmpty ? null : images.first.fit;
  }

  testWidgets('video 9:16 → background cover (full-bleed ala IG)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 0.5625);
    expect(fit, BoxFit.cover);
  });

  testWidgets('video square → background contain (letterbox, bukan zoom)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 1.0);
    expect(fit, BoxFit.contain);
  });

  testWidgets('video 4:5 → background contain (letterbox, bukan zoom)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 0.8);
    expect(fit, BoxFit.contain);
  });

  // Fix A5 — handoff preload terkonfirmasi: klaim dari map pemilik hanya
  // terjadi saat state mengadopsi (initState), BUKAN tiap build parent.
  // Regresi lama: remove() di build() → rebuild parent dengan state
  // ber-key sama masih hidup menjatuhkan controller dari map tanpa pernah
  // diadopsi (yatim, tak pernah di-dispose).
  testWidgets(
      'claimPreloadedVideo dipanggil sekali di initState, '
      'tidak dipanggil ulang saat parent rebuild', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    var claimCalls = 0;
    Widget buildHost({required bool isActive}) {
      return MaterialApp(
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(),
          isActive: isActive,
          preloadedController: null,
          claimPreloadedVideo: () {
            claimCalls++;
            return null; // tidak ada preload siap — jalur fresh-init.
          },
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      );
    }

    await tester.pumpWidget(buildHost(isActive: false));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(claimCalls, 1);

    // Parent rebuild (props berubah) dengan key sama → state lama tetap
    // hidup, initState tidak jalan lagi → klaim TIDAK boleh terjadi lagi.
    await tester.pumpWidget(buildHost(isActive: true));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpWidget(buildHost(isActive: false));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(claimCalls, 1);
  });

  // ── T2 — kontrak ownsController + playbackManagedExternally, fix A1/A4 ──
  group('T2 playback contracts', () {
    late _FakeVideoPlayerPlatform fakePlatform;

    void installPlatform({bool manualInit = false}) {
      fakePlatform = _FakeVideoPlayerPlatform(manualInit: manualInit);
      VideoPlayerPlatform.instance = fakePlatform;
    }

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      // Neutralize the caching layer so the wrapper reaches our fake platform.
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
    });

    Widget host({
      required bool isActive,
      VideoPlayerController? preloaded,
      bool ownsController = true,
      bool playbackManagedExternally = false,
      ValueChanged<bool>? onVisibleChanged,
      VoidCallback? onRequestUserTogglePlay,
      VoidCallback? onRequestPause,
      VoidCallback? onRequestPlay,
    }) {
      return MaterialApp(
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true),
          isActive: isActive,
          preloadedController: preloaded,
          ownsController: ownsController,
          playbackManagedExternally: playbackManagedExternally,
          onVisibleChanged: onVisibleChanged,
          onRequestUserTogglePlay: onRequestUserTogglePlay,
          onRequestPause: onRequestPause,
          onRequestPlay: onRequestPlay,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      );
    }

    // Fix A1: video yang selesai init saat inactive lalu jadi active WAJIB
    // autoplay — bukan stuck karena _isPaused salah diturunkan dari !isPlaying.
    testWidgets('A1: init saat inactive lalu jadi active → autoplay',
        (tester) async {
      installPlatform();
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(isActive: false));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(VideoPlayer).evaluate().isNotEmpty) break;
      }
      expect(find.byType(VideoPlayer), findsWidgets,
          reason: 'video harus init walau inactive');
      final ctrl =
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
      expect(ctrl.value.isPlaying, isFalse,
          reason: 'inactive → belum diputar');

      // Jadi aktif → didUpdateWidget harus play (gate !_isPaused benar).
      await tester.pumpWidget(host(isActive: true));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (ctrl.value.isPlaying) break;
      }
      expect(ctrl.value.isPlaying, isTrue,
          reason: 'video tidak boleh stuck diam saat jadi aktif (fix A1)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // Fix A4: tap saat loading tidak boleh memulai init/controller kedua.
    testWidgets('A4: tap saat loading → satu controller / satu init',
        (tester) async {
      installPlatform(manualInit: true); // tahan initialized supaya "loading"
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(isActive: true));
      // Biarkan init dari initState mulai (create → createCount 1), tetap
      // in-flight karena initialized ditahan.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.createCount, 1,
          reason: 'init pertama membuat satu player');

      // Tap area media beberapa kali saat masih loading → _onTapMedia dgn
      // ctrl==null memanggil _maybeInitVideo lagi, harus no-op (guard A4).
      for (var t = 0; t < 3; t++) {
        await tester.tapAt(const Offset(200, 600));
        await tester.pump(const Duration(milliseconds: 350)); // lewati double-tap
      }
      expect(fakePlatform.createCount, 1,
          reason: 'tap saat loading tidak boleh memulai controller kedua (A4)');

      // Selesaikan init lalu bongkar tree bersih.
      fakePlatform.emitInitialized();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // playbackManagedExternally: VisibilityDetector + tap TIDAK menyentuh
    // controller, tapi melapor lewat callback ke coordinator (T3).
    testWidgets(
        'managed: visibilitas + tap jadi callback, controller tak disentuh',
        (tester) async {
      installPlatform();
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Controller "milik coordinator" — sudah initialized, tetap paused.
      // initialize() di-drive lewat runAsync (real async) supaya event
      // `initialized` dari fake platform terkirim; bare await di zona
      // FakeAsync testWidgets tidak pernah selesai (hang).
      final borrowed = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/managed.mp4'),
      );
      await tester.runAsync(() => borrowed.initialize());
      addTearDown(borrowed.dispose);
      expect(borrowed.value.isPlaying, isFalse);

      final visibleReports = <bool>[];
      var toggleCalls = 0;

      await tester.pumpWidget(host(
        isActive: true,
        preloaded: borrowed,
        ownsController: false,
        playbackManagedExternally: true,
        onVisibleChanged: visibleReports.add,
        onRequestUserTogglePlay: () => toggleCalls++,
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // VisibilityDetector melapor visible=true, TANPA memutar controller.
      expect(visibleReports, isNotEmpty,
          reason: 'managed → visibilitas dilaporkan via callback');
      expect(visibleReports.last, isTrue);
      expect(borrowed.value.isPlaying, isFalse,
          reason: 'managed → widget tidak play() controller langsung');

      // Tap → user-toggle callback, bukan pause/play langsung.
      await tester.tapAt(const Offset(200, 600));
      await tester.pump(const Duration(milliseconds: 350));
      expect(toggleCalls, greaterThanOrEqualTo(1),
          reason: 'managed → tap melapor userTogglePlay');
      expect(borrowed.value.isPlaying, isFalse,
          reason: 'managed → tap tidak mengubah playback controller');

      // Bongkar tree: ownsController=false → borrowed TIDAK di-dispose oleh
      // widget (dibuktikan borrowed masih usable + di-dispose oleh tearDown).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      expect(borrowed.value.isInitialized, isTrue,
          reason: 'ownsController:false → controller tidak di-dispose widget');
    });
  });
}
