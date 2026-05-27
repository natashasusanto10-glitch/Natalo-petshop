import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../state/member_store.dart';
import 'api_client.dart';

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

  const FollowUserSummary({
    required this.id,
    required this.name,
    this.username,
    this.profilePhotoUrl,
    this.bio,
    this.followersCount = 0,
    this.followingCount = 0,
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
    final data = await _send(
      'POST',
      '/social/users/${Uri.encodeComponent(userId)}/follow',
    );
    return FollowState.fromJson(data);
  }

  Future<FollowState> unfollow(String userId) async {
    final data = await _send(
      'DELETE',
      '/social/users/${Uri.encodeComponent(userId)}/follow',
    );
    return FollowState.fromJson(data);
  }

  Future<FollowState> fetchState(String userId) async {
    final data = await _send(
      'GET',
      '/social/users/${Uri.encodeComponent(userId)}/follow-state',
    );
    return FollowState.fromJson(data);
  }

  Future<FollowListResult> fetchFollowers(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _send(
      'GET',
      '/social/users/${Uri.encodeComponent(userId)}/followers',
      query: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return FollowListResult.fromJson(data);
  }

  Future<FollowListResult> fetchFollowing(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _send(
      'GET',
      '/social/users/${Uri.encodeComponent(userId)}/following',
      query: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return FollowListResult.fromJson(data);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final uri = ApiConfig.socialUri(path, query);
    final request = http.Request(method, uri)..headers.addAll(_headers());
    try {
      final streamed = await request.send().timeout(
            const Duration(seconds: 12),
          );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _messageFor(response),
          statusCode: response.statusCode,
        );
      }
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const ApiException('Format response follow tidak valid.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  Map<String, String> _headers() {
    final token = memberStore.sessionToken;
    return {
      'accept': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      if (token != null) 'cookie': 'member_session=$token',
    };
  }

  String _messageFor(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['error'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}
    if (response.statusCode == 401) return 'Login dulu untuk follow user.';
    if (response.statusCode == 404) return 'User tidak ditemukan.';
    return 'Gagal memproses follow. Coba lagi.';
  }
}

final followService = FollowService._();

String? _nullableString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}
