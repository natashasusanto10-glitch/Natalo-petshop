// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_local_store.dart';
import 'package:natalo_petshop_flutter/utils/app_route_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Migrasi Feed→PostVideoCoordinator (Opsi D, Langkah 7): coordinator kini
/// SATU-SATUNYA jalur (feature flag dihapus) — dibuat unconditionally di
/// initState + wiring lifecycle (app background/foreground, route
/// push/pop) selalu aktif. Test ini memverifikasi wiring itu memakai
/// [debugFeedCoordinatorFactory] untuk menyuntik spy.

/// Sesi kosong — `_bootstrapFromCache` bisa memicu `attach()` sungguhan
/// (preload window disinkron dari cache), jadi factory TAK BOLEH throw.
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

/// Coordinator mata-mata: menghitung pauseAll/resumeAll supaya wiring
/// lifecycle bisa diverifikasi tanpa sesi hidup.
class _SpyCoordinator extends PostVideoCoordinator {
  _SpyCoordinator() : super(sessionFactory: (_) => _NullSession());

  int pauseAllCount = 0;
  int resumeAllCount = 0;

  @override
  void pauseAll() {
    pauseAllCount++;
    super.pauseAll();
  }

  @override
  void resumeAll() {
    resumeAllCount++;
    super.resumeAll();
  }
}

Map<String, dynamic> _videoPostJson() => {
      'id': 'flag-video-1',
      'slug': 'flag-video-1',
      'kind': 'USER_VIDEO',
      'videoUrl': 'https://example.com/flag-video-1.m3u8',
      'thumbnailUrl': 'https://example.com/flag-video-1.jpg',
      'durationSec': 10,
      'aspectRatio': 0.5625,
      'author': {'id': 'author-1', 'name': 'Tester'},
      'createdAt': '2026-07-18T00:00:00.000Z',
    };

Future<void> _pumpFeed(
  WidgetTester tester, {
  List<NavigatorObserver> observers = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: observers,
      routes: {
        '/member/login': (_) => const Scaffold(body: Text('Login')),
      },
      home: const FeedScreen(),
    ),
  );
  // Bounded pump — bootstrap dari cache; jangan pumpAndSettle (shimmer hang).
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

dynamic _feedState(WidgetTester tester) =>
    tester.state(find.byType(FeedScreen)) as dynamic;

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    // feedLocalStore singleton bertahan lintas-file dalam satu proses test —
    // tanpa reset ini, `_initialized` dari file lain membuat
    // `setMockInitialValues` di bawah diam-diam terabaikan.
    feedLocalStore.debugResetForTest();
    SharedPreferences.setMockInitialValues({
      'feed_offline_cache_v2': jsonEncode([_videoPostJson()]),
    });
    debugFeedCoordinatorFactory = null;
  });

  tearDown(() {
    debugFeedCoordinatorFactory = null;
  });

  testWidgets('coordinator selalu dibuat (flag dihapus, Langkah 7)',
      (tester) async {
    await _pumpFeed(tester);
    expect(_feedState(tester).debugVideoCoordinator, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('dispose screen men-dispose coordinator', (tester) async {
    final spy = _SpyCoordinator();
    debugFeedCoordinatorFactory = ({required sessionFactory}) => spy;
    await _pumpFeed(tester);
    expect(spy.isDisposed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(spy.isDisposed, isTrue,
        reason: 'feed_screen.dispose() → coordinator.dispose() sekali');
  });

  testWidgets('app background/foreground → pauseAll/resumeAll',
      (tester) async {
    final spy = _SpyCoordinator();
    debugFeedCoordinatorFactory = ({required sessionFactory}) => spy;
    await _pumpFeed(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    // >=1, bukan ==1: item managed (FeedVideoPostView) PUNYA
    // WidgetsBindingObserver sendiri yang JUGA melapor via onRequestPause →
    // coordinator.pauseAll() — defense-in-depth yang disengaja, bukan bug.
    // pauseAll idempotent, aman dipanggil berkali-kali.
    expect(spy.pauseAllCount, greaterThanOrEqualTo(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(spy.resumeAllCount, greaterThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('route opaque didorong/ditutup → pauseAll/resumeAll',
      (tester) async {
    final spy = _SpyCoordinator();
    debugFeedCoordinatorFactory = ({required sessionFactory}) => spy;
    await _pumpFeed(tester, observers: [appRouteObserver]);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Atas')),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // >=1: screen-level DAN item-level onRequestPause (RouteAware bawaan
    // FeedVideoPostView) sama-sama mendeteksi push yang SAMA — defense-in-
    // depth disengaja, lihat komentar di test lifecycle di atas.
    expect(spy.pauseAllCount, greaterThanOrEqualTo(1),
        reason: 'didPushNext → pauseAll');

    navigator.pop();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(spy.resumeAllCount, greaterThanOrEqualTo(1),
        reason: 'didPopNext → resumeAll');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
