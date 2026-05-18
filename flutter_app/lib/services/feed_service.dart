import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/feed_post.dart';
import '../state/member_store.dart';
import 'api_client.dart';

/// Hasil toggle like — backend balikin status final.
class FeedLikeResult {
  final bool liked;
  final int likeCount;
  const FeedLikeResult({required this.liked, required this.likeCount});
}

/// Feed API: list, like, comment, share, upload. Stub minimal — endpoint REST
/// di Next.js (`/api/feed/posts/**`).
class FeedService {
  FeedService._();

  Map<String, String> get _headers {
    final token = memberStore.sessionToken;
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      if (token != null) 'cookie': 'member_session=$token',
    };
  }

  Future<FeedPage> fetchPublicFeed({String? cursor, int limit = 10}) async {
    try {
      final uri = ApiConfig.uri('/api/feed/posts', {
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      });
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw ApiException('feed fetch failed', statusCode: res.statusCode);
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) {
        return const FeedPage();
      }
      final itemsJson = (body['items'] ?? body['posts'] ?? body['data']) as List?;
      final items = (itemsJson ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FeedPost.fromJson)
          .toList();
      return FeedPage(
        items: items,
        nextCursor: body['nextCursor'] as String?,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[feedService.fetchPublicFeed] $e');
      if (e is ApiException) rethrow;
      return const FeedPage();
    }
  }

  Future<FeedLikeResult> toggleLike(
    String postId, {
    required bool currentlyLiked,
  }) async {
    final method = currentlyLiked ? 'DELETE' : 'POST';
    final uri = ApiConfig.uri('/api/feed/posts/$postId/like');
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      final streamed = await req.send().timeout(const Duration(seconds: 6));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 401) {
        throw const ApiException('unauthorized', statusCode: 401);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException('toggle like failed', statusCode: res.statusCode);
      }
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        return FeedLikeResult(
          liked: body['liked'] as bool? ?? !currentlyLiked,
          likeCount: (body['likeCount'] as num?)?.toInt() ?? 0,
        );
      }
      return FeedLikeResult(liked: !currentlyLiked, likeCount: 0);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  Future<void> trackShare(String postId) async {
    try {
      final uri = ApiConfig.uri('/api/feed/posts/$postId/share');
      await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Silent — non-critical.
    }
  }

  /// List produk yang boleh di-pin / tag di feed post (admin moderation).
  Future<List<dynamic>> fetchPinnableProducts({int limit = 30}) async {
    try {
      final data = await apiClient.getJson(
        '/api/feed/pinnable-products',
        query: {'limit': limit},
      );
      final list = data is List
          ? data
          : data is Map
              ? data['products'] ?? data['data']
              : null;
      if (list is! List) return const [];
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('[feedService.fetchPinnableProducts] $e');
      return const [];
    }
  }

  /// Upload thumbnail image untuk feed post. Boleh dipanggil dengan `file`
  /// (bytes/blob) atau dengan `filePath` + `filename` + `contentType`.
  /// Saat ini stub return wrapper dengan null URL.
  Future<FeedUploadResult> uploadFeedThumbnail({
    Object? file,
    String? filePath,
    String? filename,
    String? contentType,
  }) async {
    if (filePath == null || filePath.isEmpty) {
      return const FeedUploadResult(url: '');
    }
    try {
      final data = await apiClient.postMultipartFile(
        '/api/feed/upload-thumbnail',
        fieldName: 'file',
        filePath: filePath,
        filename: filename ?? 'thumbnail.jpg',
        contentType: contentType ?? 'image/jpeg',
      );
      if (data is Map<String, dynamic>) {
        return FeedUploadResult(url: (data['url'] ?? '').toString());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[feedService.uploadFeedThumbnail] $e');
      if (e is ApiException) rethrow;
    }
    return const FeedUploadResult(url: '');
  }
}

/// Hasil upload — kalau sukses, `url` berisi resource URL hasil upload.
/// `''` kalau upload gagal / belum kembali.
class FeedUploadResult {
  final String url;
  const FeedUploadResult({this.url = ''});
}

final FeedService feedService = FeedService._();
