import 'api_client.dart';

/// Follow/unfollow service — pakai endpoint Next.js (`/social/users/...`)
/// yang dihost di Vercel. Sebelumnya ada dual implementation dengan
/// NestJS microservice (`social_service/`) yang access lewat
/// `SOCIAL_API_BASE_URL` dart-define; itu sudah di-kill (commit "kill
/// NestJS social service") karena overhead maintenance dual code
/// melebihi manfaatnya untuk solo dev di pre-DAU app. Resurrect Nest
/// kalau muncul trigger nyata: Vercel bill spike dari social traffic,
/// real-time feature (chat/live notif), atau Vercel function timeout di
/// social endpoint.
class FollowState {
  final bool isFollowing;
  final int followersCount;
  final int followingCount;
  final bool changed;
  final bool isSelf;

  const FollowState({
    required this.isFollowing,
    required this.followersCount,
    required this.followingCount,
    this.changed = false,
    this.isSelf = false,
  });

  factory FollowState.fromJson(Map<String, dynamic> json) {
    return FollowState(
      isFollowing: json['isFollowing'] == true,
      followersCount: (json['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
      changed: json['changed'] == true,
      isSelf: json['isSelf'] == true,
    );
  }
}

class FollowUserSummary {
  final String id;
  final String name;
  final String? username;
  final String? profilePhotoUrl;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final bool isSelf;

  const FollowUserSummary({
    required this.id,
    required this.name,
    this.username,
    this.profilePhotoUrl,
    this.bio,
    this.followersCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.isSelf = false,
  });

  String get initial =>
      name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase();

  String get displayHandle =>
      username != null && username!.isNotEmpty ? username! : name;

  bool get canOpenProfile => username != null && username!.isNotEmpty;

  factory FollowUserSummary.fromJson(Map<String, dynamic> json) {
    return FollowUserSummary(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      username: _nullableString(json['username']),
      profilePhotoUrl: _nullableString(
        json['profilePhotoUrl'] ?? json['profile_photo_url'],
      ),
      bio: _nullableString(json['bio']),
      followersCount: (json['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
      isFollowing: json['isFollowing'] == true,
      isSelf: json['isSelf'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'profilePhotoUrl': profilePhotoUrl,
        'bio': bio,
        'followersCount': followersCount,
        'followingCount': followingCount,
        'isFollowing': isFollowing,
        'isSelf': isSelf,
      };

  FollowUserSummary copyWith({
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    bool? isSelf,
  }) {
    return FollowUserSummary(
      id: id,
      name: name,
      username: username,
      profilePhotoUrl: profilePhotoUrl,
      bio: bio,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isSelf: isSelf ?? this.isSelf,
    );
  }
}

class FollowListResult {
  final List<FollowUserSummary> items;
  final String? nextCursor;

  const FollowListResult({
    required this.items,
    required this.nextCursor,
  });

  factory FollowListResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <FollowUserSummary>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map<String, dynamic>) {
          items.add(FollowUserSummary.fromJson(raw));
        } else if (raw is Map) {
          items.add(FollowUserSummary.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return FollowListResult(
      items: items,
      nextCursor: _nullableString(json['nextCursor']),
    );
  }
}

class FollowService {
  FollowService._();

  Future<FollowState> follow(String userId) async {
    final data = await apiClient.postJson(
      '/social/users/${Uri.encodeComponent(userId)}/follow',
    );
    return FollowState.fromJson(_asMap(data));
  }

  Future<FollowState> unfollow(String userId) async {
    final data = await apiClient.deleteJson(
      '/social/users/${Uri.encodeComponent(userId)}/follow',
    );
    return FollowState.fromJson(_asMap(data));
  }

  Future<FollowState> fetchState(String userId) async {
    final data = await apiClient.getJson(
      '/social/users/${Uri.encodeComponent(userId)}/follow-state',
    );
    return FollowState.fromJson(_asMap(data));
  }

  Future<List<FollowUserSummary>> searchUsers(
    String query, {
    int limit = 20,
  }) async {
    return _fetchUserSearch(
      query: query,
      limit: limit,
      suggested: false,
    );
  }

  Future<List<FollowUserSummary>> fetchSuggestedUsers({
    int limit = 12,
  }) async {
    return _fetchUserSearch(
      query: '',
      limit: limit,
      suggested: true,
    );
  }

  Future<List<FollowUserSummary>> _fetchUserSearch({
    required String query,
    required int limit,
    required bool suggested,
  }) async {
    final data = await apiClient.getJson(
      '/api/users/search',
      query: {
        'q': query,
        'limit': limit,
        if (suggested) 'suggested': '1',
      },
      timeout: const Duration(seconds: 5),
    );
    final map = _asMap(data);
    final rawItems = map['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map<String, dynamic>>()
        .map(FollowUserSummary.fromJson)
        .where((user) => user.canOpenProfile)
        .toList(growable: false);
  }

  Future<FollowListResult> fetchFollowers(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async {
    final data = await apiClient.getJson(
      '/social/users/${Uri.encodeComponent(userId)}/followers',
      query: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return FollowListResult.fromJson(_asMap(data));
  }

  Future<FollowListResult> fetchFollowing(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async {
    final data = await apiClient.getJson(
      '/social/users/${Uri.encodeComponent(userId)}/following',
      query: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return FollowListResult.fromJson(_asMap(data));
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException('Format response follow tidak valid.');
  }
}

final followService = FollowService._();

String? _nullableString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}
