import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_warm_handoff.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
import 'package:natalo_petshop_flutter/widgets/liquid_glass.dart';
import 'package:natalo_petshop_flutter/widgets/origin_expansion_route.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const hapticChannel = MethodChannel('haptic_feedback');
  final hapticCalls = <MethodCall>[];

  setUp(() {
    hapticCalls.clear();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hapticChannel, (call) async {
      hapticCalls.add(call);
      return null;
    });
    addTearDown(() {
      VisibilityDetectorController.instance.updateInterval =
          const Duration(milliseconds: 500);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hapticChannel, null);
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

  testWidgets('opens Postingan without entry haptic', (tester) async {
    final post = FeedPost.fromJson({
      'id': 'public-a',
      'slug': 'public-a',
      'kind': 'USER_PHOTO',
      'mediaUrl': 'https://example.com/public-a.jpg',
      'thumbnailUrl': 'https://example.com/public-a.jpg',
      'author': {'id': 'creator-1', 'name': 'Creator'},
      'createdAt': DateTime(2026, 7, 18).toIso8601String(),
    });
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
      ),
      posts: [post],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PublicProfileScreen(
          username: 'creator',
          initialResult: result,
          fetchChatConfig: _noOpFetch,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('profile-post-public-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    expect(hapticCalls.where((call) => call.method == 'light'), isEmpty);
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
    // Tab labels now render inside PublicProfileIdentityTabHeader's sliver
    // (Key('public_profile_tab_group')), not inside PublicProfileChromeOverlay
    // (which only owns the toolbar row since Task 2's refactor).
    final tabGroup = find.byKey(const Key('public_profile_tab_group'));
    expect(find.descendant(of: tabGroup, matching: find.text('Postingan')),
        findsOneWidget);
    expect(find.descendant(of: tabGroup, matching: find.text('Video')),
        findsOneWidget);
    expect(find.descendant(of: tabGroup, matching: find.text('Belanja')),
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
    // The header sliver list now leads with a PINNED spacer reserving
    // topPadding+toolbarHeight (fix for the tab-bar-under-status-bar
    // regression) — that spacer consumes real scroll extent before the
    // identity+tab sliver's own shrink begins, so every offset that targets
    // "N% through the identity shrink" must add this inset first.
    final headerLeadInset = metrics.topPadding + metrics.toolbarHeight;

    // Midway through the identity shrink — well before the grid can reach
    // the chrome — the glass must already be gradually fading in (never an
    // instant snap from 0 straight to full opacity).
    final midOffset = headerLeadInset + metrics.identityHeight * 0.75;
    outerPosition.jumpTo(midOffset);
    await tester.pump();
    expect(overlay().t, closeTo(0.75, 0.01));
    final midOpacities = tester
        .widgetList<LiquidGlass>(find.byType(LiquidGlass))
        .map((glass) => glass.opacity)
        .toList();
    expect(midOpacities, isNotEmpty);
    expect(midOpacities.any((o) => o > 0 && o < 1), isTrue);

    // One logical pixel beyond identity collapse is the first moment the real
    // grid enters beneath the collapsed chrome. Chrome and the tab bar now
    // share the exact same shrink progress `t` (the fix for the old
    // independent-timing bug that used to let the chrome glass lag behind),
    // so by the time t reaches 1 the glass has ALREADY finished fading in —
    // there is no frame where the grid is visible beneath a still-partial
    // chip.
    final intermediateOffset = headerLeadInset + metrics.identityHeight + 1;
    outerPosition.jumpTo(intermediateOffset);
    await tester.pump();
    final intermediateTile = tester.getRect(
      find.byKey(const ValueKey('profile-post-geometry-0')),
    );
    expect(overlay().t, 1.0);
    expect(intermediateTile.top, lessThan(metrics.collapsedChromeHeight));
    expect(intermediateTile.bottom, greaterThan(0));
    final intermediateOpacities = tester
        .widgetList<LiquidGlass>(find.byType(LiquidGlass))
        .map((glass) => glass.opacity)
        .toList();
    expect(intermediateOpacities, isNotEmpty);
    expect(intermediateOpacities.every((o) => o == 0 || o >= 0.99), isTrue);

    outerPosition.jumpTo(metrics.scrollSpaceHeight);
    await tester.pump();
    final collapsedTile = tester.getRect(
      find.byKey(const ValueKey('profile-post-geometry-0')),
    );
    expect(overlay().t, 1.0);
    expect(collapsedTile.top, lessThanOrEqualTo(0.5));
    expect(collapsedTile.bottom, greaterThan(0));
    expect(find.byType(BackdropFilter), findsWidgets);
    final collapsedOpacities = tester
        .widgetList<LiquidGlass>(find.byType(LiquidGlass))
        .map((glass) => glass.opacity)
        .toList();
    expect(collapsedOpacities.any((o) => o >= 0.99), isTrue);
  });
}

Future<void> _noOpFetch() async {}
