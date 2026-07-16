// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// In-memory [VideoPlayerPlatform] — auto-emits `initialized` so a plain HLS
/// controller reaches a playable state in the widget test. Salinan minimal
/// dari harness `feed_video_post_view_test.dart` (HLS bypass cache wrapper →
/// tak perlu noop cache/metadata).
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform();

  final Map<int, StreamController<VideoEvent>> _streams = {};
  final Map<int, Duration> _positions = {};
  int _nextId = 0;
  int createCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  final Set<int> _disposedIds = {};

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
    stream.add(VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(720, 1280),
      duration: const Duration(seconds: 10),
    ));
    return id;
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
    playCount++;
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCount++;
  }

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

FeedPost _fakeVideoPost({
  String id = 'post-1',
  double aspectRatio = 0.5625,
  bool hls = false,
  List<Map<String, dynamic>>? taggedProducts,
}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl':
        hls ? 'https://example.com/$id.m3u8' : 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': aspectRatio,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'viewerLiked': false,
    'createdAt': DateTime.now().toIso8601String(),
    if (taggedProducts != null) 'taggedProducts': taggedProducts,
  });
}

Widget _hostVideo({
  required FeedPost post,
  required bool isActive,
  bool playbackManagedExternally = false,
  void Function(CoverPauseReason)? onRequestPause,
  VoidCallback? onRequestPlay,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FeedVideoPostView(
        post: post,
        isActive: isActive,
        preloadedController: null,
        ownsController: !playbackManagedExternally,
        playbackManagedExternally: playbackManagedExternally,
        onOverlayStateChanged: (_) {},
        onMediaZoomChanged: (_) {},
        onRequestPause: onRequestPause,
        onRequestPlay: onRequestPlay,
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    await appSettingsStore.setFeedAutoplay(true);
  });

  testWidgets('pill tap opens links sheet and requests pause (managed)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CoverPauseReason? pausedReason;
    var resumed = false;
    final post = _fakeVideoPost(hls: true, taggedProducts: [
      {
        'id': '1',
        'slug': 'a',
        'name': 'Produk A',
        'price': 55000,
        'discountPrice': 44500,
        'stock': 10,
      },
      {'id': '2', 'slug': 'b', 'name': 'Produk B', 'price': 30000, 'stock': 5},
    ]);
    await tester.pumpWidget(_hostVideo(
      post: post,
      isActive: true,
      playbackManagedExternally: true,
      onRequestPause: (r) => pausedReason = r,
      onRequestPlay: () => resumed = true,
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Produk A').evaluate().isNotEmpty) break;
    }
    expect(find.text('Produk A'), findsWidgets); // pill featured name
    expect(find.text('·2'), findsOneWidget); // pill count

    await tester.tap(find.text('Produk A').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Produk (2)').evaluate().isNotEmpty) break;
    }
    expect(find.text('Produk (2)'), findsOneWidget); // sheet open
    expect(pausedReason, CoverPauseReason.productSheet);

    // Let the sheet entrance animation settle before hitting close.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.close_rounded));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (resumed) break;
    }
    expect(resumed, isTrue);
  });
}
