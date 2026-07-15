import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _fakeVideoPost({
  String id = 'post-1',
  double aspectRatio = 0.5625,
  String? videoAltText,
}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': aspectRatio,
    'videoAltText': videoAltText,
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

  testWidgets('media surface exposes explicit alt text semantics',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(
            videoAltText: 'Kucing putih sedang makan dari mangkuk biru',
          ),
          isActive: false,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Kucing putih sedang makan dari mangkuk biru'),
      findsOneWidget,
    );
  });

  // Aturan fit ala IG Reels: video ±9:16 → cover full-bleed (crop tipis);
  // video lebih pendek (4:5 / square / landscape) → contain letterbox,
  // supaya tidak terasa "zoom". Diverifikasi lewat thumbnail background
  // (jalur pra-video), yang WAJIB mengikuti aturan yang sama dengan
  // player supaya tidak ada lompatan cover→contain saat video siap.
  Future<BoxFit?> pumpAndReadThumbFit(
      WidgetTester tester, double aspectRatio) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(aspectRatio: aspectRatio),
          isActive: false,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .where((w) => w.imageUrl.endsWith('.jpg'));
    return images.isEmpty ? null : images.first.fit;
  }

  testWidgets('video 9:16 → background cover (full-bleed ala IG)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 0.5625);
    expect(fit, BoxFit.cover);
  });

  testWidgets('video square → background contain (letterbox, bukan zoom)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 1.0);
    expect(fit, BoxFit.contain);
  });

  testWidgets('video 4:5 → background contain (letterbox, bukan zoom)',
      (tester) async {
    final fit = await pumpAndReadThumbFit(tester, 0.8);
    expect(fit, BoxFit.contain);
  });
}
