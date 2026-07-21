// Task 2 — viewer pakai PostHero ber-scope (foto/carousel/video) +
// onWillClose sinkron saat pop. Konvensi sama dengan
// member_post_detail_screen_coordinator_test.dart: SharedPreferences mock,
// debugPostVideoSessionFactory seam (tanpa plugin video_player nyata),
// bounded pump loop — JANGAN pumpAndSettle (shimmer tak pernah settle).

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
  bool playing = false;
  Duration _pos = Duration.zero;

  @override
  Future<void> play() async {
    playCount++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> seekTo(Duration position) async => _pos = position;

  @override
  Future<void> setVolume(double v) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}

  @override
  Duration get position => _pos;
}

FeedPost _fakePhotoPost({String id = 'p1'}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'mediaUrl': 'https://example.com/$id.jpg',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'aspectRatio': 1.0,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

FeedPost _fakeVideoPost({String id = 'p2'}) {
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
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    debugPostVideoSessionFactory = (id) => _FakeSession();
    await appSettingsStore.setFeedAutoplay(true);
    await appSettingsStore.setFeedMuted(true);
  });

  tearDown(() {
    debugPostVideoSessionFactory = null;
    debugPostVideoSessionUrlObserver = null;
    debugScopedFeedPostFetcher = null;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<FeedPost> posts,
    String? heroScope,
    void Function(String)? onWillClose,
  }) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MemberPostDetailScreen(
                      post: posts.first,
                      posts: posts,
                      heroScope: heroScope,
                      onWillClose: onWillClose,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets(
    'slot foto & video dibungkus PostHero ber-scope saat heroScope diberikan',
    (tester) async {
      final postFoto = _fakePhotoPost(id: 'p1');
      final postVideo = _fakeVideoPost(id: 'p2');
      await pumpScreen(
        tester,
        posts: [postFoto, postVideo],
        heroScope: 'profile',
      );

      final heroes = tester.widgetList<Hero>(find.byType(Hero)).toList();
      expect(heroes.map((h) => h.tag), contains('post-hero/profile/p1'));
      expect(heroes.every((h) => h.transitionOnUserGestures), isTrue);
      expect(
        find.byWidgetPredicate(
          (w) => w is Hero && w.tag == 'post-thumb-p1',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'tanpa heroScope tidak ada PostHero (deep-link aman dari tag duplikat)',
    (tester) async {
      final postFoto = _fakePhotoPost(id: 'p1');
      await pumpScreen(tester, posts: [postFoto]);

      expect(
        find.byWidgetPredicate(
          (w) => w is Hero && (w.tag as String).startsWith('post-hero/'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('onWillClose menerima post AKTIF saat back', (tester) async {
    String? closedWith;
    final postFoto = _fakePhotoPost(id: 'p1');
    await pumpScreen(
      tester,
      posts: [postFoto],
      heroScope: 'profile',
      onWillClose: (id) => closedWith = id,
    );

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(closedWith, 'p1');
  });
}
