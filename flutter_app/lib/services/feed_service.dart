import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../models/my_feed_post.dart';
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

  /// Fetch feed posts cursor-paginated.
  ///
  /// Gap #9 fix: tidak lagi silent-swallow non-ApiException errors.
  /// Network timeout / DNS fail / parse error → throw ApiException
  /// supaya caller bisa show retry UI (sebelumnya return empty page
  /// yang misleading: user lihat "Belum ada postingan" padahal error).
  /// Gap #10 fix: timeout 8s → 15s (Indonesia 3G/slow 4G area).
  Future<FeedPage> fetchPublicFeed({String? cursor, int limit = 10}) async {
    try {
      final uri = ApiConfig.uri('/api/feed/posts', {
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      });
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw ApiException('feed fetch failed', statusCode: res.statusCode);
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) {
        return const FeedPage();
      }
      final itemsJson =
          (body['items'] ?? body['posts'] ?? body['data']) as List?;
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
      // Wrap network/timeout/parse errors sebagai ApiException supaya
      // caller bisa distinguish "error" vs "empty result".
      throw ApiException(e.toString(), cause: e);
    }
  }

  Future<List<MyFeedPost>> fetchMyPosts({String filter = 'all'}) async {
    final data = await apiClient.getJson(
      '/api/feed/my-posts',
      query: {'status': filter},
    );
    final raw =
        data is Map ? (data['posts'] ?? data['items'] ?? data['data']) : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MyFeedPost.fromApiJson)
        .toList();
  }

  /// Track view event — fire-and-forget. Backend increment viewCount
  /// + record analytics event. Client debounce sendiri (avoid
  /// double-count) via FeedLocalStore.hasViewedThisSession.
  ///
  /// Gap #3 fix: previously no client send view event → analytics
  /// under-report views untuk Flutter users.
  Future<void> trackView(String postId) async {
    try {
      final uri = ApiConfig.uri('/api/feed/posts/$postId/view');
      await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Silent — non-critical analytics, jangan ganggu UX.
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

  // ──────────────────────────────────────────────────────────────
  // Comments — Instagram Reels-style threading + likes + replies.
  // Backend endpoint match Next.js /api/feed/posts/:id/comments.
  // ──────────────────────────────────────────────────────────────

  /// Fetch komentar untuk post, cursor-paginated (newest-first).
  /// Backend bisa balikin flat list (parent+replies di-mix) atau nested
  /// — model FeedComment punya `parentCommentId` untuk group client-side.
  Future<FeedCommentPage> fetchComments(
    String postId, {
    String? cursor,
    int limit = 30,
  }) async {
    try {
      final uri = ApiConfig.uri('/api/feed/posts/$postId/comments', {
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      });
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw ApiException(
          'fetch comments failed',
          statusCode: res.statusCode,
        );
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return FeedCommentPage.empty;
      final itemsJson =
          (body['items'] ?? body['comments'] ?? body['data']) as List?;
      final items = (itemsJson ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FeedComment.fromApiJson)
          .toList();
      return FeedCommentPage(
        items: items,
        nextCursor: body['nextCursor'] as String?,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[feedService.fetchComments] $e');
      if (e is ApiException) rethrow;
      return FeedCommentPage.empty;
    }
  }

  /// Post komentar baru. `parentCommentId` opsional — kalau ada, ini
  /// adalah reply ke komentar parent.
  Future<FeedComment> postComment(
    String postId, {
    required String content,
    String? parentCommentId,
  }) async {
    final uri = ApiConfig.uri('/api/feed/posts/$postId/comments');
    try {
      final res = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'content': content,
              if (parentCommentId != null) 'parentCommentId': parentCommentId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) {
        throw const ApiException('unauthorized', statusCode: 401);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          'post comment failed',
          statusCode: res.statusCode,
        );
      }
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        // Backend bisa balikin nested `{comment: {...}}` atau langsung.
        final commentJson = body['comment'] is Map<String, dynamic>
            ? body['comment'] as Map<String, dynamic>
            : body;
        return FeedComment.fromApiJson(commentJson);
      }
      throw const ApiException('invalid response');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  /// Toggle like di komentar. Return likeCount terbaru dari backend.
  Future<int> toggleCommentLike(
    String commentId, {
    required bool currentlyLiked,
  }) async {
    final method = currentlyLiked ? 'DELETE' : 'POST';
    final uri = ApiConfig.uri('/api/feed/comments/$commentId/like');
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      final streamed = await req.send().timeout(const Duration(seconds: 6));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 401) {
        throw const ApiException('unauthorized', statusCode: 401);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          'toggle comment like failed',
          statusCode: res.statusCode,
        );
      }
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        return (body['likeCount'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  /// Delete komentar — backend cek ownership (cuma author yang boleh).
  Future<void> deleteComment(String commentId) async {
    final uri = ApiConfig.uri('/api/feed/comments/$commentId');
    try {
      final res = await http
          .delete(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 401) {
        throw const ApiException('unauthorized', statusCode: 401);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          'delete comment failed',
          statusCode: res.statusCode,
        );
      }
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
