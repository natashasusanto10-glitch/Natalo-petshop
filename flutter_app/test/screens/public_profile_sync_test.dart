import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO',
      'author': {'id': 'author-$id', 'name': 'Tester'},
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

void main() {
  test('profile follow snapshot is neutralized for a new viewer', () {
    const profile = PublicProfile(
      id: 'profile-1',
      name: 'Creator',
      isFollowing: true,
      isOwner: false,
    );

    final otherViewer = rebasePublicProfileForViewer(
      profile,
      viewerId: 'viewer-2',
    );
    final ownerViewer = rebasePublicProfileForViewer(
      profile,
      viewerId: 'profile-1',
    );

    expect(otherViewer.isFollowing, isFalse);
    expect(otherViewer.isOwner, isFalse);
    expect(ownerViewer.isFollowing, isFalse);
    expect(ownerViewer.isOwner, isTrue);
  });

  test('viewer rebase clears viewer-specific mutual followers', () {
    const profile = PublicProfile(
      id: 'official-1',
      name: 'Natalo Petshop Official',
      isOfficial: true,
      mutualFollowers: PublicProfileMutualSummary(
        items: [
          PublicProfileMutualFollower(id: 'user-1', name: 'Mona'),
        ],
        totalCount: 1,
      ),
    );
    final rebased = rebasePublicProfileForViewer(
      profile,
      viewerId: 'viewer-2',
    );
    expect(rebased.mutualFollowers, PublicProfileMutualSummary.empty);
  });

  test('explicitly removed post cannot fall back from stale profile list', () {
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) => Future.value(saved),
    );
    final post = _post('removed-post');
    store.seed([post]);
    final staleFetchStarted = DateTime.now().subtract(
      const Duration(seconds: 1),
    );

    store.removePost(post.id);
    store.mergeFromServer([post], fetchedAt: staleFetchStarted);

    expect(
      canonicalizePublicProfilePosts([post], store: store),
      isEmpty,
    );
    store.dispose();
  });
}
