import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../state/member_store.dart';
import 'api_client.dart';

/// Hasil toggle like — backend balikin status final.
class FeedLikeResult {
  final bool liked;
  final int likeCount;
  final List<FeedAuthor> recentLikers;
  const FeedLikeResult({
    required this.liked,
    required this.likeCount,
    this.recentLikers = const [],
  });
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

  /// Fetch 1 postingan by ID (viewer) — dipakai saat tap deep-link notif
  /// "X posting video/foto baru" (`/feed/<id>`). Return null kalau 404
  /// (postingan dihapus / belum tayang) supaya caller bisa fallback
  /// (mis. buka feed) tanpa crash.
  Future<FeedPost?> fetchPostById(String id) async {
    try {
      final uri = ApiConfig.uri('/api/feed/posts/${Uri.encodeComponent(id)}');
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        throw ApiException('post fetch failed', statusCode: res.statusCode);
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;
      return FeedPost.fromJson(body);
    } catch (e) {
      if (kDebugMode) debugPrint('[feedService.fetchPostById] $e');
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  /// Fetch user's own posts. Cursor-paginated:
  /// - Page pertama: omit `cursor`, default 20 items (max 50)
  /// - Page selanjutnya: pass `cursor` dari `nextCursor` page sebelumnya
  ///
  /// Return [FeedPage] dengan `nextCursor` null kalau end-of-list.
  /// FeedPost.fromJson handles shape /api/feed/my-posts (status, type,
  /// mediaItems, productIds) sama seperti shape reels feed.
  Future<FeedPage> fetchMyPosts({
    String filter = 'all',
    String? cursor,
    int limit = 20,
  }) async {
    final data = await apiClient.getJson(
      '/api/feed/my-posts',
      query: {
        'status': filter,
        if (cursor != null) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final raw =
        data is Map ? (data['posts'] ?? data['items'] ?? data['data']) : data;
    final items = raw is List
        ? raw.whereType<Map<String, dynamic>>().map(FeedPost.fromJson).toList()
        : const <FeedPost>[];
    final nextCursor = data is Map ? data['nextCursor'] as String? : null;
    return FeedPage(items: items, nextCursor: nextCursor);
  }

  /// Fetch the authenticated viewer's saved posts, newest save first.
  Future<FeedPage> fetchSavedPosts({
    String? cursor,
    int limit = 20,
  }) async {
    final data = await apiClient.getJson(
      '/api/feed/saved',
      query: {
        if (cursor != null) 'cursor': cursor,
        'limit': '$limit',
      },
      timeout: const Duration(seconds: 15),
    );
    final raw =
        data is Map ? (data['items'] ?? data['posts'] ?? data['data']) : data;
    final items = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(FeedPost.fromJson)
            // The collection itself is authoritative even if an older API
            // payload omits the per-viewer field.
            .map((post) => post.copyWith(viewerSaved: true))
            .toList()
        : const <FeedPost>[];
    final nextCursor = data is Map ? data['nextCursor'] as String? : null;
    return FeedPage(items: items, nextCursor: nextCursor);
  }

  /// Set the saved state explicitly. PUT/DELETE are idempotent, allowing the
  /// store to converge to the latest tap even while a request is in flight.
  Future<bool> setSaved(String postId, {required bool saved}) async {
    final path = '/api/feed/posts/${Uri.encodeComponent(postId)}/save';
    final data = saved
        ? await apiClient.putJson(path)
        : await apiClient.deleteJson(path);
    if (data is Map<String, dynamic>) {
      return data['saved'] as bool? ?? saved;
    }
    return saved;
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
    final uri = ApiConfig.uri('/api/feed/posts/$postId/like');
    try {
      // Backend endpoint POST ini bersifat toggle: kalau user sudah like,
      // request POST akan unlike. Jangan kirim DELETE karena route Next.js
      // tidak expose DELETE dan akan memicu "toggle like failed".
      final req = http.Request('POST', uri)..headers.addAll(_headers);
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
          recentLikers: (body['recentLikers'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(FeedAuthor.fromJson)
              .where((liker) => liker.id.isNotEmpty)
              .toList(),
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
      throw ApiException('fetch comments failed', cause: e);
    }
  }

  /// Post komentar baru. `parentCommentId` opsional — kalau ada, ini
  /// adalah reply ke komentar parent.
  Future<FeedCommentCreateResult> postComment(
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
        return FeedCommentCreateResult(
          comment: FeedComment.fromApiJson(commentJson),
          commentCount: (body['commentCount'] as num?)?.toInt(),
        );
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
    final uri = ApiConfig.uri('/api/feed/comments/$commentId/like');
    try {
      // Sama seperti post like: backend comment like memakai POST toggle.
      final req = http.Request('POST', uri)..headers.addAll(_headers);
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
  Future<FeedCommentDeleteResult> deleteComment(String commentId) async {
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
      final body = jsonDecode(res.body);
      return FeedCommentDeleteResult(
        commentCount: body is Map<String, dynamic>
            ? (body['commentCount'] as num?)?.toInt()
            : null,
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  /// Catat share yang benar-benar dipilih dari native share sheet.
  ///
  /// Backend mengembalikan count final agar seluruh layar dapat reconcile
  /// ke satu angka yang sama. `null` berarti tracking gagal; share native
  /// tetap sudah terjadi sehingga caller boleh mempertahankan update lokal.
  Future<int?> trackShare(String postId) async {
    try {
      final uri = ApiConfig.uri('/api/feed/posts/$postId/share');
      final response = await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      return (body['shareCount'] as num?)?.toInt();
    } catch (_) {
      // Silent — non-critical.
      return null;
    }
  }

  /// Soft-delete post milik user sendiri (COMMUNITY video atau PHOTO_CAROUSEL).
  ///
  /// Backend route: DELETE /api/feed/posts/{id}
  ///   - Verify session user = post author
  ///   - Set deletedAt timestamp
  ///   - Fire-and-forget cleanup Bunny + UploadThing assets
  ///
  /// Return true kalau sukses. Throw ApiException dengan statusCode untuk
  /// caller mapping error message (401 → relogin, 404 → not your post, 5xx
  /// → server error).
  Future<bool> deleteMyPost(String postId) async {
    final uri = ApiConfig.uri('/api/feed/posts/$postId');
    try {
      final res = await http
          .delete(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return true;
      if (res.statusCode == 401) {
        throw const ApiException('unauthorized', statusCode: 401);
      }
      if (res.statusCode == 404) {
        throw const ApiException('Post tidak ditemukan', statusCode: 404);
      }
      throw ApiException('delete failed', statusCode: res.statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[feedService.deleteMyPost] $e');
      throw ApiException(e.toString(), cause: e);
    }
  }

  /// Update metadata post milik user sendiri.
  ///
  /// Backend akan mengembalikan post customer ACTIVE ke PENDING_REVIEW
  /// setelah edit, supaya caption/tag baru dimoderasi ulang.
  Future<bool> updateMyPost(
    String postId, {
    required String title,
    String? description,
    List<String>? productIds,
  }) async {
    final data = await apiClient.patchJson(
      '/api/feed/posts/$postId',
      body: {
        'title': title,
        'description': description,
        if (productIds != null) 'productIds': productIds,
      },
      timeout: const Duration(seconds: 15),
    );
    if (data is Map<String, dynamic>) {
      return data['ok'] == true;
    }
    return true;
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
