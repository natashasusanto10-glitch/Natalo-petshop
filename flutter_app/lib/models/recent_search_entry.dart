import '../services/feed_service.dart';
import '../services/follow_service.dart';

/// Union-style entry in recent search history: either a user OR a hashtag.
///
/// Supports JSON round-trip via toJson()/fromJson(), with backward
/// compatibility for legacy entries stored as plain FollowUserSummary.toJson()
/// blobs (no 'type' field). Legacy entries default to user type.
class RecentSearchEntry {
  final FollowUserSummary? user;
  final HashtagSuggestion? hashtag;

  const RecentSearchEntry.user(FollowUserSummary this.user) : hashtag = null;
  const RecentSearchEntry.hashtag(HashtagSuggestion this.hashtag)
      : user = null;

  bool get isHashtag => hashtag != null;

  /// Identity untuk dedupe recent.
  String get key => isHashtag ? 'hashtag:${hashtag!.name}' : 'user:${user!.id}';

  Map<String, dynamic> toJson() => isHashtag
      ? {
          'type': 'hashtag',
          'name': hashtag!.name,
          'postCount': hashtag!.postCount,
        }
      : {'type': 'user', ...user!.toJson()};

  factory RecentSearchEntry.fromJson(Map<String, dynamic> json) {
    if (json['type'] == 'hashtag') {
      return RecentSearchEntry.hashtag(
        HashtagSuggestion(
          name: (json['name'] as String?) ?? '',
          postCount: (json['postCount'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    // 'user' eksplisit ATAU legacy tanpa 'type' → user.
    return RecentSearchEntry.user(FollowUserSummary.fromJson(json));
  }
}
