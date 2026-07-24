import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/recent_search_entry.dart';
import 'package:natalo_petshop_flutter/services/follow_service.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

void main() {
  group('RecentSearchEntry', () {
    test('Hashtag round-trip: toJson/fromJson preserves all fields', () {
      // Arrange
      final hashtag = RecentSearchEntry.hashtag(
        name: 'petshop',
        postCount: 42,
      );

      // Act
      final json = hashtag.toJson();
      final reconstructed = RecentSearchEntry.fromJson(json);

      // Assert
      expect(reconstructed.isHashtag, true);
      expect(reconstructed.name, 'petshop');
      expect(reconstructed.postCount, 42);
    });

    test('User round-trip: toJson/fromJson preserves all fields', () {
      // Arrange
      final user = RecentSearchEntry.user(
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
      expect(reconstructed.userSummary, isNotNull);
      expect(reconstructed.userSummary!.id, 'user123');
      expect(reconstructed.userSummary!.name, 'John Doe');
      expect(reconstructed.userSummary!.username, 'johndoe');
      expect(reconstructed.userSummary!.profilePhotoUrl,
          'https://example.com/photo.jpg');
      expect(reconstructed.userSummary!.bio, 'A pet lover');
      expect(reconstructed.userSummary!.followersCount, 10);
      expect(reconstructed.userSummary!.followingCount, 5);
      expect(reconstructed.userSummary!.isFollowing, true);
      expect(reconstructed.userSummary!.isSelf, false);
      expect(reconstructed.userSummary!.isOfficial, false);
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
      expect(entry.userSummary, isNotNull);
      expect(entry.userSummary!.id, 'legacy-user-456');
      expect(entry.userSummary!.name, 'Jane Smith');
      expect(entry.userSummary!.username, 'janesmith');
      expect(entry.userSummary!.followersCount, 100);
    });
  });
}
