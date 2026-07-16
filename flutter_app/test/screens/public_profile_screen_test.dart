import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_warm_handoff.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
import 'package:natalo_petshop_flutter/widgets/origin_expansion_route.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() {
      VisibilityDetectorController.instance.updateInterval =
          const Duration(milliseconds: 500);
    });
  });

  testWidgets('entry refreshes chat config exactly once', (tester) async {
    var fetchCount = 0;
    const result = PublicProfileResult(
      profile: PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        isOwner: true,
      ),
      posts: [],
    );
    final screen = PublicProfileScreen(
      username: 'creator',
      initialResult: result,
      fetchChatConfig: () async => fetchCount++,
    );

    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpWidget(MaterialApp(home: screen));

    expect(fetchCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('public profile tile keys stay stable and scoped to their content tab',
      () {
    final keys = ProfilePostOriginKeyCache();

    final allTile = keys.forPost(PublicProfileContentFilter.all, 'video-1');

    expect(
      keys.forPost(PublicProfileContentFilter.all, 'video-1'),
      same(allTile),
    );
    expect(
      keys.forPost(PublicProfileContentFilter.video, 'video-1'),
      isNot(same(allTile)),
    );
  });

  testWidgets('video tile opens Postingan through origin expansion and returns',
      (tester) async {
    final reverseSnapshotStatuses = <AnimationStatus>[];
    debugOriginExpansionStatusObserver = (status, hasSnapshot) {
      if (hasSnapshot) reverseSnapshotStatuses.add(status);
    };
    addTearDown(() => debugOriginExpansionStatusObserver = null);
    final post = FeedPost.fromJson({
      'id': 'video-1',
      'slug': 'video-1',
      'kind': 'USER_VIDEO',
      'videoUrl': 'https://example.com/video-1.mp4',
      'thumbnailUrl': 'https://example.com/video-1.jpg',
      'author': {'id': 'creator-1', 'name': 'Creator'},
      'createdAt': DateTime(2026).toIso8601String(),
    });
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        isOwner: true,
      ),
      posts: [post],
    );
    var disposeCount = 0;
    final warmSession = VideoPlayerSession(
      url: post.videoPlaybackUrl,
      debugInitAttempt: (_) async {},
      debugDisposePlayer: () async => disposeCount++,
    );
    final warmHandoff = PostVideoWarmHandoff(
      postId: post.id,
      url: post.videoPlaybackUrl,
      hasAudio: post.hasAudio != false,
      session: warmSession,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PublicProfileScreen(
          username: 'creator',
          initialResult: result,
          warmHandoffFactory: (_) => warmHandoff,
          fetchChatConfig: _noOpFetch,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('profile-post-video-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byKey(const ValueKey('origin-expansion-snapshot')),
        findsOneWidget);
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    final detailState =
        tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
    expect(detailState.debugVideoCoordinator.sessionFor(post.id),
        same(warmSession));
    expect(disposeCount, 0);

    Navigator.of(tester.element(find.byType(MemberPostDetailScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(reverseSnapshotStatuses, contains(AnimationStatus.reverse));

    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byType(MemberPostDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('profile-post-video-1')), findsOneWidget);
  });

  testWidgets(
      'real scroll collapses and reverses chrome without resetting content',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'post-1',
      'slug': 'post-1',
      'kind': 'USER_VIDEO',
      'videoUrl': 'https://example.com/post-1.mp4',
      'thumbnailUrl': 'not-a-network-url',
      'author': {'id': 'creator-1', 'name': 'Creator'},
      'createdAt': DateTime(2026).toIso8601String(),
    });
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        bio: 'Profil kreator',
        isOwner: true,
      ),
      posts: [post],
    );

    await tester.pumpWidget(MaterialApp(
      home: PublicProfileScreen(
        username: 'creator',
        initialResult: result,
        fetchChatConfig: _noOpFetch,
      ),
    ));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNull);
    expect(
        find.byKey(const Key('public_profile_grid_underlay')), findsOneWidget);
    expect(find.byType(PublicProfileChromeOverlay), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-post-post-1')), findsOneWidget);

    await tester.drag(find.byType(TabBarView), const Offset(-420, 0));
    await tester.pumpAndSettle();

    final videoSelected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Video'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(videoSelected.properties.selected, isTrue);

    final scrollView = find.byType(NestedScrollView);
    final dragPoint = tester.getBottomLeft(scrollView) + const Offset(200, -80);
    await tester.dragFrom(dragPoint, const Offset(0, -360));
    await tester.pump();
    final chrome = find.byType(PublicProfileChromeOverlay);
    expect(find.descendant(of: chrome, matching: find.text('Postingan')),
        findsOneWidget);
    expect(find.descendant(of: chrome, matching: find.text('Video')),
        findsOneWidget);
    expect(find.descendant(of: chrome, matching: find.text('Belanja')),
        findsOneWidget);

    final selected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Video'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(selected.properties.selected, isTrue);

    await tester.dragFrom(dragPoint, const Offset(0, 360));
    await tester.pump();
    final reversedSelected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Video'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(reversedSelected.properties.selected, isTrue);

    await tester.tap(find.byTooltip('Postingan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('profile-post-post-1')), findsOneWidget);
  });

  testWidgets('real grid enters glass chrome before full collapse',
      (tester) async {
    final posts = List.generate(18, (index) {
      return FeedPost.fromJson({
        'id': 'geometry-$index',
        'slug': 'geometry-$index',
        'kind': 'USER_VIDEO',
        'videoUrl': 'https://example.com/geometry-$index.mp4',
        'thumbnailUrl': 'not-a-network-url',
        'author': {'id': 'creator-1', 'name': 'Creator'},
        'createdAt': DateTime(2026).toIso8601String(),
      });
    });
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        bio: 'Profil kreator',
        isOwner: true,
      ),
      posts: posts,
    );

    await tester.pumpWidget(MaterialApp(
      home: PublicProfileScreen(
        username: 'creator',
        initialResult: result,
        fetchChatConfig: _noOpFetch,
      ),
    ));
    await tester.pump();

    final overlayFinder = find.byType(PublicProfileChromeOverlay);
    PublicProfileChromeOverlay overlay() =>
        tester.widget<PublicProfileChromeOverlay>(overlayFinder);
    final nestedScrollables = find.descendant(
      of: find.byType(NestedScrollView),
      matching: find.byType(Scrollable),
    );
    final outerPosition =
        tester.state<ScrollableState>(nestedScrollables.first).position;
    final metrics = overlay().metrics;

    // One logical pixel beyond identity collapse is the first moment the real
    // grid enters beneath the collapsed chrome. The glass must still be in an
    // intermediate phase here, not already snapped to its endpoint.
    final intermediateOffset = metrics.identityHeight + 1;
    outerPosition.jumpTo(intermediateOffset);
    await tester.pump();
    final intermediateTile = tester.getRect(
      find.byKey(const ValueKey('profile-post-geometry-0')),
    );
    expect(overlay().scrollOffset, closeTo(intermediateOffset, 0.5));
    expect(intermediateTile.top, lessThan(metrics.collapsedChromeHeight));
    expect(intermediateTile.bottom, greaterThan(0));
    final intermediateTint = tester.widget<ColoredBox>(
      find.byKey(const Key('public_profile_glass_tint')),
    );
    expect(intermediateTint.color.a, greaterThan(0));
    expect(intermediateTint.color.a, lessThan(0.72));

    outerPosition.jumpTo(metrics.scrollSpaceHeight);
    await tester.pump();
    final collapsedTile = tester.getRect(
      find.byKey(const ValueKey('profile-post-geometry-0')),
    );
    expect(overlay().scrollOffset, closeTo(metrics.scrollSpaceHeight, 0.5));
    expect(collapsedTile.top, lessThanOrEqualTo(0.5));
    expect(collapsedTile.bottom, greaterThan(0));
    expect(find.byType(BackdropFilter), findsOneWidget);
    final collapsedTint = tester.widget<ColoredBox>(
      find.byKey(const Key('public_profile_glass_tint')),
    );
    expect(collapsedTint.color.a, closeTo(0.72, 0.01));
  });
}

Future<void> _noOpFetch() async {}
