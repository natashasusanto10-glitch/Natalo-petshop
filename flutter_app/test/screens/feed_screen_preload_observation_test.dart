// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/feed_video_observation.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _PreloadVideoPlatform extends VideoPlayerPlatform {
  _PreloadVideoPlatform({this.failCreate = false, this.initializeGate});

  final bool failCreate;
  final Completer<void>? initializeGate;
  final Map<int, StreamController<VideoEvent>> _streams = {};
  var _nextId = 0;
  var disposedCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => _create();

  Future<int?> _create() async {
    if (failCreate) throw StateError('create failed');
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
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
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposedCount++;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopMetadataStorage implements IVideoPlayerMetadataStorage {
  @override
  Set<String> get keys => const {};

  @override
  Future<int?> read(String key) async => null;

  @override
  Future<void> write(String key, int value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> erase() async {}
}

CachedVideoPlayerPlus _cachedPlayer(String id) =>
    CachedVideoPlayerPlus.networkUrl(
      Uri.parse('https://example.com/$id.mp4'),
      cacheKey: id,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VideoPlayerPlatform.instance = _PreloadVideoPlatform();
    CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
    CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
  });

  test('adopting a preloaded controller keeps one observed identity', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final controller = Object();

    observeFeedPreloadCreated(
      observer,
      postId: 'post-a',
      controller: controller,
    );
    observeFeedPreloadAdopted(
      observer,
      postId: 'post-a',
      controller: controller,
    );

    expect(observer.snapshot.liveControllerCount, 1);
    expect(observer.snapshot.collisions, isEmpty);
    expect(
      observer.snapshot.events.map((event) => event.type),
      <SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.attached,
      ],
    );
  });

  test('disposing one preload removes only its observed identity', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final first = Object();
    final second = Object();

    observeFeedPreloadCreated(observer, postId: 'post-a', controller: first);
    observeFeedPreloadCreated(observer, postId: 'post-b', controller: second);
    observeFeedControllerDisposed(
      observer,
      postId: 'post-a',
      controller: first,
      ownerId: feedPreloadOwnerId('post-a'),
    );

    expect(observer.snapshot.liveControllerCount, 1);
    expect(observer.snapshot.collisions, isEmpty);
  });

  test('failed preload does not remain live', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final controller = Object();

    observeFeedPreloadCreated(
      observer,
      postId: 'post-a',
      controller: controller,
    );
    observeFeedControllerFailed(
      observer,
      postId: 'post-a',
      controller: controller,
      ownerId: feedPreloadOwnerId('post-a'),
    );

    expect(observer.snapshot.liveControllerCount, 0);
    expect(
      observer.snapshot.events.map((event) => event.type),
      containsAllInOrder(<SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.failed,
        SocialVideoLifecycleType.released,
      ]),
    );
  });

  test('distinct local controller collides with a live preload', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final preload = Object();
    final local = Object();

    observeFeedPreloadCreated(
      observer,
      postId: 'post-a',
      controller: preload,
    );
    observeFeedLocalControllerCreated(
      observer,
      postId: 'post-a',
      controller: local,
    );

    expect(observer.snapshot.liveControllerCount, 2);
    expect(observer.snapshot.collisions.single.controllerCount, 2);
  });

  test('pending MP4 wrapper cleanup never reads controller before init',
      () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    final wrapper = _cachedPlayer('pending');

    await disposeFeedCachedPreloadForObservation(
      player: wrapper,
      controller: null,
      observer: observer,
      postId: 'post-pending',
    );

    expect(observer.snapshot.events, isEmpty);
    expect(observer.snapshot.liveControllerCount, 0);
  });

  test('pending MP4 disposal waits for init and releases eventual controller',
      () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    final initializeGate = Completer<void>();
    final platform = _PreloadVideoPlatform(initializeGate: initializeGate);
    VideoPlayerPlatform.instance = platform;
    final wrapper = _cachedPlayer('pending-success');
    final initialization = wrapper.initialize();

    final disposal = disposeFeedCachedPreloadForObservation(
      player: wrapper,
      controller: null,
      observer: observer,
      postId: 'post-pending-success',
      initialization: initialization,
    );
    await Future<void>.delayed(Duration.zero);
    expect(platform.disposedCount, 0);

    initializeGate.complete();
    await initialization;
    await disposal;

    expect(platform.disposedCount, 1);
    expect(observer.snapshot.liveControllerCount, 0);
  });

  test('MP4 preload records actual post-init identity and eviction releases it',
      () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    final platform = _PreloadVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    final wrapper = _cachedPlayer('ready');

    final controller = await initializeFeedCachedPreloadForObservation(
      player: wrapper,
      observer: observer,
      postId: 'post-ready',
      isCurrent: () => true,
    );

    expect(controller, same(wrapper.controller));
    expect(observer.snapshot.liveControllerCount, 1);
    expect(
        observer.snapshot.events.map((event) => event.type),
        containsAllInOrder(<SocialVideoLifecycleType>[
          SocialVideoLifecycleType.created,
          SocialVideoLifecycleType.initialized,
        ]));

    await disposeFeedCachedPreloadForObservation(
      player: wrapper,
      controller: controller,
      observer: observer,
      postId: 'post-ready',
    );

    expect(platform.disposedCount, 1);
    expect(observer.snapshot.liveControllerCount, 0);
    expect(
        observer.snapshot.events.last.type, SocialVideoLifecycleType.disposed);
  });

  test('failed MP4 preload cleanup retains no observed identity', () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    VideoPlayerPlatform.instance = _PreloadVideoPlatform(failCreate: true);
    final wrapper = _cachedPlayer('failed');

    await expectLater(
      initializeFeedCachedPreloadForObservation(
        player: wrapper,
        observer: observer,
        postId: 'post-failed',
        isCurrent: () => true,
      ),
      throwsStateError,
    );
    await disposeFeedCachedPreloadForObservation(
      player: wrapper,
      controller: null,
      observer: observer,
      postId: 'post-failed',
    );

    expect(observer.snapshot.liveControllerCount, 0);
    expect(observer.snapshot.events, isEmpty);
  });

  test('actual MP4 identity is reused on adoption and detects a distinct local',
      () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    final wrapper = _cachedPlayer('identity');
    final preload = await initializeFeedCachedPreloadForObservation(
      player: wrapper,
      observer: observer,
      postId: 'post-identity',
      isCurrent: () => true,
    );

    observeFeedPreloadAdopted(
      observer,
      postId: 'post-identity',
      controller: preload!,
    );
    expect(observer.snapshot.liveControllerCount, 1);
    expect(observer.snapshot.collisions, isEmpty);

    observeFeedLocalControllerCreated(
      observer,
      postId: 'post-identity',
      controller: Object(),
    );
    expect(observer.snapshot.collisions.single.controllerCount, 2);

    await disposeFeedCachedPreloadForObservation(
      player: wrapper,
      controller: preload,
      observer: observer,
      postId: 'post-identity',
    );
  });
}
