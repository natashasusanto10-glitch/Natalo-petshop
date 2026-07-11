import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
}
