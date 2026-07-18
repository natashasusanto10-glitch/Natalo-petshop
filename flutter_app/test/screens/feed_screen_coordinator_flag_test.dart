// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/utils/app_route_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Langkah 3 (migrasi Feed→PostVideoCoordinator, Opsi D): coordinator +
/// wiring lifecycle di LEVEL feed_screen, DI BALIK feature flag DEFAULT OFF.
/// Nol perubahan user-facing — coordinator belum dipakai widget item.

/// Coordinator mata-mata: menghitung pauseAll/resumeAll supaya wiring
/// lifecycle bisa diverifikasi tanpa sesi hidup.
class _SpyCoordinator extends PostVideoCoordinator {
  _SpyCoordinator()
      : super(sessionFactory: (_) => throw StateError('tak dipakai di Step 3'));

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
    SharedPreferences.setMockInitialValues({
      'feed_offline_cache_v2': jsonEncode([_videoPostJson()]),
    });
    debugFeedCoordinatorEnabledOverride = null;
    debugFeedCoordinatorFactory = null;
  });

  tearDown(() {
    debugFeedCoordinatorEnabledOverride = null;
    debugFeedCoordinatorFactory = null;
  });

  test('feedCoordinatorEnabled default OFF; override memaksa', () {
    expect(feedCoordinatorEnabled(), isFalse);
    debugFeedCoordinatorEnabledOverride = true;
    expect(feedCoordinatorEnabled(), isTrue);
    debugFeedCoordinatorEnabledOverride = false;
    expect(feedCoordinatorEnabled(), isFalse);
    debugFeedCoordinatorEnabledOverride = null;
  });

  testWidgets('flag OFF (default) → tak ada coordinator', (tester) async {
    await _pumpFeed(tester);
    expect(_feedState(tester).debugVideoCoordinator, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('flag ON → coordinator dibuat', (tester) async {
    debugFeedCoordinatorEnabledOverride = true;
    await _pumpFeed(tester);
    expect(_feedState(tester).debugVideoCoordinator, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('flag ON → dispose screen men-dispose coordinator',
      (tester) async {
    debugFeedCoordinatorEnabledOverride = true;
    final spy = _SpyCoordinator();
    debugFeedCoordinatorFactory = ({required sessionFactory}) => spy;
    await _pumpFeed(tester);
    expect(spy.isDisposed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(spy.isDisposed, isTrue,
        reason: 'feed_screen.dispose() → coordinator.dispose() sekali');
  });

  testWidgets('flag ON → app background/foreground → pauseAll/resumeAll',
      (tester) async {
    debugFeedCoordinatorEnabledOverride = true;
    final spy = _SpyCoordinator();
    debugFeedCoordinatorFactory = ({required sessionFactory}) => spy;
    await _pumpFeed(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(spy.pauseAllCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(spy.resumeAllCount, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('flag ON → route opaque didorong/ditutup → pauseAll/resumeAll',
      (tester) async {
    debugFeedCoordinatorEnabledOverride = true;
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
    expect(spy.pauseAllCount, 1, reason: 'didPushNext → pauseAll');

    navigator.pop();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(spy.resumeAllCount, 1, reason: 'didPopNext → resumeAll');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('flag OFF → app lifecycle TIDAK crash (tak ada coordinator)',
      (tester) async {
    await _pumpFeed(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    // Tak ada assertion selain "tak crash" — flag OFF = wiring lifecycle mati.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
