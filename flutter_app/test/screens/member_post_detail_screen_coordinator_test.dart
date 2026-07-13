// T3a — verifikasi wiring inline video ↔ PostVideoCoordinator di halaman
// Postingan TANPA plugin native: `debugPostVideoSessionFactory` menyuntik
// fake [PlaybackSession] (tak butuh video_player), jadi kita bisa memeriksa
// attach/setActive/play, D3 (autoplay off tak auto-main), dan sinkronisasi
// mute — semua lewat interaksi widget nyata.
//
// Gotcha test repo ini: JANGAN pumpAndSettle (shimmer/AppProductImage tak
// pernah settle) → pakai bounded pump loop. SharedPreferences.setMockInitialValues
// + VisibilityDetector.updateInterval = 0.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _FakeSession implements PlaybackSession {
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  double volume = -1;
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

FeedPost _fakeVideoPost({String id = 'post-1'}) {
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
  late Map<String, _FakeSession> sessions;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    sessions = {};
    debugPostVideoSessionFactory = (id) {
      final s = _FakeSession();
      sessions[id] = s;
      return s;
    };
    // State default eksplisit — appSettingsStore singleton bisa bawa nilai
    // dari test sebelumnya di isolate yang sama.
    await appSettingsStore.setFeedAutoplay(true);
    await appSettingsStore.setFeedMuted(true);
  });

  tearDown(() {
    debugPostVideoSessionFactory = null;
  });

  Future<void> pumpScreen(WidgetTester tester, {List<FeedPost>? posts}) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final list = posts ?? [_fakeVideoPost()];
    await tester.pumpWidget(
      MaterialApp(
        home: MemberPostDetailScreen(post: list.first, posts: list),
      ),
    );
    // Bounded pump — biarkan VisibilityDetector fire + coordinator wiring.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets(
    'autoplay ON: inline attach + setActive → sesi dibuat & di-play, muted '
    'mengikuti feedMuted',
    (tester) async {
      await pumpScreen(tester);

      expect(sessions.containsKey('post-1'), isTrue,
          reason: 'inline yang terlihat harus attach → factory dipanggil');
      final s = sessions['post-1']!;
      expect(s.playCount, greaterThan(0),
          reason: 'setActive coordinator harus memutar sesi aktif');
      expect(s.playing, isTrue);
      // feedMuted true → sesi aktif volume 0 (§2.2).
      expect(s.volume, 0);

      await disposeTree(tester);
      // Coordinator dispose halaman → sesi di-dispose (satu-satunya pemilik).
      expect(s.disposeCount, 1);
    },
  );

  testWidgets(
    'D3: autoplay OFF → tidak auto-play (tombol play tampil); tap play memulai',
    (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      await pumpScreen(tester);

      // Tak ada sesi dibuat (tak attach), tombol play tampil.
      expect(sessions, isEmpty,
          reason: 'autoplay off: inline tidak boleh attach/putar otomatis');
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Tap play → attach + setActive.
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(sessions.containsKey('post-1'), isTrue);
      expect(sessions['post-1']!.playing, isTrue,
          reason: 'tap play harus memulai playback');

      await disposeTree(tester);
    },
  );

  testWidgets(
    'mute global re-apply ke sesi aktif (unmute → volume 1)',
    (tester) async {
      await pumpScreen(tester);
      final s = sessions['post-1']!;
      expect(s.volume, 0, reason: 'mula-mula muted');

      // Unmute global (ekuivalen tap tombol mute inline) → coordinator
      // listener menaikkan volume sesi AKTIF ke 1.
      await appSettingsStore.setFeedMuted(false);
      await tester.pump(const Duration(milliseconds: 20));
      expect(s.volume, 1);

      await appSettingsStore.setFeedMuted(true);
      await tester.pump(const Duration(milliseconds: 20));
      expect(s.volume, 0);

      await disposeTree(tester);
    },
  );
}
