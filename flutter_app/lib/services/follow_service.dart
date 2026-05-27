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

  Future<Map<String, dynamic>> _send(String method, String path) async {
    final uri = ApiConfig.socialUri(path);
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
