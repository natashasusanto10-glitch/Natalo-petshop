import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/scoped_video_feed_screen.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
    final posts = [
      _fakeVideoPost('a'),
      _fakeVideoPost('b'),
      _fakeVideoPost('c'),
    ];
    await tester.pumpWidget(
      MaterialApp(home: ScopedVideoFeedScreen(posts: posts, initialIndex: 1)),
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

  testWidgets('drag past top boundary on first video dismisses the viewer', (
    tester,
  ) async {
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
    expect(
      find.byType(ScopedVideoFeedScreen),
      findsNothing,
      reason: 'overscroll drag at the first video should close the viewer',
    );

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('swipe right dismisses fullscreen viewer', (tester) async {
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

    await tester.dragFrom(const Offset(100, 400), const Offset(220, 0));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
  });
}
