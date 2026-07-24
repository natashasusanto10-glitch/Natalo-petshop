import '../services/follow_service.dart';

/// Union-style entry in recent search history: either a user OR a hashtag.
///
/// Supports JSON round-trip via toJson()/fromJson(), with backward
/// compatibility for legacy entries stored as plain FollowUserSummary.toJson()
/// blobs (no 'type' field). Legacy entries default to user type.
class RecentSearchEntry {
  /// 'user' or 'hashtag'
  final String type;

  /// User data (non-null iff type == 'user')
  final FollowUserSummary? userSummary;

  /// Hashtag name (non-null iff type == 'hashtag')
  final String? _hashtagName;

  /// Post count for hashtag (non-null iff type == 'hashtag')
  final int? _hashtagPostCount;

  const RecentSearchEntry._({
    required this.type,
    this.userSummary,
    String? hashtagName,
    int? hashtagPostCount,
  })  : _hashtagName = hashtagName,
        _hashtagPostCount = hashtagPostCount;

  /// Create a user recent search entry
  factory RecentSearchEntry.user(FollowUserSummary userSummary) {
    return RecentSearchEntry._(
      type: 'user',
      userSummary: userSummary,
    );
  }

  /// Create a hashtag recent search entry
  factory RecentSearchEntry.hashtag({
    required String name,
    required int postCount,
  }) {
    return RecentSearchEntry._(
      type: 'hashtag',
      hashtagName: name,
      hashtagPostCount: postCount,
    );
  }

  bool get isHashtag => type == 'hashtag';

  bool get isUser => type == 'user';

  /// Hashtag name. Only valid when isHashtag == true.
  String get name {
    assert(isHashtag, 'name is only valid for hashtag entries');
    return _hashtagName ?? '';
  }

  /// Post count for hashtag. Only valid when isHashtag == true.
  int get postCount {
    assert(isHashtag, 'postCount is only valid for hashtag entries');
    return _hashtagPostCount ?? 0;
  }

  /// Serialize to JSON with explicit type field for forward compatibility.
  Map<String, dynamic> toJson() {
    if (isHashtag) {
      return {
        'type': 'hashtag',
        'name': _hashtagName,
        'postCount': _hashtagPostCount,
      };
    } else {
      return {
        'type': 'user',
        ...userSummary?.toJson() ?? {},
      };
    }
  }

  /// Deserialize from JSON, with backward compatibility for legacy user entries.
  ///
  /// If json has no 'type' field or type is unrecognized, assumes it's a
  /// legacy FollowUserSummary and defaults to user type.
  factory RecentSearchEntry.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;

    if (type == 'hashtag') {
      return RecentSearchEntry.hashtag(
        name: (json['name'] as String?) ?? '',
        postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      );
    }

    // Default to user type for missing/unrecognized type (backward compat)
    final userSummary = FollowUserSummary.fromJson(json);
    return RecentSearchEntry.user(userSummary);
  }
}
