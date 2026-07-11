// Widget tests for Task 4: "Postingan Terkait" tap-video → Flow A
// (ScopedVideoFeedScreen via pushScaledVideoFeed), tap-photo → unchanged
// MemberPostDetailScreen.
//
// TODO(video-nav-smooth-transitions): these are written as `skip: true`
// because `ProductDetailScreen` has no dependency-injection seam for its
// network layer — `productService`/`feedService` both funnel through the
// module-level `final ApiClient apiClient = ApiClient._()` singleton in
// lib/services/api_client.dart, which calls `package:http`'s top-level
// `http.get`/`http.post` directly (no injectable `http.Client`). There is
// no existing mock/harness for `product_detail_screen.dart` under
// flutter_app/test/ to mirror (checked before writing this file — none
// exists). Building a real end-to-end harness would require either (a)
// adding an injectable http.Client to ApiClient (out of scope for this
// leaf UI task) or (b) a disproportionately large fake-server rig. Per the
// task brief, this file documents the intended assertions with `skip: true`
// rather than inventing a fragile mock. `_CustomerPostCard` routing logic
// itself was verified via `flutter analyze` + manual code review (see
// sdd/task-4-report.md).
//
// Once ApiClient exposes an injectable http.Client (or a repository/DI
// seam is added), un-skip these tests and wire:
//   - productService.fetchProductFeedPosts → one VIDEO-kind post (for the
//     first test) / one PHOTO_CAROUSEL-kind post (for the second test)
//   - feedService.fetchPostById → a matching FeedPost
// then locate the tapped tile via `find.byIcon(Icons.play_arrow_rounded)`
// (video) or `find.byIcon(Icons.collections_rounded)` (photo) — see
// `_CustomerPostTypeBadge` in product_detail_screen.dart — and assert:
//   video tap  → find.byType(ScopedVideoFeedScreen) is pushed
//   photo tap  → find.byType(MemberPostDetailScreen) is pushed

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tapping a video related-post pushes ScopedVideoFeedScreen',
    (tester) async {},
    skip: true,
  );

  testWidgets(
    'tapping a photo related-post pushes MemberPostDetailScreen',
    (tester) async {},
    skip: true,
  );
}
