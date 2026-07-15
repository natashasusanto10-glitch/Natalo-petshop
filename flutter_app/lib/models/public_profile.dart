import '../constants/official_brand.dart';

/// Public profile model — shape /api/u/{username} response. Subset
/// User row yang aman tampil ke siapapun + stats publik.
class PublicProfile {
  final String id;
  final String name;
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

  /// Akun official Natalo (admin). Profil tampil brand "Natalo Petshop"
  /// + badge centang + logo, BUKAN nama/foto pribadi pemilik.
  final bool isOfficial;

  const PublicProfile({
    required this.id,
    required this.name,
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
      isOfficial: json['isOfficial'] == true,
    );
  }

  PublicProfile copyWith({
    int? postCount,
    int? likedCount,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    bool? isOwner,
    bool? isOfficial,
  }) {
    return PublicProfile(
      id: id,
      name: name,
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
      isOfficial: isOfficial ?? this.isOfficial,
    );
  }
}

String? _nullableString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}
