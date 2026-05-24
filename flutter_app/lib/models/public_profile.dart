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
  final bool isOwner;

  const PublicProfile({
    required this.id,
    required this.name,
    this.username,
    this.profilePhotoUrl,
    this.bio,
    this.memberSince,
    this.postCount = 0,
    this.likedCount = 0,
    this.isOwner = false,
  });

  String get initial =>
      name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase();

  /// Public handle untuk header — `@username` kalau set, fallback
  /// nama. URL path tetap pakai username yang asli (lowercase).
  String get displayHandle =>
      (username != null && username!.isNotEmpty) ? '@$username' : name;

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
      memberSince:
          DateTime.tryParse((json['memberSince'] ?? '').toString()),
      postCount: 0,
      likedCount: 0,
      isOwner: isOwner,
    );
  }

  PublicProfile copyWith({int? postCount, int? likedCount, bool? isOwner}) {
    return PublicProfile(
      id: id,
      name: name,
      username: username,
      profilePhotoUrl: profilePhotoUrl,
      bio: bio,
      memberSince: memberSince,
      postCount: postCount ?? this.postCount,
      likedCount: likedCount ?? this.likedCount,
      isOwner: isOwner ?? this.isOwner,
    );
  }
}

String? _nullableString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}
