import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/scoped_video_feed_screen.dart';
import 'package:natalo_petshop_flutter/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Fake sesi plugin-free — tak punya controller nyata (bukan VideoPlayerSession)
/// → FeedVideoPostView managed merender thumbnail & tetap melapor intent. Cukup
/// untuk memverifikasi wiring coordinator (setActive/preloadNext/detach/evict).
class _FakeSession implements PlaybackSession {
  _FakeSession(this.postId);
  final String postId;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  double volume = 1;
  bool playing = false;
  Duration _pos = Duration.zero;

  @override
  Future<void> play() async {
    playCount++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    playing = false;
  }

  @override
  Future<void> seekTo(Duration position) async => _pos = position;

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> dispose() async => disposeCount++;

  @override
  Duration get position => _pos;
}

FeedPost _fakeVideoPost(String id) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': 0.5625,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  setUp(() {
    // Disable VisibilityDetector's internal debounce timer so it doesn't
    // leave a pending Timer past test teardown (it fires synchronously
    // instead when updateInterval is zero).
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('ScopedVideoFeedScreen opens at initialIndex', (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b'), _fakeVideoPost('c')];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(posts: posts, initialIndex: 1),
      ),
    );
    await tester.pump();
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.initialPage, 1);
    // VisibilityDetector schedules a debounced (500ms) internal timer on
    // paint; flush it so the test binding doesn't flag a pending timer at
    // teardown. pumpAndSettle() is avoided repo-wide because it hangs when
    // video/image/shimmer surfaces render (never settles).
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('drag past top boundary on first video dismisses the viewer',
      (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ScopedVideoFeedScreen(posts: posts, initialIndex: 0),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);

    // Drag DOWN well past the 72px overscroll threshold while on the
    // first video → viewer pops (ala IG Reels tarik-turun dari profil).
    await tester.drag(find.byType(PageView), const Offset(0, 300));
    // Pop fires immediately (NavigatorObserver confirms), but the exiting
    // route stays in the overlay through the reverse transition + the
    // overscroll ballistic settle (~600-800ms) — pump bounded until gone.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsNothing,
        reason: 'overscroll drag at the first video should close the viewer');

    await tester.pump(const Duration(milliseconds: 600));
  });

  // ── T7 — full-managed: semua item terikat coordinator, preload next,
  //    urutan transisi deterministik, maks 3 sesi, nol dobel controller ──
  group('T7 full-managed', () {
    late Map<String, _FakeSession> sessions;
    late Map<String, int> createCount;
    late PostVideoCoordinator coordinator;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      sessions = {};
      createCount = {};
      await appSettingsStore.setFeedMuted(true);
      await appSettingsStore.setFeedVideoQuality('auto');
      coordinator = PostVideoCoordinator(
        sessionFactory: (id) {
          createCount[id] = (createCount[id] ?? 0) + 1;
          final s = _FakeSession(id);
          sessions[id] = s;
          return s;
        },
      );
    });

    tearDown(() {
      if (!coordinator.isDisposed) coordinator.dispose();
    });

    Future<void> pumpScoped(
      WidgetTester tester, {
      required List<FeedPost> posts,
      int initialIndex = 0,
    }) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Simulasi handoff Postingan: origin (halaman awal) pinned.
      coordinator.setOrigin(posts[initialIndex].id);
      await tester.pumpWidget(
        MaterialApp(
          home: ScopedVideoFeedScreen(
            posts: posts,
            initialIndex: initialIndex,
            coordinator: coordinator,
            originPostId: posts[initialIndex].id,
          ),
        ),
      );
      // Bounded pump — postFrameCallback aktivasi awal + VisibilityDetector.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    Future<void> swipeNext(WidgetTester tester) async {
      await tester.drag(find.byType(PageView), const Offset(0, -900),
          warnIfMissed: false);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    testWidgets(
      'aktivasi awal: origin active + preload next (semua item managed)',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);

        expect(coordinator.activePostId, 'a',
            reason: 'halaman awal jadi active');
        expect(sessions['a']!.playing, isTrue,
            reason: 'origin di-play oleh setActive');
        // Preload next (b) — bukan data saver.
        expect(coordinator.preloadPostId, 'b');
        expect(sessions.containsKey('b'), isTrue);
        expect(sessions['b']!.playing, isFalse,
            reason: 'preload lahir paused + muted');
      },
    );

    testWidgets(
      'swipe A→B: B pakai sesi preload (createCount B tetap 1, tak dibuat ulang)',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);
        expect(createCount['b'], 1, reason: 'B dipreload sekali di aktivasi awal');

        await swipeNext(tester);

        expect(coordinator.activePostId, 'b');
        expect(sessions['b']!.playing, isTrue);
        expect(createCount['b'], 1,
            reason: 'B jadi active pakai sesi preload — TIDAK dibuat ulang');
        // Nol dobel controller: setiap id maksimum 1 sesi dibuat.
        for (final entry in createCount.entries) {
          expect(entry.value, 1, reason: 'id ${entry.key} tak boleh dobel sesi');
        }
      },
    );

    testWidgets(
      'swipe berkali-kali → maks 3 sesi hidup (origin+active+next), nol dobel',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
          _fakeVideoPost('d'),
          _fakeVideoPost('e'),
        ];
        await pumpScoped(tester, posts: posts);

        await swipeNext(tester); // a→b
        await swipeNext(tester); // b→c
        await swipeNext(tester); // c→d

        expect(coordinator.livePostIds.length, lessThanOrEqualTo(3),
            reason: 'maks 3 sesi: origin + active + next');
        // Origin (a) tetap hidup (pinned) untuk kembali ke Postingan.
        expect(coordinator.livePostIds, contains('a'));
        expect(sessions['a']!.disposeCount, 0);
        // Nol dobel controller sepanjang swipe.
        for (final entry in createCount.entries) {
          expect(entry.value, 1, reason: 'id ${entry.key} tak boleh dobel sesi');
        }
      },
    );

    testWidgets(
      'data saver: preloadNext DILEWATI — swipe bikin sesi saat itu (1 sesi/id)',
      (tester) async {
        await appSettingsStore.setFeedVideoQuality('data_saver');
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);

        // Aktivasi awal TIDAK preload B (data saver).
        expect(coordinator.preloadPostId, isNull);
        expect(sessions.containsKey('b'), isFalse,
            reason: 'data saver → tak ada preload sebelum swipe');

        await swipeNext(tester); // a→b: setActive bikin sesi B saat itu

        expect(coordinator.activePostId, 'b');
        expect(createCount['b'], 1, reason: 'B dibuat sekali (satu controller)');
        // Masih tak ada preload C.
        expect(coordinator.preloadPostId, isNull);
        expect(sessions.containsKey('c'), isFalse);
      },
    );

    testWidgets(
      'kembali ke Postingan: origin (pinned) TIDAK di-dispose saat viewer tutup',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);
        await swipeNext(tester); // a→b, origin a tetap pinned

        // Tutup viewer (dispose screen) — origin masih pinned via setOrigin.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 30));

        expect(sessions['a']!.disposeCount, 0,
            reason: 'origin hidup → inline lanjut di timestamp saat kembali');
        // Coordinator (milik halaman Postingan) belum dispose di test ini.
        expect(coordinator.sessionFor('a'), same(sessions['a']));
      },
    );
  });
}
