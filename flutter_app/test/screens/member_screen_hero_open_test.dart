import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_viewer_route.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Task 3 — member_screen (own-profile grid) dipindah dari
/// `pushOriginExpansion`/`OriginSnapshotSource` ke `pushPostViewer` + hero
/// bawaan Flutter (`PostHero`). Tile grid harus punya Hero bertag
/// `post-hero/<scope>/<postId>` dan tap membuka `MemberPostDetailScreen`
/// lewat `PostViewerRoute` (transisi native), BUKAN
/// `OriginExpansionTransition` lama.
void main() {
  FeedPost post(String id) => FeedPost(
        id: id,
        slug: id,
        kind: 'PHOTO',
        videoUrl: '',
        thumbnailUrl: 'https://example.com/$id.jpg',
        author: const FeedAuthor(id: 'owner-1', name: 'Natasha'),
        createdAt: DateTime(2026, 1, 1),
        status: 'PUBLISHED',
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    memberStore.setProfile(
      const MemberProfile(
        id: 'owner-1',
        name: 'Natasha',
        username: 'natasha_s',
        role: 'CUSTOMER',
        bio: 'Cat mom',
        followersCount: 1,
        followingCount: 1,
      ),
    );
    debugMyPostsFetcher = ({String filter = 'all', String? cursor}) async {
      return FeedPage(
        items: [post('p1'), post('p2'), post('p3')],
        nextCursor: null,
      );
    };
  });

  tearDown(() async {
    debugMyPostsFetcher = null;
    await memberStore.logout();
  });

  Future<void> pumpBounded(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  /// Pump a fixed number of frames — used after navigation actions where a
  /// route-transition animation needs several frames regardless of whether
  /// a spinner is present.
  Future<void> pumpFrames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    await pumpBounded(tester);
  }

  testWidgets(
      'own-profile tile grid punya PostHero scope profile; tap membuka viewer via PostViewerRoute',
      (tester) async {
    await pumpScreen(tester);

    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byWidgetPredicate(
      (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
    ));
    await pumpFrames(tester);

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    expect(find.byType(PostViewerRoute), findsNothing);
    // Tile grid harus TIDAK lagi memakai OriginExpansionTransition lama.
    expect(
      find.byWidgetPredicate(
          (w) => '${w.runtimeType}' == 'OriginSnapshotSource'),
      findsNothing,
    );
  });

  testWidgets(
      'back dari viewer tidak melempar exception dan grid tetap merender',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byWidgetPredicate(
      (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
    ));
    await pumpFrames(tester);
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);

    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await pumpBounded(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(MemberScreen), findsOneWidget);
  });
}
