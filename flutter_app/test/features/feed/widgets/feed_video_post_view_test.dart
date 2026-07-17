// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/features/feed/video/frame_output_heartbeat_service.dart';
import 'package:natalo_petshop_flutter/features/feed/video/feed_video_observation.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_playback_health_monitor.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_scrubber.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_session_store.dart';
import 'package:natalo_petshop_flutter/state/settings_store.dart';
import 'package:natalo_petshop_flutter/utils/android_back_overlays.dart';
import 'package:natalo_petshop_flutter/utils/app_route_observer.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';
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
  int playCount = 0;
  int pauseCount = 0;
  int seekCount = 0;
  int setSpeedCount = 0;
  int callsAfterDispose = 0;
  Completer<void>? setVolumeGate;
  Completer<void>? pauseGate;
  final Set<int> _disposedIds = {};
  int get disposedCount => _disposedIds.length;
  // D1: rekam setiap setVolume supaya test bisa memverifikasi controller
  // aktif mengikuti feedMuted (0/1) secara live + inactive tetap 0.
  final List<double> volumes = [];

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

  void emitBuffered(Duration end) {
    for (final stream in _streams.values) {
      stream.add(VideoEvent(
        eventType: VideoEventType.bufferingUpdate,
        buffered: [DurationRange(Duration.zero, end)],
      ));
    }
  }

  @override
  Future<void> dispose(int playerId) async {
    _disposedIds.add(playerId);
    await _streams.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    if (_disposedIds.contains(playerId)) {
      callsAfterDispose++;
      throw StateError('play after dispose');
    }
    playCount++;
  }

  @override
  Future<void> pause(int playerId) async {
    if (_disposedIds.contains(playerId)) {
      callsAfterDispose++;
      throw StateError('pause after dispose');
    }
    pauseCount++;
    await pauseGate?.future;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {
    if (_disposedIds.contains(playerId)) {
      callsAfterDispose++;
      throw StateError('volume after dispose');
    }
    final gate = setVolumeGate;
    if (gate != null) await gate.future;
    volumes.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    setSpeedCount++;
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seekCount++;
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}

/// Fake platform yang GAGAL membuat player untuk [failUntil] percobaan pertama
/// (create ke-1..failUntil lempar) lalu SUKSES sesudahnya. Dipakai T8 untuk
/// membawa [VideoPlayerSession] ke keadaan error (init awal + 1 auto-retry
/// gagal) lalu membuktikan `retry()` melahirkan controller BARU yang sukses.
class _FailThenSucceedPlatform extends VideoPlayerPlatform {
  _FailThenSucceedPlatform({
    required this.failUntil,
    this.failWithInitializeEvent = false,
    this.initializeGate,
  });

  final int failUntil;
  final bool failWithInitializeEvent;
  final Completer<void>? initializeGate;
  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _nextId = 0;
  int createCount = 0;
  int disposeCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => _create();

  Future<int?> _create() async {
    createCount++;
    final shouldFail = createCount <= failUntil;
    if (shouldFail && !failWithInitializeEvent) {
      throw Exception('network down (create #$createCount)');
    }
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    if (shouldFail) {
      stream.addError(PlatformException(
        code: 'video_init_failed',
        message: 'network down during initialization',
      ));
    } else {
      final initialized = VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(720, 1280),
        duration: const Duration(seconds: 10),
      );
      if (initializeGate == null) {
        stream.add(initialized);
      } else {
        unawaited(initializeGate!.future.then((_) {
          if (!stream.isClosed) stream.add(initialized);
        }));
      }
    }
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposeCount++;
    await _streams.remove(playerId)?.close();
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
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}

/// D4 legacy — fake platform yang gagal/sukses BERDASARKAN URL sumber
/// (bukan hitungan create): URI yang mengandung [failFragment] selalu lempar
/// (simulasi CDN 403 token basi), URI lain sukses. [uris] merekam tiap
/// create supaya test bisa membuktikan attempt-3 memakai URL SEGAR.
class _UrlAwareFailPlatform extends VideoPlayerPlatform {
  _UrlAwareFailPlatform({required this.failFragment});

  final String failFragment;
  final List<String> uris = [];
  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _nextId = 0;
  int createCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create(dataSource.uri);

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      _create(options.dataSource.uri);

  Future<int?> _create(String? uri) async {
    createCount++;
    uris.add(uri ?? '');
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    if (uri != null && uri.contains(failFragment)) {
      // Gagal via error event (BUKAN throw di create): untuk controller HLS
      // plain, throw di create membuat dispose menggantung menunggu
      // _creatingCompleter — pola sama dgn failWithInitializeEvent di
      // _FailThenSucceedPlatform.
      stream.addError(PlatformException(
        code: 'video_init_failed',
        message: '403 stale signed token ($uri)',
      ));
    } else {
      stream.add(VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(720, 1280),
        duration: const Duration(seconds: 10),
      ));
    }
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
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
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

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
          {String? key,
          Map<String, String>? authHeaders,
          bool force = false}) =>
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
  bool liked = false,
  String? videoAltText,
  String? videoUrl,
  String? thumbnailUrl,
}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    // HLS (.m3u8) sengaja BYPASS cache wrapper (feed_video_post_view :isHls)
    // → plain VideoPlayerController.networkUrl → langsung ke fake platform.
    // MP4 lewat CachedVideoPlayerPlus yang download-gated (tak cocok untuk
    // menguji jalur init controller di widget test).
    'videoUrl': videoUrl ??
        (hls ? 'https://example.com/$id.m3u8' : 'https://example.com/$id.mp4'),
    'thumbnailUrl': thumbnailUrl ?? 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': aspectRatio,
    'videoAltText': videoAltText,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'viewerLiked': liked,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void _registerLegacyFrameOutputRecoveryTests() {
  group('legacy frame-output recovery', () {
    late _FakeVideoPlayerPlatform platform;
    late StreamController<dynamic> heartbeatEvents;
    late VideoPlaybackSnapshot Function() snapshot;
    late FrameOutputStallRecover recoverFrameOutput;

    FeedVideoHealthMonitorFactory monitorFactory() => ({
          required readSnapshot,
          required onPlaybackStall,
          required onFrameOutputStall,
          required metricContext,
        }) {
          snapshot = readSnapshot;
          recoverFrameOutput = onFrameOutputStall;
          return VideoPlaybackHealthMonitor(
            readSnapshot: readSnapshot,
            onRecover: onPlaybackStall,
            onFrameOutputStallRecover: onFrameOutputStall,
            metricContext: metricContext,
            interval: const Duration(days: 1),
          );
        };

    Future<void> pumpLegacy(
      WidgetTester tester, {
      VideoPlayerController? preloaded,
      bool managed = false,
      FrameOutputHeartbeatService? heartbeatService,
      SocialVideoSessionObserver? observationObserver,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: preloaded,
          playbackManagedExternally: managed,
          ownsController: !managed,
          frameOutputHeartbeatService: heartbeatService,
          observationObserver: observationObserver,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      platform = _FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      heartbeatEvents = StreamController<dynamic>.broadcast();
      await appSettingsStore.setFeedAutoplay(true);
    });

    tearDown(() async {
      if (!heartbeatEvents.isClosed) await heartbeatEvents.close();
    });

    testWidgets('registers adopted preload once and unregisters on dispose',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final service = FrameOutputHeartbeatService(
        streamFactory: () => heartbeatEvents.stream,
      );
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/preloaded.m3u8'),
      );
      await tester.runAsync(controller.initialize);

      await pumpLegacy(tester,
          preloaded: controller, heartbeatService: service);
      heartbeatEvents.add({
        'playerId': 0,
        'textureId': 0,
        'frameCount': 7,
        'mediaTimeUs': 1000,
        'monotonicTimeUs': 2000,
        'platform': 'test',
      });
      await tester.pump();
      expect(snapshot().frameOutputCount, 7);
      expect(heartbeatEvents.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      expect(heartbeatEvents.hasListener, isFalse);
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets('adopted preload records attachment without another creation',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final observer = SocialVideoSessionObserver(enabled: true);
      final post = _fakeVideoPost(hls: true);
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/observed-preload.m3u8'),
      );
      await tester.runAsync(controller.initialize);
      observeFeedPreloadCreated(
        observer,
        postId: post.id,
        controller: controller,
      );
      observeFeedControllerInitialized(
        observer,
        postId: post.id,
        controller: controller,
        ownerId: feedPreloadOwnerId(post.id),
      );

      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: post,
          isActive: true,
          preloadedController: controller,
          observationObserver: observer,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();

      expect(
        observer.snapshot.events
            .where((event) => event.type == SocialVideoLifecycleType.created),
        hasLength(1),
      );
      expect(
        observer.snapshot.events
            .where((event) => event.type == SocialVideoLifecycleType.attached),
        hasLength(1),
      );
      expect(
        observer.snapshot.events.where(
            (event) => event.type == SocialVideoLifecycleType.initialized),
        hasLength(1),
        reason: 'ready preload was already initialized by its parent',
      );
      expect(observer.snapshot.liveControllerCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(observer.snapshot.liveControllerCount, 0);
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets(
        'HLS adopted while initializing records initialized after handoff',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final observer = SocialVideoSessionObserver(enabled: true);
      final delayedPlatform = _FakeVideoPlayerPlatform(manualInit: true);
      final volumeGate = Completer<void>();
      delayedPlatform.setVolumeGate = volumeGate;
      VideoPlayerPlatform.instance = delayedPlatform;
      final post = _fakeVideoPost(hls: true);
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/pending-adopt.m3u8'),
      );
      unawaited(controller.initialize());
      observeFeedPreloadCreated(
        observer,
        postId: post.id,
        controller: controller,
      );

      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: post,
          isActive: true,
          preloadedController: controller,
          observationObserver: observer,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();

      expect(
        observer.snapshot.events.where(
            (event) => event.type == SocialVideoLifecycleType.initialized),
        isEmpty,
      );

      delayedPlatform.emitInitialized();
      await tester.pump();
      volumeGate.complete();
      await tester.pump();

      expect(
        observer.snapshot.events.where(
            (event) => event.type == SocialVideoLifecycleType.initialized),
        hasLength(1),
      );
      expect(observer.snapshot.liveControllerCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(observer.snapshot.liveControllerCount, 0);
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets('local controller records create initialize and final dispose',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final observer = SocialVideoSessionObserver(enabled: true);

      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          observationObserver: observer,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(
        observer.snapshot.events.map((event) => event.type),
        containsAllInOrder(<SocialVideoLifecycleType>[
          SocialVideoLifecycleType.created,
          SocialVideoLifecycleType.initialized,
        ]),
      );
      expect(observer.snapshot.liveControllerCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(observer.snapshot.events.last.type,
          SocialVideoLifecycleType.disposed);
      expect(observer.snapshot.liveControllerCount, 0);
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets('MP4 cache failure retries without a pre-init controller read',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final observer = SocialVideoSessionObserver(enabled: true);
      final retryPlatform = _FailThenSucceedPlatform(failUntil: 1);
      VideoPlayerPlatform.instance = retryPlatform;
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();

      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: false),
          isActive: true,
          preloadedController: null,
          observationObserver: observer,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(retryPlatform.createCount, 2);
      expect(
        observer.snapshot.events.map((event) => event.type),
        containsAllInOrder(<SocialVideoLifecycleType>[
          SocialVideoLifecycleType.created,
          SocialVideoLifecycleType.initialized,
        ]),
      );
      expect(observer.snapshot.liveControllerCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(observer.snapshot.liveControllerCount, 0);
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets('failed HLS attempt leaves no live observed identity',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final observer = SocialVideoSessionObserver(enabled: true);
      final retryPlatform = _FailThenSucceedPlatform(
        failUntil: 2,
        failWithInitializeEvent: true,
      );
      VideoPlayerPlatform.instance = retryPlatform;

      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          observationObserver: observer,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();
      await tester.pump();
      for (var i = 0;
          i < 20 &&
              observer.snapshot.events
                  .where(
                      (event) => event.type == SocialVideoLifecycleType.failed)
                  .isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        observer.snapshot.events
            .where((event) => event.type == SocialVideoLifecycleType.failed),
        hasLength(1),
      );
      expect(observer.snapshot.liveControllerCount, 0);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets('disposed local init never emits initialized after completion',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final observer = SocialVideoSessionObserver(enabled: true);
      final initializedGate = Completer<void>();
      VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();

      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          observationObserver: observer,
          beforeObserveInitialized: () => initializedGate.future,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();
      expect(
        observer.snapshot.events
            .where((event) => event.type == SocialVideoLifecycleType.created),
        hasLength(1),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      initializedGate.complete();
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(
        observer.snapshot.events.where(
            (event) => event.type == SocialVideoLifecycleType.initialized),
        isEmpty,
      );
      expect(observer.snapshot.liveControllerCount, 0);
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets('pending MP4 local init disposes controller after it settles',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      final observer = SocialVideoSessionObserver(enabled: true);
      final initializeGate = Completer<void>();
      final delayedPlatform = _FailThenSucceedPlatform(
        failUntil: 0,
        initializeGate: initializeGate,
      );
      VideoPlayerPlatform.instance = delayedPlatform;
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();

      await tester.pumpWidget(MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: false),
          isActive: true,
          preloadedController: null,
          observationObserver: observer,
          healthMonitorFactory: monitorFactory(),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(delayedPlatform.disposeCount, 0);

      initializeGate.complete();
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(delayedPlatform.disposeCount, 1);
      expect(
        observer.snapshot.events.where(
            (event) => event.type == SocialVideoLifecycleType.initialized),
        isEmpty,
      );
      expect(observer.snapshot.liveControllerCount, 0);
      await appSettingsStore.setFeedAutoplay(true);
    });

    testWidgets('attempts recover once, rebuild, and preserve timestamp',
        (tester) async {
      final observer = SocialVideoSessionObserver(enabled: true);
      await pumpLegacy(tester, observationObserver: observer);
      final initialCreates = platform.createCount;
      final playBefore = platform.playCount;

      await tester.runAsync(
        () => recoverFrameOutput(const Duration(seconds: 3), 1),
      );
      expect(platform.pauseCount, greaterThan(0));
      expect(platform.seekCount, greaterThan(0));
      expect(platform.playCount, greaterThan(playBefore));

      await tester.runAsync(
        () => recoverFrameOutput(const Duration(seconds: 4), 2),
      );
      await tester.pump();
      expect(platform.createCount, initialCreates + 1);
      expect(platform.disposedCount, 1);
      expect(snapshot().position, const Duration(seconds: 4));
      expect(snapshot().playbackDiscontinuitySequence, greaterThan(1));
      expect(
        observer.snapshot.events
            .where((event) => event.type == SocialVideoLifecycleType.created),
        hasLength(2),
      );
      expect(
        observer.snapshot.events
            .where((event) => event.type == SocialVideoLifecycleType.disposed),
        hasLength(1),
      );
      expect(observer.snapshot.liveControllerCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(observer.snapshot.liveControllerCount, 0);
    });

    testWidgets(
        'attempt 1 cannot overwrite a user scrub while pause is pending',
        (tester) async {
      await pumpLegacy(tester);
      platform.pauseGate = Completer<void>();
      final recovery = recoverFrameOutput(const Duration(seconds: 2), 1);
      await tester.pump();

      expect(find.byType(FeedVideoScrubber), findsOneWidget);
      await tester.drag(
        find.byType(FeedVideoScrubber),
        const Offset(120, 0),
        warnIfMissed: false,
      );
      await tester.pump();
      final userPosition = snapshot().position;
      expect(userPosition, isNot(const Duration(seconds: 2)));

      platform.pauseGate!.complete();
      await tester.runAsync(() => recovery);
      await tester.pump();
      expect(snapshot().position, userPosition);
    });

    testWidgets('managed controller never registers a local heartbeat route',
        (tester) async {
      final service = FrameOutputHeartbeatService(
        streamFactory: () => heartbeatEvents.stream,
      );
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/managed.m3u8'),
      );
      await tester.runAsync(controller.initialize);

      await pumpLegacy(tester,
          preloaded: controller, managed: true, heartbeatService: service);
      expect(heartbeatEvents.hasListener, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.dispose);
    });

    testWidgets('suppresses paused or covered recovery and post-dispose races',
        (tester) async {
      await pumpLegacy(tester);
      final media = find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onDoubleTap != null,
      );
      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 400));
      final pausedPauses = platform.pauseCount;
      final pausedSeeks = platform.seekCount;
      await tester.runAsync(
        () => recoverFrameOutput(const Duration(seconds: 1), 1),
      );
      expect(platform.pauseCount, pausedPauses);
      expect(platform.seekCount, pausedSeeks);

      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 400));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final pauses = platform.pauseCount;
      final seeks = platform.seekCount;
      await tester.runAsync(
        () => recoverFrameOutput(const Duration(seconds: 2), 1),
      );
      expect(platform.pauseCount, pauses);
      expect(platform.seekCount, seeks);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => recoverFrameOutput(const Duration(seconds: 5), 2),
      );
      expect(platform.createCount, 1);
      expect(platform.callsAfterDispose, 0);
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(frameOutputHeartbeatChannelName, (message) async {
    return const StandardMethodCodec().encodeSuccessEnvelope(null);
  });
  _registerLegacyFrameOutputRecoveryTests();
  testWidgets('comment action raises the embedded drawer', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    await appSettingsStore.setFeedAutoplay(false);
    addTearDown(() => appSettingsStore.setFeedAutoplay(true));

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(id: 'comment-drawer-regression', hls: true),
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.takeException(), isNull);
    expect(find.byType(FeedCommentSheet), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(FeedCommentSheet)).dy,
      lessThan(tester.view.physicalSize.height),
    );
  });

  testWidgets('comment drawer consumes double back while closing and reopens',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    resetAndroidBackOverlays();
    addTearDown(resetAndroidBackOverlays);
    await appSettingsStore.setFeedAutoplay(false);
    addTearDown(() => appSettingsStore.setFeedAutoplay(true));

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(id: 'comment-double-back', hls: true),
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byType(FeedCommentSheet), findsOneWidget);

    expect(consumeAndroidBackOverlay(), isTrue);
    expect(consumeAndroidBackOverlay(), isTrue,
        reason: 'closing retains Android back ownership');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(FeedCommentSheet), findsNothing);
    expect(consumeAndroidBackOverlay(), isFalse);

    await tester.tap(find.bySemanticsLabel('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byType(FeedCommentSheet), findsOneWidget);

    expect(consumeAndroidBackOverlay(), isTrue);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.byType(FeedCommentSheet), findsNothing);
  });

  // Terminal-state design: pointer cancel di handle = release velocity nol,
  // dan sesi drawer hanya menyimpan detent valid (initial/expanded) — bukan
  // partial extent live-tracking di band terlarang [dismiss, initial).
  testWidgets(
      'video drawer: drag-cancel settle ke initial + sesi hanya menyimpan '
      'detent valid', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    feedCommentSessionStore.clear();
    addTearDown(feedCommentSessionStore.clear);
    await appSettingsStore.setFeedAutoplay(false);
    addTearDown(() => appSettingsStore.setFeedAutoplay(true));

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(id: 'comment-cancel-session', hls: true),
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byType(FeedCommentSheet), findsOneWidget);
    final initialTop = tester.getTopLeft(find.byType(FeedCommentSheet)).dy;

    // Tarik handle turun ~15% layar (extent ~0.45 — band terlarang), TAHAN.
    final handle = find.byKey(const ValueKey('feed-comment-drag-handle'));
    final screenHeight = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, screenHeight * 0.025));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Mid-drag di band terlarang: sesi TIDAK boleh menyimpan partial extent.
    final session = feedCommentSessionStore.sessionFor(
      viewerId: 'guest',
      postId: 'comment-cancel-session',
    );
    final storedMidDrag = session.sheetExtent;
    expect(
      storedMidDrag == null ||
          (storedMidDrag - feedCommentInitialExtent).abs() <= 0.02 ||
          storedMidDrag >= 0.9,
      isTrue,
      reason: 'sesi wajib berisi detent valid, bukan partial '
          '(tersimpan: $storedMidDrag)',
    );

    // Cancel (bukan release): wajib settle balik TEPAT ke initial.
    await gesture.cancel();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(FeedCommentSheet), findsOneWidget,
        reason: 'cancel di atas dismiss → resting state = initial');
    expect(
      tester.getTopLeft(find.byType(FeedCommentSheet)).dy,
      closeTo(initialTop, 2),
      reason: 'extent wajib kembali ke detent initial setelah cancel',
    );
  });

  testWidgets('deactivation and dispose force-clean comment drawer lifecycle',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    resetAndroidBackOverlays();
    addTearDown(resetAndroidBackOverlays);
    await appSettingsStore.setFeedAutoplay(false);
    addTearDown(() => appSettingsStore.setFeedAutoplay(true));
    final overlayStates = <bool>[];
    final pauseReasons = <CoverPauseReason>[];
    var playRequests = 0;
    final active = ValueNotifier<bool>(true);
    addTearDown(active.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, isActive, _) => FeedVideoPostView(
            key: const ValueKey('lifecycle-comment-view'),
            post: _fakeVideoPost(id: 'comment-lifecycle', hls: true),
            isActive: isActive,
            preloadedController: null,
            ownsController: false,
            playbackManagedExternally: true,
            onOverlayStateChanged: overlayStates.add,
            onMediaZoomChanged: (_) {},
            onRequestPause: pauseReasons.add,
            onRequestPlay: () => playRequests++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 320));
    expect(overlayStates, [true]);

    active.value = false;
    await tester.pump();
    expect(find.byType(FeedCommentSheet), findsNothing);
    expect(overlayStates, [true, false]);
    expect(consumeAndroidBackOverlay(), isFalse);
    expect(pauseReasons, isEmpty);
    expect(playRequests, 0,
        reason: 'an initial-height drawer did not own a playback pause');

    active.value = true;
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byType(FeedCommentSheet), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('feed-comment-drag-handle')),
      const Offset(0, -380),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(pauseReasons, [CoverPauseReason.commentSheetFull]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(overlayStates, [true, false, true, false]);
    expect(playRequests, 1,
        reason: 'forced cleanup releases only the pause the drawer acquired');
    expect(consumeAndroidBackOverlay(), isFalse);
  });

  testWidgets('delayed preload claim blocks concurrent local initialization',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    await appSettingsStore.setFeedAutoplay(false);
    addTearDown(() => appSettingsStore.setFeedAutoplay(true));

    final parentController = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/delayed-parent.m3u8'),
    );
    await tester.runAsync(parentController.initialize);
    final delayedClaim = Completer<PreloadedVideoClaim?>();
    final ownership = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          claimPreloadedVideo: () => delayedClaim.future,
          onLocalOwnershipChanged: ownership.add,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(platform.createCount, 1,
        reason: 'only the parent controller exists while claim is pending');
    expect(ownership, isEmpty);

    delayedClaim.complete(PreloadedVideoClaim(
      controller: parentController,
      cachedPlayer: null,
    ));
    await tester.pump();
    await tester.pump();

    expect(platform.createCount, 1,
        reason: 'adoption must not race a second local controller');
    expect(ownership, [true]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(ownership, [true, false]);
  });

  testWidgets(
      'mounted inactive neighbor stays pending and adopts parent preload',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final ownership = <bool>[];
    PreloadedVideoClaim? readyClaim;

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: false,
          preloadedController: null,
          claimPreloadedVideo: () {
            final claim = readyClaim;
            readyClaim = null;
            return claim;
          },
          preloadListenable: revision,
          onLocalOwnershipChanged: ownership.add,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(platform.createCount, 0,
        reason: 'inactive mounted PageView neighbor must not local-init');
    expect(ownership, isEmpty, reason: 'pending is not ownership');

    final parentController = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/neighbor-parent.m3u8'),
    );
    await tester.runAsync(parentController.initialize);
    readyClaim = PreloadedVideoClaim(
      controller: parentController,
      cachedPlayer: null,
    );
    revision.value++;
    await tester.pump();

    expect(platform.createCount, 1);
    expect(ownership, [true], reason: 'ownership starts only after adoption');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(ownership, [true, false]);
  });

  testWidgets(
      'late preload is not claimed while committed local init is pending',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform(manualInit: true);
    VideoPlayerPlatform.instance = platform;
    await appSettingsStore.setFeedAutoplay(true);
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    var claimCalls = 0;
    final ownership = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          claimPreloadedVideo: () {
            claimCalls++;
            return null;
          },
          preloadListenable: revision,
          onLocalOwnershipChanged: ownership.add,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(platform.createCount, 1);
    expect(claimCalls, 1, reason: 'initial claim happens before local init');
    expect(ownership, isEmpty, reason: 'initializing is not ownership yet');

    revision.value++;
    await tester.pump();
    expect(claimCalls, 1,
        reason: 'late notifier must not steal/claim during local init');

    platform.emitInitialized();
    await tester.pump(const Duration(milliseconds: 20));
    expect(ownership, [true]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('local ownership ignores late preload notifier without claiming',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    await appSettingsStore.setFeedAutoplay(false);
    addTearDown(() => appSettingsStore.setFeedAutoplay(true));

    final local = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/local.m3u8'),
    );
    final late = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/late.m3u8'),
    );
    await tester.runAsync(() async {
      await local.initialize();
      await late.initialize();
    });
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final ownership = <bool>[];
    var claimCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: false,
          preloadedController: local,
          claimPreloadedVideo: () {
            claimCount++;
            return PreloadedVideoClaim(
              controller: claimCount == 1 ? local : late,
              cachedPlayer: null,
            );
          },
          preloadListenable: revision,
          onLocalOwnershipChanged: ownership.add,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(ownership, [true]);

    final before = platform.disposedCount;
    final claimsBefore = claimCount;
    revision.value++;
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(claimCount, claimsBefore);
    expect(platform.disposedCount, before,
        reason: 'unclaimed preload remains the parent responsibility');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(ownership, [true, false]);
  });

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

  testWidgets('media surface exposes explicit alt text semantics',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(
            videoAltText: 'Kucing putih sedang makan dari mangkuk biru',
          ),
          isActive: false,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.bySemanticsLabel('Kucing putih sedang makan dari mangkuk biru'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // Framing imersif ala IG/Reels: media (video/thumbnail) selalu penuhi
  // LEBAR layar (`fitWidth`) supaya tidak terasa "zoom" pada media yang
  // lebih lebar dari 9:16, dan rata ATAS (`Alignment.topCenter`) supaya
  // video mulai penuh dari tepi atas seperti IG — sisa ruang jatuh di
  // bawah sebagai area hitam (latar dasar), TANPA blurred backdrop.
  // Diverifikasi lewat thumbnail background (jalur pra-video) yang WAJIB
  // memakai framing yang sama dengan player supaya tidak ada lompatan saat
  // video siap.
  Future<BoxFit?> pumpAndReadThumbFit(WidgetTester tester, double aspectRatio,
      {Size viewport = const Size(393, 852)}) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: viewport),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: aspectRatio),
            isActive: false,
            preloadedController: null,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .where((w) => w.imageUrl.endsWith('.jpg'));
    return images.isEmpty ? null : images.last.fit;
  }

  Future<Alignment?> pumpAndReadThumbAlign(
      WidgetTester tester, double aspectRatio,
      {Size viewport = const Size(393, 852)}) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: viewport),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: aspectRatio),
            isActive: false,
            preloadedController: null,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .where((w) => w.imageUrl.endsWith('.jpg'));
    return images.isEmpty ? null : images.last.alignment as Alignment?;
  }

  testWidgets('video 9:16 → foreground fitWidth (isi penuh tanpa zoom)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 9 / 16,
        viewport: const Size(393, 852));
    expect(fit, BoxFit.fitWidth);
  });

  testWidgets('video square → foreground fitWidth (bukan zoom)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 1.0);
    expect(fit, BoxFit.fitWidth);
  });

  testWidgets('video 4:5 → foreground fitWidth (bukan zoom)', (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 0.8);
    expect(fit, BoxFit.fitWidth);
  });

  testWidgets('video portrait sangat tinggi → foreground fitWidth',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 0.4);
    expect(fit, BoxFit.fitWidth);
  });

  testWidgets('video landscape 16:9 → foreground fitWidth', (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 16 / 9);
    expect(fit, BoxFit.fitWidth);
  });

  testWidgets('media rata atas (topCenter) — mulai penuh dari atas ala IG',
      (tester) async {
    final align = await pumpAndReadThumbAlign(tester, 0.8);
    expect(align, Alignment.topCenter);
  });

  testWidgets('thumbnail and initialized player share fitWidth framing',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;

    // Metadata invalid tetap memakai framing fitWidth yang sama dengan
    // controller ter-inisialisasi.
    final thumbnailFit =
        await pumpAndReadThumbFit(tester, 0, viewport: const Size(393, 852));
    expect(thumbnailFit, BoxFit.fitWidth);

    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/fallback.m3u8'),
    );
    await controller.initialize();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: 0, hls: true),
            isActive: true,
            preloadedController: controller,
            ownsController: true,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Satu FittedBox media (tanpa backdrop): fitWidth + rata atas.
    final fittedBox =
        tester.widgetList<FittedBox>(find.byType(FittedBox)).last;
    expect(fittedBox.fit, BoxFit.fitWidth);
    expect(fittedBox.alignment, Alignment.topCenter);
  });

  testWidgets(
      'main Feed uses one top-aligned cover thumbnail without blurred backdrop',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: 9 / 16),
            isActive: false,
            preloadedController: null,
            framing: FeedVideoFraming.mainFeed,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final thumbnails = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .where((image) => image.imageUrl.endsWith('.jpg'))
        .toList();
    expect(thumbnails, hasLength(1));
    expect(thumbnails.single.fit, BoxFit.cover);
    expect(thumbnails.single.alignment, Alignment.topCenter);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('fullscreen Feed uses one top-aligned cover thumbnail',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(bottom: 34),
        ),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: 9 / 16),
            isActive: false,
            preloadedController: null,
            framing: FeedVideoFraming.fullscreenFeed,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final thumbnails = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .where((image) => image.imageUrl.endsWith('.jpg'))
        .toList();
    expect(thumbnails, hasLength(1));
    expect(thumbnails.single.fit, BoxFit.cover);
    expect(thumbnails.single.alignment, Alignment.topCenter);

    final mediaViewport = tester.widget<Positioned>(
      find.byKey(const ValueKey('feed-video-media-viewport')),
    );
    expect(mediaViewport.top, 0);
    expect(mediaViewport.bottom, 0);
  });

  testWidgets('main Feed initialized player shares cover topCenter framing',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/main-feed.m3u8'),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: 9 / 16, hls: true),
            isActive: true,
            preloadedController: controller,
            framing: FeedVideoFraming.mainFeed,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final mediaFittedBoxes = tester.widgetList<FittedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('feed-video-media-viewport')),
        matching: find.byType(FittedBox),
      ),
    );
    expect(mediaFittedBoxes, isNotEmpty);
    expect(mediaFittedBoxes.last.fit, BoxFit.cover);
    expect(mediaFittedBoxes.last.alignment, Alignment.topCenter);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('feed-video-media-viewport')),
        matching: find.byType(ImageFiltered),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'fullscreen Feed initialized player shares cover topCenter framing',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/fullscreen-feed.m3u8'),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(bottom: 34),
        ),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: 9 / 16, hls: true),
            isActive: true,
            preloadedController: controller,
            framing: FeedVideoFraming.fullscreenFeed,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final mediaFittedBoxes = tester.widgetList<FittedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('feed-video-media-viewport')),
        matching: find.byType(FittedBox),
      ),
    );
    expect(mediaFittedBoxes, isNotEmpty);
    expect(mediaFittedBoxes.last.fit, BoxFit.cover);
    expect(mediaFittedBoxes.last.alignment, Alignment.topCenter);
  });

  testWidgets('main Feed media stops at the bottom navigation inset',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(bottom: 100),
        ),
        child: MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(aspectRatio: 9 / 16),
            isActive: false,
            preloadedController: null,
            framing: FeedVideoFraming.mainFeed,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final mediaViewport = tester.widget<Positioned>(
      find.byKey(const ValueKey('feed-video-media-viewport')),
    );
    expect(mediaViewport.top, 0);
    expect(mediaViewport.bottom, 100);
  });

  // Fix A5 — handoff preload terkonfirmasi: klaim dari map pemilik hanya
  // terjadi saat state mengadopsi (initState), BUKAN tiap build parent.
  // Regresi lama: remove() di build() → rebuild parent dengan state
  // ber-key sama masih hidup menjatuhkan controller dari map tanpa pernah
  // diadopsi (yatim, tak pernah di-dispose).
  testWidgets(
      'activation retries atomic preload claim without rebuilding state',
      (tester) async {
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

    // Activation retries the atomic claim before committing local init.
    await tester.pumpWidget(buildHost(isActive: true));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpWidget(buildHost(isActive: false));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(claimCalls, 2);
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
      bool liked = false,
      ValueChanged<bool>? onVisibleChanged,
      VoidCallback? onRequestUserTogglePlay,
      ValueChanged<CoverPauseReason>? onRequestPause,
      VoidCallback? onRequestPlay,
    }) {
      return MaterialApp(
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true, liked: liked),
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

    testWidgets(
        'A1: inactive stays pending; activation initializes + autoplays',
        (tester) async {
      installPlatform();
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(isActive: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(VideoPlayer), findsNothing,
          reason: 'inactive neighbor remains available for parent preload');

      await tester.pumpWidget(host(isActive: true));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(VideoPlayer).evaluate().isEmpty) continue;
        final ctrl = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer).first)
            .controller;
        if (ctrl.value.isPlaying) break;
      }
      final ctrl =
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
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
        await tester
            .pump(const Duration(milliseconds: 350)); // lewati double-tap
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
        liked: true,
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

      // Double-tap → like saja. Gesture arena harus membatalkan single-tap,
      // jadi playback tidak sempat pause lalu resume.
      await tester.tapAt(const Offset(200, 600));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(200, 600));
      await tester.pump(const Duration(milliseconds: 350));
      expect(toggleCalls, 0,
          reason: 'double-tap like tidak boleh menyentuh playback');

      // Single tap → user-toggle callback, bukan pause/play langsung.
      await tester.tapAt(const Offset(200, 600));
      await tester.pump(const Duration(milliseconds: 350));
      expect(toggleCalls, 1, reason: 'managed → tap melapor userTogglePlay');
      expect(borrowed.value.isPlaying, isFalse,
          reason: 'managed → tap tidak mengubah playback controller');

      // Bongkar tree: ownsController=false → borrowed TIDAK di-dispose oleh
      // widget (dibuktikan borrowed masih usable + di-dispose oleh tearDown).
      await tester.pumpWidget(const SizedBox());
      // Double-tap intentionally exercises the like path. In widget tests the
      // API is unavailable, so its warning toast owns a delayed-dismiss timer;
      // drain it explicitly before invariant verification.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(borrowed.value.isInitialized, isTrue,
          reason: 'ownsController:false → controller tidak di-dispose widget');
    });

    // FIX 1 (T2 review): scrubber di managed mode TIDAK boleh play/pause
    // controller pinjaman — hanya seek. Cegah race scrub-pause → background
    // → lepas scrub → play() menembus suspend = audio hantu.
    testWidgets('managed: scrub drag TIDAK memanggil controller play/pause',
        (tester) async {
      installPlatform();
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final borrowed = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/managed-scrub.mp4'),
      );
      await tester.runAsync(() => borrowed.initialize());
      await tester.runAsync(() => borrowed.play());
      addTearDown(borrowed.dispose);
      expect(borrowed.value.isPlaying, isTrue);

      await tester.pumpWidget(host(
        isActive: true,
        preloaded: borrowed,
        ownsController: false,
        playbackManagedExternally: true,
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(FeedVideoScrubber), findsOneWidget,
          reason: 'scrubber harus ter-render untuk controller aktif');

      final playBefore = fakePlatform.playCount;
      final pauseBefore = fakePlatform.pauseCount;

      // Drag horizontal di scrubber (start → update → end).
      await tester.drag(
        find.byType(FeedVideoScrubber),
        const Offset(120, 0),
        warnIfMissed: false,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(fakePlatform.pauseCount, pauseBefore,
          reason: 'managed → scrub start tidak boleh pause controller');
      expect(fakePlatform.playCount, playBefore,
          reason: 'managed → scrub end tidak boleh play/resume controller');
      expect(borrowed.value.isPlaying, isTrue,
          reason: 'managed → video tetap jalan saat scrub (seek-only)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // FIX 2 (T2 review): long-press peek-pause / 2x-speed di managed mode
    // di-nonaktifkan — tak ada ctrl.pause/play/setPlaybackSpeed langsung.
    testWidgets(
        'managed: long-press TIDAK memanggil play/pause/setPlaybackSpeed',
        (tester) async {
      installPlatform();
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final borrowed = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/managed-lp.mp4'),
      );
      await tester.runAsync(() => borrowed.initialize());
      await tester.runAsync(() => borrowed.play());
      addTearDown(borrowed.dispose);
      expect(borrowed.value.isPlaying, isTrue);

      await tester.pumpWidget(host(
        isActive: true,
        preloaded: borrowed,
        ownsController: false,
        playbackManagedExternally: true,
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final playBefore = fakePlatform.playCount;
      final pauseBefore = fakePlatform.pauseCount;
      final speedBefore = fakePlatform.setSpeedCount;

      // Long-press center (pause zone) lalu release.
      await tester.longPressAt(const Offset(200, 600));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(fakePlatform.pauseCount, pauseBefore,
          reason: 'managed → long-press tidak boleh pause controller');
      expect(fakePlatform.playCount, playBefore,
          reason: 'managed → long-press release tidak boleh play controller');
      expect(fakePlatform.setSpeedCount, speedBefore,
          reason: 'managed → long-press tidak boleh setPlaybackSpeed (nol 2x)');
      expect(borrowed.value.isPlaying, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // FIX 3 (T2 review, gap D5): onRequestPause membawa CoverPauseReason yang
    // benar dari sumber berbeda — routePush (route opaque didorong) vs
    // appBackground (lifecycle). T3 pakai reason untuk drop routePush saat
    // handoff.
    testWidgets('managed: onRequestPause membawa reason sesuai sumber',
        (tester) async {
      installPlatform();
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final reasons = <CoverPauseReason>[];
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          ownsController: false,
          playbackManagedExternally: true,
          onRequestPause: reasons.add,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Sumber 1: push route opaque → didPushNext → reason routePush.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(reasons, contains(CoverPauseReason.routePush),
          reason:
              'route opaque didorong → reason routePush (T3 drop saat handoff)');
      expect(reasons.last, CoverPauseReason.routePush);

      // Sumber 2: app ke background → lifecycle → reason appBackground.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(reasons.last, CoverPauseReason.appBackground,
          reason: 'app background → reason appBackground (T3 pauseAll)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  // ── BLOCKER — audio hantu: guard isActive di managed _resumeFromCover ──
  // Di fullscreen, view ORIGIN yang sudah di-swipe-lewati tetap MOUNTED tapi
  // isActive:false. Coordinator.activePostId nyangkut di origin (sibling tak
  // pernah setActive). Resume apa pun (app-foreground / didPopNext) di view
  // origin mounted-inactive TIDAK boleh minta onRequestPlay → resumeAll,
  // karena itu memutar origin tersembunyi di belakang sibling = dua suara.
  group('BLOCKER managed resume guard (audio hantu)', () {
    late _FakeVideoPlayerPlatform fakePlatform;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
      fakePlatform = _FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = fakePlatform;
    });

    Widget host({
      required bool isActive,
      required List<void> playCalls,
      required List<CoverPauseReason> pauseCalls,
    }) {
      return MaterialApp(
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true),
          isActive: isActive,
          preloadedController: null,
          ownsController: false,
          playbackManagedExternally: true,
          onRequestPause: pauseCalls.add,
          onRequestPlay: () => playCalls.add(null),
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      );
    }

    testWidgets(
        'managed inactive: app-resume TIDAK memanggil onRequestPlay '
        '(origin di belakang sibling)', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final playCalls = <void>[];
      final pauseCalls = <CoverPauseReason>[];
      await tester.pumpWidget(
          host(isActive: false, playCalls: playCalls, pauseCalls: pauseCalls));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // App ke background lalu foreground → _resumeFromCover (managed).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(playCalls, isEmpty,
          reason: 'view mounted-inactive TIDAK boleh minta resume '
              '(cegah audio hantu origin di belakang sibling)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets(
        'managed active: app-resume MEMANGGIL onRequestPlay (kasus benar)',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final playCalls = <void>[];
      final pauseCalls = <CoverPauseReason>[];
      await tester.pumpWidget(
          host(isActive: true, playCalls: playCalls, pauseCalls: pauseCalls));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(playCalls, isNotEmpty,
          reason: 'origin AKTIF + foreground → resume benar (onRequestPlay)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  // ── D1 — mute LIVE di Feed utama (jalur non-managed/legacy) ──
  // Controller feed yang SUDAH hidup harus ikut perubahan feedMuted secara
  // live (§2.2): HANYA controller AKTIF yang naik ke volume 1 saat unmute
  // global; controller inactive/background TETAP volume 0.
  group('D1 mute live (non-managed)', () {
    late _FakeVideoPlayerPlatform fakePlatform;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
      fakePlatform = _FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = fakePlatform;
    });

    Widget host({
      required bool isActive,
      required VideoPlayerController preloaded,
    }) {
      return MaterialApp(
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true),
          isActive: isActive,
          preloadedController: preloaded,
          // Jalur legacy: default ownsController:true, managed:false.
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      );
    }

    testWidgets('post aktif tanpa audio claim: unmute live tetap volume 0',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Autoplay OFF berarti view tidak eligible dan tidak memegang claim.
      // Unmute global tidak boleh menaikkan volume tanpa claim aktif.
      await appSettingsStore.setFeedAutoplay(false);
      addTearDown(() => appSettingsStore.setFeedAutoplay(true));
      // Mulai dari state diketahui.
      await appSettingsStore.setFeedMuted(true);

      final borrowed = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/d1-active.mp4'),
      );
      await tester.runAsync(() => borrowed.initialize());
      // ownsController default true → widget yang men-dispose borrowed saat
      // unmount (jangan addTearDown dispose = double-dispose).

      await tester.pumpWidget(host(isActive: true, preloaded: borrowed));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Isolasi dari volume adopt-time — uji hanya efek transisi live.
      fakePlatform.volumes.clear();

      // Sudah muted → set false = unmute global saat controller SUDAH hidup.
      await appSettingsStore.setFeedMuted(false);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.volumes.last, 0,
          reason: 'tanpa claim audio, unmute live tetap volume 0');

      fakePlatform.volumes.clear();
      // Mute global lagi → controller aktif turun ke 0 secara live.
      await appSettingsStore.setFeedMuted(true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.volumes.last, 0,
          reason: 'post aktif mute live → setVolume(0)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets(
        'post TIDAK aktif: unmute global TIDAK menaikkan volume (tetap 0)',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Mulai muted.
      await appSettingsStore.setFeedMuted(true);

      final borrowed = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/d1-inactive.mp4'),
      );
      await tester.runAsync(() => borrowed.initialize());

      await tester.pumpWidget(host(isActive: false, preloaded: borrowed));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Isolasi dari volume adopt-time.
      fakePlatform.volumes.clear();

      // Unmute global sementara post ini TIDAK aktif → volume TIDAK boleh naik
      // ke 1 (unmute tak boleh membocorkan audio video background).
      await appSettingsStore.setFeedMuted(false);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.volumes.contains(1), isFalse,
          reason: 'post inactive → unmute global tidak menaikkan volume ke 1');
      expect(fakePlatform.volumes.last, 0,
          reason: 'post inactive tetap senyap (volume 0)');

      // Rapikan state global untuk test lain.
      await appSettingsStore.setFeedMuted(true);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  testWidgets(
      'legacy delayed volume cannot play or touch platform after dispose',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    await appSettingsStore.setFeedAutoplay(true);
    await appSettingsStore.setFeedMuted(false);

    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/legacy-dispose.mp4'),
    );
    await tester.runAsync(() => controller.initialize());
    platform.setVolumeGate = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: controller,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    platform.setVolumeGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(platform.playCount, 0,
        reason: 'disposed generation must fail before stale play');
    expect(platform.callsAfterDispose, 0,
        reason: 'cleanup errors are contained before reaching native calls');
    await appSettingsStore.setFeedMuted(true);
  });

  testWidgets('reports low-frequency contiguous buffer ahead while active',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/buffer-report.mp4'),
    );
    await tester.runAsync(controller.initialize);
    final reports = <Duration>[];

    Widget host(bool active) => MaterialApp(
          home: FeedVideoPostView(
            post: _fakeVideoPost(hls: true),
            isActive: active,
            preloadedController: controller,
            onBufferAheadChanged: reports.add,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        );

    await tester.pumpWidget(host(true));
    await tester.pump();
    platform.emitBuffered(const Duration(milliseconds: 2500));
    await tester.pump();
    platform.emitBuffered(const Duration(milliseconds: 3200));
    await tester.pump();

    expect(reports, contains(const Duration(milliseconds: 3200)));
    final activeReportCount = reports.length;

    await tester.pumpWidget(host(false));
    platform.emitBuffered(const Duration(seconds: 5));
    await tester.pump();
    expect(reports.length, activeReportCount);
  });

  // ── T8 — retry di fullscreen (managed view) ──
  // Saat sesi coordinator ERROR di managed view: tampil surface error +
  // tombol "Coba lagi" → session.retry() (reset budget). Retry mengganti
  // controller DI DALAM sesi yang sama (identitas sesi tetap, revision bump)
  // → view WAJIB re-adopt controller BARU via listener REVISION (bukan
  // registry) dan merender langsung, tanpa kembali ke Postingan. Widget tak
  // pernah men-dispose controller (coordinator pemilik).
  group('T8 retry di fullscreen (managed)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      // Thumbnail post → CachedNetworkImage → flutter_cache_manager →
      // path_provider — tanpa stub ini, MissingPluginException muncul
      // ASYNC SETELAH tes selesai (getApplicationSupportDirectory/
      // getTemporaryDirectory) dan bikin tes gagal walau assertion-nya
      // sendiri lulus. Pola sama dgn grup D4 legacy di bawah.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async =>
            Directory.systemTemp.createTempSync('t8_retry_fullscreen').path,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    Widget host({
      required PostVideoCoordinator coordinator,
      required FeedPost post,
      required bool isActive,
    }) {
      return MaterialApp(
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-managed'),
          post: post,
          isActive: isActive,
          preloadedController: null,
          ownsController: false,
          playbackManagedExternally: true,
          coordinator: coordinator,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      );
    }

    Future<void> flushAsync(WidgetTester tester) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
    }

    // (a) + (b): sesi error → tombol "Coba lagi"; tap → session.retry().
    // Pakai seam debugInitAttempt (tanpa plugin) — controller selalu null,
    // sesi selalu error → cukup untuk memverifikasi surface + panggilan retry.
    testWidgets('sesi error → tampil "Coba lagi"; tap → retry() dipanggil',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final post = _fakeVideoPost();
      var attempts = 0;
      final coordinator = PostVideoCoordinator(
        sessionFactory: (postId) => VideoPlayerSession(
          url: 'https://cdn/$postId.mp4',
          userQualityPreference: 'auto',
          debugDelay: (_) async {},
          debugInitAttempt: (_) async {
            attempts++;
            throw Exception('network down');
          },
        ),
      );
      addTearDown(coordinator.dispose);

      // Buat sesi + drive init (awal + 1 auto-retry) sampai error.
      coordinator.attach('view-1', post.id);
      await flushAsync(tester);
      final session = coordinator.sessionFor(post.id) as VideoPlayerSession;
      expect(session.hasError, isTrue);
      expect(attempts, 2, reason: 'init awal + tepat 1 auto-retry');

      await tester.pumpWidget(host(
        coordinator: coordinator,
        post: post,
        isActive: true,
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Coba lagi'), findsOneWidget,
          reason: 'managed + sesi error → surface error dgn tombol Coba lagi');
      expect(find.byType(VideoPlayer), findsNothing);

      // Tap Coba lagi → session.retry() (reset budget → init ulang).
      await tester.tap(find.text('Coba lagi'));
      await tester.pump();
      await flushAsync(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(attempts, greaterThan(2),
          reason: 'tap "Coba lagi" memicu session.retry() → init ulang');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // (c) + (d): retry SUKSES (create ke-3) → sesi melahirkan controller BARU
    // (revision bump) → view re-adopt + render VideoPlayer (bukan thumbnail
    // diam). Controller tak pernah di-dispose oleh widget saat unmount.
    testWidgets('retry sukses → re-adopt controller baru via revision + render',
        (tester) async {
      // failWithInitializeEvent:true WAJIB — throw sinkron di create() bikin
      // dispose() VideoPlayerController asli menggantung selamanya menunggu
      // _creatingCompleter yang tak pernah selesai (gotcha sama persis
      // seperti komentar _UrlAwareFailPlatform di atas). Tanpa ini, retry
      // kedua tak pernah kejadian — hasError tetap false selamanya (deadlock
      // diam, bukan flaky order-dependent).
      final platform = _FailThenSucceedPlatform(
        failUntil: 2,
        failWithInitializeEvent: true,
      );
      VideoPlayerPlatform.instance = platform;
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // HLS → bypass cache wrapper → plain VideoPlayerController → fake platform.
      final post = _fakeVideoPost(hls: true);
      final coordinator = PostVideoCoordinator(
        sessionFactory: (postId) => VideoPlayerSession(
          url: 'https://example.com/$postId.m3u8',
          userQualityPreference: 'auto',
          debugDelay: (_) async {},
        ),
      );
      addTearDown(coordinator.dispose);

      // Buat sesi (init awal + auto-retry pakai create #1 & #2 → keduanya
      // gagal) + jadikan aktif (desired play + volume, poin 4).
      coordinator.attach('view-1', post.id);
      coordinator.setActive(post.id);
      // Dua flush: beda dgn seam debugInitAttempt (sinkron), attempt via
      // VideoPlayerController ASLI (event-stream StreamController + Completer
      // sungguhan) butuh lebih banyak giliran microtask per attempt — 1x
      // flushAsync (12 putaran) cukup utk attempt pertama tapi kadang tak
      // cukup utk menuntaskan attempt KEDUA (create→gagal→cleanup→retry→
      // create lagi) dlm satu window yg sama.
      await flushAsync(tester);
      await flushAsync(tester);
      final session = coordinator.sessionFor(post.id) as VideoPlayerSession;
      expect(session.hasError, isTrue,
          reason: 'dua create pertama gagal → sesi error');
      expect(platform.createCount, 2);

      await tester.pumpWidget(host(
        coordinator: coordinator,
        post: post,
        isActive: true,
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing,
          reason: 'error → belum ada controller dirender');

      // Tap Coba lagi → retry → create #3 SUKSES → controller baru.
      await tester.tap(find.text('Coba lagi'));
      await tester.pump();
      await flushAsync(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(session.hasError, isFalse);
      expect(session.isInitialized, isTrue);
      expect(session.controller, isNotNull);
      expect(find.byType(VideoPlayer), findsWidgets,
          reason: 're-adopt controller baru pasca-retry → VideoPlayer render');
      expect(find.text('Coba lagi'), findsNothing,
          reason: 'surface error hilang setelah retry sukses');
      // Poin 4: desired play dipertahankan pada controller baru (view aktif).
      expect(session.controller!.value.isPlaying, isTrue,
          reason: 'retry mempertahankan desired play state (view aktif)');

      final controller = session.controller!;
      final disposesBefore = platform.disposeCount;

      // (d) Unmount widget → ownsController:false → TIDAK men-dispose.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.disposeCount, disposesBefore,
          reason: 'widget managed tak pernah men-dispose controller pinjaman');
      expect(controller.value.isInitialized, isTrue,
          reason: 'controller tetap hidup — coordinator pemilik');

      // Bersihkan: coordinator (pemilik) men-dispose sesi → controller,
      // menghentikan timer posisi periodik yang jalan selama playing.
      await tester.runAsync(() async {
        coordinator.dispose();
        await Future<void>.delayed(Duration.zero);
      });
    });
  });

  // ── Race fix (Feed→Profile) — jalur legacy non-managed ──
  // `didPushNext()` dulu early-return TANPA mencatat cover kalau controller
  // belum siap (null/belum initialized). Kalau init selesai async DI
  // BELAKANG route baru, video mulai bermain di belakang layar. Fix:
  // `_routeCovered` dicatat SEGERA saat route opaque didorong, independen
  // dari state controller, dan semua jalur play() lewat gate
  // `_canAutoplayNow` yang mengecek flag itu.
  group('race fix — route push sebelum init selesai (non-managed)', () {
    late _FakeVideoPlayerPlatform fakePlatform;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
    });

    testWidgets(
        'push route SEBELUM init selesai → controller tidak pernah play + '
        'volume 0; pop → baru play', (tester) async {
      fakePlatform = _FakeVideoPlayerPlatform(manualInit: true);
      VideoPlayerPlatform.instance = fakePlatform;
      // GAP #3: feedMuted=false → saat uncover, volume WAJIB kembali ke 1.
      await appSettingsStore.setFeedMuted(false);
      addTearDown(() => appSettingsStore.setFeedMuted(true));
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true), // HLS bypass cache wrapper
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      // Biarkan init mulai (create → createCount 1) — initialized ditahan
      // (manualInit), controller masih "loading".
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.createCount, 1,
          reason: 'init pertama mulai membuat satu player');
      expect(fakePlatform.playCount, 0,
          reason: 'belum initialized → belum ada play');

      // Push route opaque SEBELUM init selesai → didPushNext harus mencatat
      // _routeCovered SEGERA (controller belum initialized).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Selesaikan init DI BELAKANG route baru.
      fakePlatform.emitInitialized();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(fakePlatform.playCount, 0,
          reason:
              'race fix: init selesai di belakang route → TIDAK boleh play');
      expect(fakePlatform.volumes, isNotEmpty,
          reason: 'volume tetap di-apply (senyap) walau tidak play');
      expect(fakePlatform.volumes.last, 0,
          reason: 'route-covered → controller wajib senyap (volume 0)');

      // Pop kembali ke Feed → didPopNext harus resume (masih isActive).
      navigator.pop();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, greaterThanOrEqualTo(1),
          reason: 'kembali ke Feed (didPopNext) → sekarang boleh play');
      // GAP #3: sebelum fix, init-di-bawah-cover memaksa setVolume(0) dan tak
      // ada yang mengembalikan saat uncover → video resume SENYAP. Setelah fix,
      // uncover mengembalikan volume ke feedMuted?0:1 = 1.
      expect(fakePlatform.volumes.last, 1,
          reason: 'GAP #3: uncover mengembalikan volume (feedMuted=false → 1)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // GAP #4: di race Feed→Profile, controller null saat cover →
    // _pausedByCover TAK PERNAH true → _resumeFromCover (versi lama)
    // early-return, dan video hanya bangun karena VisibilityDetector re-fire
    // (~500ms di device, jeda terlihat). Fix: didPopNext meneruskan wasCovered
    // → _resumeFromCover(forceIfUncovered:true) menyalakan via state-machine.
    // Test ini menon-aktifkan VD re-fire (interval besar) supaya play HANYA
    // bisa datang dari state-machine — bukti jalur didPopNext benar-benar hidup.
    testWidgets(
        'GAP #4: pop → resume via didPopNext state-machine tanpa menunggu '
        'VisibilityDetector re-fire', (tester) async {
      // Interval besar → VisibilityDetector TIDAK re-fire selama test body.
      VisibilityDetectorController.instance.updateInterval =
          const Duration(hours: 1);
      addTearDown(() =>
          VisibilityDetectorController.instance.updateInterval = Duration.zero);

      fakePlatform = _FakeVideoPlayerPlatform(manualInit: true);
      VideoPlayerPlatform.instance = fakePlatform;
      await appSettingsStore.setFeedMuted(false);
      addTearDown(() => appSettingsStore.setFeedMuted(true));
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Push opaque SEBELUM init selesai → controller null saat cover →
      // _pausedByCover tak pernah true (kondisi persis GAP #4).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Init selesai DI BELAKANG route → senyap, tak play.
      fakePlatform.emitInitialized();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, 0,
          reason: 'covered → belum play (VD juga tak re-fire)');

      // Pop → didPopNext → _resumeFromCover(forceIfUncovered:true). Karena VD
      // dinon-aktifkan, satu-satunya sumber play adalah state-machine ini.
      navigator.pop();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, greaterThanOrEqualTo(1),
          reason: 'GAP #4: resume via didPopNext, BUKAN VisibilityDetector');
      expect(fakePlatform.volumes.last, 1,
          reason: 'GAP #3: uncover mengembalikan volume (feedMuted=false → 1)');

      await tester.pumpWidget(const SizedBox());
      // Flush timer VD yang terjadwal (interval besar) supaya tak "pending".
      await tester.pump(const Duration(hours: 1));
    });

    testWidgets(
        '_routeCovered toggle: push opaque menahan autoplay, pop melepasnya '
        '(controller sudah ready sebelum push)', (tester) async {
      fakePlatform = _FakeVideoPlayerPlatform(); // init langsung selesai
      VideoPlayerPlatform.instance = fakePlatform;
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: FeedVideoPostView(
          key: const ValueKey('feed-video-post-1'),
          post: _fakeVideoPost(hls: true),
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, greaterThanOrEqualTo(1),
          reason: 'controller ready + active + autoplay → sudah main');
      final ctrl =
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
      expect(ctrl.value.isPlaying, isTrue);

      // Push opaque → didPushNext harus pause + set _routeCovered=true.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isFalse,
          reason: 'route opaque didorong → video harus pause');
      final pauseCountAfterPush = fakePlatform.pauseCount;
      expect(pauseCountAfterPush, greaterThanOrEqualTo(1));

      // Pop → didPopNext harus resume (route tidak lagi covered).
      navigator.pop();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isTrue,
          reason: '_routeCovered=false setelah pop → video resume');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  // ── HARDENING audio-hantu Feed→Profile (_routeCovered opaque-aware) ──
  // Video Feed TIDAK PERNAH play selama ada route OPAQUE (Profile/Postingan/dll)
  // menutupi Feed. Ini dijaga oleh `_routeCovered` (di-set di didPushNext untuk
  // route opaque, di-reset di didPopNext) — BUKAN oleh `ModalRoute.isCurrent`
  // (guard itu dibuang: memblokir video di balik sheet TRANSPARAN, regresi).
  // Kasus nested-route (Feed→Profile→Postingan lalu pop SEBAGIAN) tetap benar
  // karena RouteObserver hanya notif route adjacent: saat Postingan di-pop
  // (Postingan→Profile), Feed TIDAK menerima didPopNext (bukan route adjacent)
  // → `_routeCovered` tetap true sepanjang Profile masih menutup Feed.
  group('HARDENING _routeCovered opaque-aware (non-managed)', () {
    late _FakeVideoPlayerPlatform fakePlatform;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
    });

    Widget legacyHost() => MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: FeedVideoPostView(
            key: const ValueKey('feed-video-post-1'),
            post: _fakeVideoPost(hls: true), // HLS bypass cache wrapper
            isActive: true,
            preloadedController: null,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        );

    // Scenario 4 + 5 (nested): Feed→Profile→Postingan (push 2 route) sebelum
    // init selesai → init selesai DI BELAKANG dua route → TIDAK play. Pop
    // SEKALI (Postingan→Profile) → MASIH ada Profile di atas → tetap TIDAK
    // play. Pop lagi (Profile→Feed) → baru boleh play. `_routeCovered` (set di
    // didPushNext saat Profile didorong) menjamin ini: pop Postingan→Profile
    // tidak mengirim didPopNext ke Feed (bukan route adjacent) → `_routeCovered`
    // tetap true sampai Profile sendiri di-pop.
    testWidgets(
        'nested Feed→Profile→Postingan: pop sebagian tetap tak play; '
        'pop penuh baru play', (tester) async {
      fakePlatform = _FakeVideoPlayerPlatform(manualInit: true);
      VideoPlayerPlatform.instance = fakePlatform;
      await appSettingsStore.setFeedMuted(false);
      addTearDown(() => appSettingsStore.setFeedMuted(true));
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(legacyHost());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.createCount, 1);
      expect(fakePlatform.playCount, 0);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      // Push Profile lalu Postingan (dua route opaque menumpuk di atas Feed).
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Init selesai DI BELAKANG dua route → tak boleh play + senyap.
      fakePlatform.emitInitialized();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, 0,
          reason: 'nested (2 route di atas Feed) → TIDAK play');
      expect(fakePlatform.volumes.last, 0,
          reason: 'covered → senyap (volume 0)');

      // Pop SEKALI (Postingan→Profile): Feed masih tertutup Profile → isCurrent
      // Feed tetap false → TIDAK play. Feed tidak menerima didPopNext di sini
      // (yang di-pop bukan route tepat di atas Feed).
      navigator.pop();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, 0,
          reason:
              '_routeCovered masih true (Profile menutup Feed) → tetap tak play');

      // Pop lagi (Profile→Feed): Feed teratas → isCurrent true → boleh play.
      navigator.pop();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, greaterThanOrEqualTo(1),
          reason: 'Feed kembali teratas → sekarang boleh play');
      expect(fakePlatform.volumes.last, 1,
          reason: 'uncover penuh → volume kembali (feedMuted=false → 1)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // Scenario 3: app di-background SAAT navigasi berlangsung (push + lifecycle
    // paused) → init selesai → tak play; kembali foreground + pop → baru play.
    testWidgets(
        'background app saat navigasi: init selesai tak play; foreground + pop '
        '→ play', (tester) async {
      fakePlatform = _FakeVideoPlayerPlatform(manualInit: true);
      VideoPlayerPlatform.instance = fakePlatform;
      await appSettingsStore.setFeedMuted(false);
      addTearDown(() => appSettingsStore.setFeedMuted(true));
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(legacyHost());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // App ke background SAAT route lain di atas Feed.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Init selesai saat covered + background → dobel penjaga → tak play.
      fakePlatform.emitInitialized();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, 0,
          reason: 'covered + background → init selesai tetap tak play');

      // Foreground kembali TAPI route masih di atas Feed → tetap tak play
      // (_routeCovered masih true menahan).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, 0,
          reason: 'foreground tapi route masih menutup Feed → tetap tak play');

      // Pop → Feed teratas + foreground → baru play.
      navigator.pop();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, greaterThanOrEqualTo(1),
          reason: 'foreground + Feed teratas → boleh play');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    // _routeCovered reinforcement: controller READY + playing, push route opaque
    // (didPushNext pause + set _routeCovered). Lalu app background→foreground
    // SELAGI route masih di atas Feed → resume TIDAK boleh menembus
    // (_routeCovered masih true), walau app sudah foreground. Baru setelah pop
    // (didPopNext reset _routeCovered), play kembali.
    testWidgets(
        'ready+playing: app foreground selagi route menutup Feed → tetap tak '
        'resume; pop → resume', (tester) async {
      fakePlatform = _FakeVideoPlayerPlatform(); // init langsung selesai
      VideoPlayerPlatform.instance = fakePlatform;
      await appSettingsStore.setFeedMuted(false);
      addTearDown(() => appSettingsStore.setFeedMuted(true));
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(legacyHost());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ctrl =
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
      expect(ctrl.value.isPlaying, isTrue);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isFalse,
          reason: 'route opaque didorong → pause (didPushNext)');

      // Background lalu foreground SELAGI route masih menutup Feed. App resume
      // memicu _resumeFromCover(forceIfUncovered:true), tapi _routeCovered masih
      // true (route opaque lain menutup Feed) menahan play.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final playAfterPause = fakePlatform.playCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, playAfterPause,
          reason:
              'foreground selagi route menutup Feed → _routeCovered menahan '
              'resume (nol play tambahan)');
      expect(ctrl.value.isPlaying, isFalse);

      // Pop → Feed teratas → resume.
      navigator.pop();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isTrue,
          reason: 'Feed teratas lagi → resume');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  // ── REGRESI sheet TRANSPARAN (guard isCurrent dibuang) ──
  // Sheet produk/cart/tagged dibuka via showModalBottomSheet(transparent) =
  // ModalBottomSheetRoute NON-opaque. Desain SENGAJA membiarkan video Feed
  // TETAP MAIN di baliknya (`_routeCovered` HANYA di-set utk route OPAQUE via
  // lastPushedRouteIsOpaque()). Guard `_feedRouteIsCurrent` lama (ModalRoute
  // .isCurrent) memblokir ini: video main di balik sheet → app background →
  // foreground → _resumeFromCover(forceIfUncovered:true) → _canAutoplayNow
  // false (isCurrent false selagi sheet non-opaque teratas) → video BEKU sampai
  // sheet ditutup. Fix: gate mengandalkan `_routeCovered` (opaque-aware), jadi
  // di balik sheet transparan video BOLEH resume; di balik route opaque TIDAK.
  group('REGRESI sheet transparan (opaque-aware, non-managed)', () {
    late _FakeVideoPlayerPlatform fakePlatform;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
      CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
      fakePlatform = _FakeVideoPlayerPlatform(); // init langsung selesai
      VideoPlayerPlatform.instance = fakePlatform;
    });

    Widget legacyHost() => MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: FeedVideoPostView(
            key: const ValueKey('feed-video-post-1'),
            post: _fakeVideoPost(hls: true), // HLS bypass cache wrapper
            isActive: true,
            preloadedController: null,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        );

    // NON-opaque route (opaque:false) — men-drive lastPushedRouteIsOpaque()
    // == false persis seperti showModalBottomSheet(transparent), tanpa perlu
    // sheet UI sungguhan. Route ini tetap PageRoute (adjacent didPushNext ke
    // Feed) tapi tidak opaque → didPushNext TIDAK men-set _routeCovered.
    Route<void> transparentRoute() => PageRouteBuilder<void>(
          opaque: false,
          barrierColor: const Color(0x66000000),
          pageBuilder: (_, __, ___) => const SizedBox(),
        );

    testWidgets(
        'di balik sheet transparan: app background→foreground → video RESUME '
        '(bukan beku)', (tester) async {
      await appSettingsStore.setFeedMuted(false);
      addTearDown(() => appSettingsStore.setFeedMuted(true));
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(legacyHost());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ctrl =
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
      expect(ctrl.value.isPlaying, isTrue,
          reason: 'controller ready + active + autoplay → sudah main');

      // Push sheet TRANSPARAN (opaque:false) → didPushNext fire tapi
      // lastPushedRouteIsOpaque() false → _routeCovered TIDAK di-set → video
      // TETAP MAIN di baliknya (perilaku by-design ala TikTok/IG).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(transparentRoute());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isTrue,
          reason: 'sheet transparan tidak menutup → video tetap main');

      // App ke background → _pauseForCover(appBackground) mem-pause video.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isFalse,
          reason: 'app background → video pause');

      // App foreground → _resumeFromCover(forceIfUncovered:true). Dengan guard
      // isCurrent LAMA, sheet transparan teratas → isCurrent false → video BEKU.
      // Setelah guard dibuang, _routeCovered false → video RESUME.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isTrue,
          reason: 'REGRESI FIX: di balik sheet transparan, foreground → video '
              'RESUME (guard isCurrent lama membuatnya beku)');
      expect(fakePlatform.volumes.last, 1,
          reason: 'resume dengan suara kembali (feedMuted=false → 1)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets(
        'KONTRAS route OPAQUE: app background→foreground selagi tertutup → '
        'TIDAK resume', (tester) async {
      await appSettingsStore.setFeedMuted(false);
      addTearDown(() => appSettingsStore.setFeedMuted(true));
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(legacyHost());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ctrl =
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
      expect(ctrl.value.isPlaying, isTrue);

      // Push route OPAQUE → didPushNext men-set _routeCovered=true + pause.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ctrl.value.isPlaying, isFalse,
          reason: 'route opaque didorong → pause + _routeCovered=true');

      // Background→foreground selagi route opaque MASIH menutup Feed →
      // _routeCovered tetap true → resume TIDAK menembus (kontras dgn transparan).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final playAfterPause = fakePlatform.playCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fakePlatform.playCount, playAfterPause,
          reason:
              'di balik route OPAQUE (_routeCovered true) → tetap tak resume');
      expect(ctrl.value.isPlaying, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  // D4 legacy — init gagal + URL bertanda-tangan (Bunny signed, expiry 6 jam)
  // → fetch post segar (server sign ulang tiap request) → SATU retry dengan
  // URL baru. Port dari jalur managed (VideoPlayerSession._maybeRefreshSignedUrl).
  group('D4 legacy — refresh signed URL (non-managed)', () {
    const staleUrl =
        'https://cdn.example/post-d4/playlist.m3u8?token=stale&expires=1';
    const freshUrl =
        'https://cdn.example/post-d4/playlist.m3u8?token=fresh&expires=999';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      // pumpBounded memakai runAsync (flush real-async init error) — itu juga
      // membangunkan flutter_cache_manager (image cache) yang menyentuh
      // path_provider; stub channel-nya supaya tidak MissingPluginException.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp
            .createTempSync('d4_signed_url_refresh')
            .path,
      );
    });

    tearDown(() {
      debugLegacyFeedPostFetcher = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    Widget host(FeedPost post) => MaterialApp(
          home: FeedVideoPostView(
            post: post,
            isActive: true,
            preloadedController: null,
            onOverlayStateChanged: (_) {},
            onMediaZoomChanged: (_) {},
          ),
        );

    Future<void> pumpBounded(WidgetTester tester, {int rounds = 12}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        // Flush real-async hop (error event stream → initialize future) yang
        // tidak terdorong fake-clock pump saja — pola runAsync suite ini.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    }

    testWidgets('URL signed basi → fetch segar → init sukses dgn URL BARU',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      addTearDown(() => appSettingsStore.setFeedAutoplay(true));
      final platform = _UrlAwareFailPlatform(failFragment: 'token=stale');
      VideoPlayerPlatform.instance = platform;

      var fetchCalls = 0;
      debugLegacyFeedPostFetcher = (id) async {
        fetchCalls++;
        expect(id, 'post-d4');
        return _fakeVideoPost(id: 'post-d4', videoUrl: freshUrl);
      };

      await tester
          .pumpWidget(host(_fakeVideoPost(id: 'post-d4', videoUrl: staleUrl, thumbnailUrl: '')));
      await pumpBounded(tester);

      expect(fetchCalls, 1, reason: 'refresh dipanggil tepat sekali');
      expect(platform.uris, hasLength(3),
          reason: 'attempt1+2 URL lama, attempt3 URL segar');
      expect(platform.uris.last, contains('token=fresh'),
          reason: 'attempt3 memakai URL SEGAR hasil refresh');
      expect(find.text('Coba lagi'), findsNothing,
          reason: 'init akhirnya sukses → tidak ada error surface');
      // findsWidgets (bukan findsOneWidget) — video aspect-mismatch sengaja
      // dirender dua-lapis (backdrop blur cover + foreground contain) yang
      // sama-sama VideoPlayer(ctrl); pola sama dgn tes T8 line ~2403.
      expect(find.byType(VideoPlayer), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      // Habiskan sisa timer (image cache / rotasi produk) supaya invariant
      // !timersPending bersih.
      await tester.pump(const Duration(minutes: 2));
    });

    testWidgets('URL non-signed → refresh TIDAK dipanggil → "Coba lagi"',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      addTearDown(() => appSettingsStore.setFeedAutoplay(true));
      const plainUrl = 'https://cdn.example/post-d4b/playlist.m3u8';
      final platform = _UrlAwareFailPlatform(failFragment: 'post-d4b');
      VideoPlayerPlatform.instance = platform;

      var fetchCalls = 0;
      debugLegacyFeedPostFetcher = (id) async {
        fetchCalls++;
        return _fakeVideoPost(id: 'post-d4b', videoUrl: freshUrl);
      };

      await tester
          .pumpWidget(host(_fakeVideoPost(id: 'post-d4b', videoUrl: plainUrl, thumbnailUrl: '')));
      await pumpBounded(tester);

      expect(fetchCalls, 0,
          reason: 'URL tanpa token=&expires= → refresh di-skip');
      expect(platform.uris, hasLength(2), reason: 'hanya attempt1+2');
      expect(find.text('Coba lagi'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('refresh return URL SAMA → tetap gagal, tanpa attempt3/loop',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      addTearDown(() => appSettingsStore.setFeedAutoplay(true));
      final platform = _UrlAwareFailPlatform(failFragment: 'token=stale');
      VideoPlayerPlatform.instance = platform;

      var fetchCalls = 0;
      debugLegacyFeedPostFetcher = (id) async {
        fetchCalls++;
        // Server balikin URL persis sama (belum re-sign) → no-op.
        return _fakeVideoPost(id: 'post-d4c', videoUrl: staleUrl);
      };

      await tester
          .pumpWidget(host(_fakeVideoPost(id: 'post-d4c', videoUrl: staleUrl, thumbnailUrl: '')));
      await pumpBounded(tester);

      expect(fetchCalls, 1);
      expect(platform.uris, hasLength(2),
          reason: 'URL sama → TIDAK ada attempt3 (tak berguna, cegah loop)');
      expect(find.text('Coba lagi'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('refresh return null → tetap gagal → "Coba lagi"',
        (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      addTearDown(() => appSettingsStore.setFeedAutoplay(true));
      final platform = _UrlAwareFailPlatform(failFragment: 'token=stale');
      VideoPlayerPlatform.instance = platform;

      var fetchCalls = 0;
      debugLegacyFeedPostFetcher = (id) async {
        fetchCalls++;
        return null; // post dihapus / 404
      };

      await tester
          .pumpWidget(host(_fakeVideoPost(id: 'post-d4d', videoUrl: staleUrl, thumbnailUrl: '')));
      await pumpBounded(tester);

      expect(fetchCalls, 1);
      expect(platform.uris, hasLength(2));
      expect(find.text('Coba lagi'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
