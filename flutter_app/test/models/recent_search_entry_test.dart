import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/recent_search_entry.dart';
import 'package:natalo_petshop_flutter/services/follow_service.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

void main() {
  group('RecentSearchEntry', () {
    test('Hashtag round-trip: toJson/fromJson preserves all fields', () {
      // Arrange
      const hashtag = RecentSearchEntry.hashtag(
        HashtagSuggestion(name: 'petshop', postCount: 42),
      );

      // Act
      final json = hashtag.toJson();
      final reconstructed = RecentSearchEntry.fromJson(json);

      // Assert
      expect(reconstructed.isHashtag, true);
      expect(reconstructed.hashtag!.name, 'petshop');
      expect(reconstructed.hashtag!.postCount, 42);
    });

    test('User round-trip: toJson/fromJson preserves all fields', () {
      // Arrange
      const user = RecentSearchEntry.user(
        FollowUserSummary(
          id: 'user123',
          name: 'John Doe',
          username: 'johndoe',
          profilePhotoUrl: 'https://example.com/photo.jpg',
          bio: 'A pet lover',
          followersCount: 10,
          followingCount: 5,
          isFollowing: true,
          isSelf: false,
          isOfficial: false,
        ),
      );

      // Act
      final json = user.toJson();
      final reconstructed = RecentSearchEntry.fromJson(json);

      // Assert
      expect(reconstructed.isHashtag, false);
      expect(reconstructed.user, isNotNull);
      expect(reconstructed.user!.id, 'user123');
      expect(reconstructed.user!.name, 'John Doe');
      expect(reconstructed.user!.username, 'johndoe');
      expect(reconstructed.user!.profilePhotoUrl,
          'https://example.com/photo.jpg');
      expect(reconstructed.user!.bio, 'A pet lover');
      expect(reconstructed.user!.followersCount, 10);
      expect(reconstructed.user!.followingCount, 5);
      expect(reconstructed.user!.isFollowing, true);
      expect(reconstructed.user!.isSelf, false);
      expect(reconstructed.user!.isOfficial, false);
    });

    test('Legacy JSON without type field defaults to user (backward compat)',
        () {
      // Arrange: old FollowUserSummary.toJson() blob with no type field
      final legacyJson = {
        'id': 'legacy-user-456',
        'name': 'Jane Smith',
        'username': 'janesmith',
        'profilePhotoUrl': 'https://example.com/jane.jpg',
        'bio': 'Pet enthusiast',
        'followersCount': 100,
        'followingCount': 20,
        'isFollowing': false,
        'isSelf': false,
        'isOfficial': false,
      };

      // Act
      final entry = RecentSearchEntry.fromJson(legacyJson);

      // Assert
      expect(entry.isHashtag, false,
          reason: 'Legacy JSON with no type should default to user');
      expect(entry.user, isNotNull);
      expect(entry.user!.id, 'legacy-user-456');
      expect(entry.user!.name, 'Jane Smith');
      expect(entry.user!.username, 'janesmith');
      expect(entry.user!.followersCount, 100);
    });
  });
}
