import 'api_client.dart';
import '../state/follow_override_store.dart';

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

/// The viewer changed while a follow mutation was in flight.
///
/// Callers must ignore this completion: its response belongs to a previous
/// authenticated session and must never reconcile UI or global overrides for
/// the current viewer.
class FollowSessionChangedException implements Exception {
  const FollowSessionChangedException();

  @override
  String toString() => 'Follow session changed while request was in flight';
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

  /// Akun official (admin) → klien render logo brand sebagai avatar
  /// (server null-kan foto asli + kirim name "Natalo Petshop").
  final bool isOfficial;

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
    this.isOfficial = false,
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
      isOfficial: json['isOfficial'] == true,
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
        'isOfficial': isOfficial,
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
      isOfficial: isOfficial,
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
          final user = FollowUserSummary.fromJson(raw);
          items.add(user.copyWith(
            isFollowing: resolveFollowState(user.id, user.isFollowing),
          ));
        } else if (raw is Map) {
          final user = FollowUserSummary.fromJson(
            Map<String, dynamic>.from(raw),
          );
          items.add(user.copyWith(
            isFollowing: resolveFollowState(user.id, user.isFollowing),
          ));
        }
      }
    }
    return FollowListResult(
      items: items,
      nextCursor: _nullableString(json['nextCursor']),
    );
  }
}

typedef FollowMutationRequest = Future<dynamic> Function(
  String userId,
  bool following,
);
typedef FollowStateRequest = Future<dynamic> Function(String userId);

class FollowService {
  FollowService._({
    FollowMutationRequest? mutationRequest,
    FollowStateRequest? stateRequest,
  })  : _mutationRequest = mutationRequest,
        _stateRequest = stateRequest;

  FollowService.forTesting({
    required FollowMutationRequest mutationRequest,
    FollowStateRequest? stateRequest,
  }) : this._(
          mutationRequest: mutationRequest,
          stateRequest: stateRequest,
        );

  final FollowMutationRequest? _mutationRequest;
  final FollowStateRequest? _stateRequest;
  final Map<String, bool> _desiredFollowing = <String, bool>{};
  final Map<String, FollowState> _confirmedStates = <String, FollowState>{};
  final Map<String, Future<FollowState>> _inFlight =
      <String, Future<FollowState>>{};
  int _sessionEpoch = 0;

  Future<FollowState> follow(String userId) =>
      _setFollowing(userId, following: true);

  Future<FollowState> unfollow(String userId) =>
      _setFollowing(userId, following: false);

  Future<FollowState> _setFollowing(
    String userId, {
    required bool following,
  }) {
    _desiredFollowing[userId] = following;
    beginFollowMutation(userId, following);
    final active = _inFlight[userId];
    if (active != null) return active;
    final future = _drainFollowIntent(
      userId,
      firstTarget: following,
      sessionEpoch: _sessionEpoch,
    );
    _inFlight[userId] = future;
    return future;
  }

  Future<FollowState> _drainFollowIntent(
    String userId, {
    required bool firstTarget,
    required int sessionEpoch,
  }) async {
    // Yield once so _setFollowing can publish this Future in _inFlight before
    // a no-op desired state reaches the synchronous return path.
    await Future<void>.value();
    if (sessionEpoch != _sessionEpoch) {
      throw const FollowSessionChangedException();
    }
    var confirmed = _confirmedStates[userId] ??
        FollowState(
          isFollowing: !firstTarget,
          followersCount: 0,
          followingCount: 0,
        );
    try {
      while (true) {
        if (sessionEpoch != _sessionEpoch) {
          throw const FollowSessionChangedException();
        }
        final target = _desiredFollowing[userId] ?? confirmed.isFollowing;
        if (target != confirmed.isFollowing ||
            !_confirmedStates.containsKey(userId)) {
          final requestedTarget = target;
          final request = _mutationRequest;
          final data = request != null
              ? await request(userId, target)
              : target
                  ? await apiClient.postJson(
                      '/social/users/${Uri.encodeComponent(userId)}/follow',
                    )
                  : await apiClient.deleteJson(
                      '/social/users/${Uri.encodeComponent(userId)}/follow',
                    );
          confirmed = FollowState.fromJson(_asMap(data));
          if (sessionEpoch != _sessionEpoch) {
            throw const FollowSessionChangedException();
          }
          _confirmedStates[userId] = confirmed;

          // No newer tap arrived while this request was in flight. The
          // server response is canonical even when it rejects the requested
          // state (for example a policy or self-follow guard), so stop here
          // instead of retrying the same request forever.
          if ((_desiredFollowing[userId] ?? requestedTarget) ==
              requestedTarget) {
            confirmFollowMutation(userId, confirmed.isFollowing);
            return confirmed;
          }
        }
        if ((_desiredFollowing[userId] ?? confirmed.isFollowing) ==
            confirmed.isFollowing) {
          confirmFollowMutation(userId, confirmed.isFollowing);
          return confirmed;
        }
      }
    } catch (_) {
      if (sessionEpoch != _sessionEpoch) rethrow;
      abandonFollowMutation(userId);
      // Every caller observes one shared rollback target. A later explicit
      // revalidation can still correct an uncertain timeout across devices.
      setFollowOverride(userId, confirmed.isFollowing);
      rethrow;
    } finally {
      if (sessionEpoch == _sessionEpoch) {
        _desiredFollowing.remove(userId);
        _inFlight.remove(userId);
      }
    }
  }

  void clearSessionState() {
    _sessionEpoch++;
    _desiredFollowing.clear();
    _confirmedStates.clear();
    _inFlight.clear();
  }

  Future<FollowState> fetchState(String userId) async {
    final sessionEpoch = _sessionEpoch;
    final observedRevision = followStateRevision(userId);
    final request = _stateRequest;
    final data = request != null
        ? await request(userId)
        : await apiClient.getJson(
            '/social/users/${Uri.encodeComponent(userId)}/follow-state',
          );
    final state = FollowState.fromJson(_asMap(data));
    if (sessionEpoch != _sessionEpoch) {
      throw const FollowSessionChangedException();
    }
    final applied = reconcileFollowStateFromServer(
      userId,
      state.isFollowing,
      observedRevision: observedRevision,
    );
    if (applied) {
      // Keep the request queue's baseline aligned with a fresh cross-device
      // snapshot. Otherwise the next tap can be mistaken for a no-op and the
      // desired mutation never reaches the server.
      _confirmedStates[userId] = state;
    }
    return state;
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
        .map((user) => user.copyWith(
              isFollowing: resolveFollowState(user.id, user.isFollowing),
            ))
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
