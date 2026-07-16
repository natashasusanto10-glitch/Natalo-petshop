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

void main() {
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
}
