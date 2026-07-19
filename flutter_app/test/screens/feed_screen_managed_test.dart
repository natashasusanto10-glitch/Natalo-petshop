// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_local_store.dart';
import 'package:natalo_petshop_flutter/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Migrasi Feed→PostVideoCoordinator (Opsi D, Langkah 7): coordinator adalah
/// SATU-SATUNYA jalur (flag dihapus). `FeedVideoPostView` selalu mode managed
/// + urutan attach→setActive→detach (§Urutan #1) / clearActive→detach
/// (§Urutan #2).

/// Sesi kosong — tak pernah diadopsi widget (bukan `VideoPlayerSession`),
/// jadi tak butuh plugin video sama sekali; widget cukup render thumbnail.
class _NullSession implements PlaybackSession {
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPlaybackSpeed(double speed) async {}
  @override
  Future<void> dispose() async {}
  @override
  Duration get position => Duration.zero;
}

/// Coordinator asli + pencatat urutan panggilan attach/setActive/detach/
/// clearActive/setPreloadWindow — supaya §Urutan #1/#2 bisa diverifikasi
/// tanpa menyentuh plugin video.
class _TrackingCoordinator extends PostVideoCoordinator {
  _TrackingCoordinator() : super(sessionFactory: (_) => _NullSession());

  final List<String> calls = <String>[];

  @override
  PlaybackSession attach(String viewId, String postId) {
    calls.add('attach:$postId');
    return super.attach(viewId, postId);
  }

  @override
  void setActive(String postId) {
    calls.add('setActive:$postId');
    super.setActive(postId);
  }

  @override
  void detach(String viewId, String postId) {
    calls.add('detach:$postId');
    super.detach(viewId, postId);
  }

  @override
  void clearActive() {
    calls.add('clearActive');
    super.clearActive();
  }

  List<Set<String>> preloadWindowCalls = [];

  @override
  void setPreloadWindow(Iterable<String> postIds) {
    preloadWindowCalls.add(postIds.toSet());
    super.setPreloadWindow(postIds);
  }
}

Map<String, dynamic> _videoJson(String id) => {
      'id': id,
      'slug': id,
      'kind': 'USER_VIDEO',
      'videoUrl': 'https://example.com/$id.m3u8',
      'thumbnailUrl': 'https://example.com/$id.jpg',
      'durationSec': 10,
      'aspectRatio': 0.5625,
      'author': {'id': 'author-1', 'name': 'Tester'},
      'createdAt': '2026-07-18T00:00:00.000Z',
    };

Map<String, dynamic> _photoJson(String id) => {
      'id': id,
      'slug': id,
      'kind': 'PHOTO_CAROUSEL',
      'mediaItems': [
        {
          'id': '$id-media',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/$id.jpg',
          'sortOrder': 0,
        },
      ],
      'author': {'id': 'author-1', 'name': 'Tester'},
      'createdAt': '2026-07-18T00:00:00.000Z',
    };

Future<_TrackingCoordinator> _pumpFeedWith(
  WidgetTester tester,
  List<Map<String, dynamic>> postsJson,
) async {
  SharedPreferences.setMockInitialValues({
    'feed_offline_cache_v2::guest': jsonEncode(postsJson),
  });
  final coordinator = _TrackingCoordinator();
  debugFeedCoordinatorFactory = ({required sessionFactory}) => coordinator;

  await tester.pumpWidget(
    MaterialApp(
      routes: {
        '/member/login': (_) => const Scaffold(body: Text('Login')),
      },
      home: const FeedScreen(),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return coordinator;
}

Future<void> _swipeNext(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(0, -900),
      warnIfMissed: false);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    debugFeedCoordinatorFactory = null;
    // feedLocalStore singleton bertahan lintas-test dalam satu proses — tanpa
    // reset ini, `_initialized` dari test sebelumnya membuat
    // `SharedPreferences.setMockInitialValues` test ini diam-diam terabaikan.
    feedLocalStore.debugResetForTest();
  });

  tearDown(() {
    debugFeedCoordinatorFactory = null;
  });

  testWidgets('item video pertama di-attach + setActive (managed)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final coordinator = await _pumpFeedWith(tester, [_videoJson('v1')]);

    expect(coordinator.calls, contains('attach:v1'));
    expect(coordinator.calls, contains('setActive:v1'));
    expect(coordinator.activePostId, 'v1');

    // Widget item harus managed (ownsController:false, coordinator terpasang).
    final widget =
        tester.widget<FeedVideoPostView>(find.byType(FeedVideoPostView));
    expect(widget.ownsController, isFalse);
    expect(widget.playbackManagedExternally, isTrue);
    expect(widget.coordinator, same(coordinator));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('swipe video A→video B → attach(B)→setActive(B)→detach(A)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final coordinator =
        await _pumpFeedWith(tester, [_videoJson('v1'), _videoJson('v2')]);
    coordinator.calls.clear();

    await _swipeNext(tester);

    expect(coordinator.activePostId, 'v2');
    final iAttachB = coordinator.calls.indexOf('attach:v2');
    final iSetActiveB = coordinator.calls.indexOf('setActive:v2');
    final iDetachA = coordinator.calls.indexOf('detach:v1');
    expect(iAttachB, greaterThanOrEqualTo(0),
        reason: '§Urutan #1: attach(B) harus dipanggil');
    expect(iSetActiveB, greaterThan(iAttachB),
        reason: '§Urutan #1: setActive(B) SETELAH attach(B)');
    expect(iDetachA, greaterThan(iSetActiveB),
        reason: '§Urutan #1: detach(A) SETELAH setActive(B), bukan sebelum');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('swipe video→foto → clearActive→detach TAK BERSYARAT',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final coordinator = await _pumpFeedWith(
      tester,
      [_videoJson('v1'), _photoJson('p1')],
    );
    coordinator.calls.clear();

    await _swipeNext(tester);

    expect(coordinator.activePostId, isNull,
        reason: 'foto bukan video → tak ada activePostId');
    final iClear = coordinator.calls.indexOf('clearActive');
    final iDetach = coordinator.calls.indexOf('detach:v1');
    expect(iClear, greaterThanOrEqualTo(0));
    expect(iDetach, greaterThan(iClear),
        reason: '§Urutan #2: detach(A) SETELAH clearActive, tak bersyarat');
    // Foto TIDAK pernah di-attach ke coordinator (video-only).
    expect(coordinator.calls.any((c) => c.startsWith('attach:p1')), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('preload window hanya berisi post video (video-only)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await appSettingsStore.setFeedAutoplay(true);

    final coordinator = await _pumpFeedWith(
      tester,
      [_videoJson('v1'), _photoJson('p1'), _videoJson('v2')],
    );

    expect(coordinator.preloadWindowCalls, isNotEmpty);
    final lastWindow = coordinator.preloadWindowCalls.last;
    expect(lastWindow.contains('p1'), isFalse,
        reason: 'foto tak pernah masuk preload window coordinator');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
