/// Tag orang yang sedang disusun di composer (Spec B). Berbeda dari
/// FeedTaggedUser (shape response server) — ini shape client-side yang
/// membawa identitas untuk render pill + koordinat untuk payload API.
class NewPostUserTag {
  final String userId;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  final int? mediaIndex; // null untuk video
  final double? x; // pecahan 0-1
  final double? y;

  const NewPostUserTag({
    required this.userId,
    required this.username,
    this.name = '',
    this.profilePhotoUrl,
    this.mediaIndex,
    this.x,
    this.y,
  });

  NewPostUserTag copyWith({int? mediaIndex, double? x, double? y}) {
    return NewPostUserTag(
      userId: userId,
      username: username,
      name: name,
      profilePhotoUrl: profilePhotoUrl,
      mediaIndex: mediaIndex ?? this.mediaIndex,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  /// Payload API — kontrak body POST create: {userId, mediaIndex, x, y}.
  Map<String, dynamic> toApiJson() => {
        'userId': userId,
        'mediaIndex': mediaIndex,
        'x': x,
        'y': y,
      };

  /// Persist penuh (draft video + pending upload) — round-trip fromJson.
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'username': username,
        'name': name,
        'profilePhotoUrl': profilePhotoUrl,
        'mediaIndex': mediaIndex,
        'x': x,
        'y': y,
      };

  factory NewPostUserTag.fromJson(Map<String, dynamic> json) {
    return NewPostUserTag(
      userId: (json['userId'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      mediaIndex: (json['mediaIndex'] as num?)?.toInt(),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
    );
  }
}
