import '../constants/official_brand.dart';

class PublicProfileMutualFollower {
  final String id;
  final String name;
  final String? username;
  final String? profilePhotoUrl;
  final bool isOfficial;

  const PublicProfileMutualFollower({
    required this.id,
    required this.name,
    this.username,
    this.profilePhotoUrl,
    this.isOfficial = false,
  });

  factory PublicProfileMutualFollower.fromJson(Map<String, dynamic> json) {
    return PublicProfileMutualFollower(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      username: _nullableString(json['username']),
      profilePhotoUrl: _nullableString(json['profilePhotoUrl']),
      isOfficial: json['isOfficial'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileMutualFollower &&
          other.id == id &&
          other.name == name &&
          other.username == username &&
          other.profilePhotoUrl == profilePhotoUrl &&
          other.isOfficial == isOfficial;

  @override
  int get hashCode =>
      Object.hash(id, name, username, profilePhotoUrl, isOfficial);
}

class PublicProfileMutualSummary {
  final List<PublicProfileMutualFollower> items;
  final int totalCount;

  const PublicProfileMutualSummary({
    this.items = const [],
    this.totalCount = 0,
  });

  static const empty = PublicProfileMutualSummary();

  factory PublicProfileMutualSummary.fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic> || raw['items'] is! List) return empty;
    final items = <PublicProfileMutualFollower>[];
    for (final item in raw['items'] as List) {
      if (item is Map<String, dynamic>) {
        final parsed = PublicProfileMutualFollower.fromJson(item);
        if (parsed.id.isNotEmpty && parsed.name.isNotEmpty) items.add(parsed);
      }
    }
    final rawCount = raw['totalCount'];
    final parsedCount =
        rawCount is num && rawCount.isFinite ? rawCount.toInt() : 0;
    return PublicProfileMutualSummary(
      items: List.unmodifiable(items),
      totalCount: parsedCount < items.length ? items.length : parsedCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileMutualSummary &&
          other.totalCount == totalCount &&
          _sameMutualItems(other.items, items);

  @override
  int get hashCode => Object.hash(totalCount, Object.hashAll(items));
}

bool _sameMutualItems(
  List<PublicProfileMutualFollower> left,
  List<PublicProfileMutualFollower> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Public profile model — shape /api/u/{username} response. Subset
/// User row yang aman tampil ke siapapun + stats publik.
class PublicProfile {
  final String id;
  final String name;
  final String? shareVersion;
  final String? username;
  final String? profilePhotoUrl;
  final String? bio;
  final DateTime? memberSince;
  final int postCount;
  final int likedCount;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final bool isOwner;
  final PublicProfileMutualSummary mutualFollowers;

  /// Akun official Natalo (admin). Profil tampil brand "Natalo Petshop"
  /// + badge centang + logo, BUKAN nama/foto pribadi pemilik.
  final bool isOfficial;

  const PublicProfile({
    required this.id,
    required this.name,
    this.shareVersion,
    this.username,
    this.profilePhotoUrl,
    this.bio,
    this.memberSince,
    this.postCount = 0,
    this.likedCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.isOwner = false,
    this.mutualFollowers = PublicProfileMutualSummary.empty,
    this.isOfficial = false,
  });

  String get initial =>
      name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase();

  /// Public handle untuk header — bare `username` kalau set, fallback
  /// nama. URL path tetap pakai username yang asli (lowercase).
  /// Match IG/TikTok pattern: identity label TIDAK pakai `@`.
  String get displayHandle => isOfficial
      ? kOfficialBrandName
      : ((username != null && username!.isNotEmpty) ? username! : name);

  factory PublicProfile.fromJson(
    Map<String, dynamic> json, {
    bool isOwner = false,
  }) {
    return PublicProfile(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      shareVersion: _nullableString(json['shareVersion']),
      username: _nullableString(json['username']),
      profilePhotoUrl: _nullableString(
        json['profilePhotoUrl'] ?? json['profile_photo_url'],
      ),
      bio: _nullableString(json['bio']),
      memberSince: DateTime.tryParse((json['memberSince'] ?? '').toString()),
      postCount: 0,
      likedCount: 0,
      followersCount: 0,
      followingCount: 0,
      isFollowing: json['isFollowing'] == true,
      isOwner: isOwner,
      mutualFollowers: PublicProfileMutualSummary.fromJson(
        json['mutualFollowers'],
      ),
      isOfficial: json['isOfficial'] == true,
    );
  }

  PublicProfile copyWith({
    String? shareVersion,
    int? postCount,
    int? likedCount,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    bool? isOwner,
    PublicProfileMutualSummary? mutualFollowers,
    bool? isOfficial,
  }) {
    return PublicProfile(
      id: id,
      name: name,
      shareVersion: shareVersion ?? this.shareVersion,
      username: username,
      profilePhotoUrl: profilePhotoUrl,
      bio: bio,
      memberSince: memberSince,
      postCount: postCount ?? this.postCount,
      likedCount: likedCount ?? this.likedCount,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isOwner: isOwner ?? this.isOwner,
      mutualFollowers: mutualFollowers ?? this.mutualFollowers,
      isOfficial: isOfficial ?? this.isOfficial,
    );
  }
}

String? _nullableString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}
