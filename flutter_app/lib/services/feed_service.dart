import '../models/feed_post.dart';
import '../models/feed_comment.dart';
import '../models/my_feed_post.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

/// Service untuk fitur Feed user-generated content.
/// Match endpoint PWA `/api/feed/*`.
class FeedService {
  /// Fetch public feed posts (timeline view) — match endpoint
  /// GET /api/feed/posts?tab=...&cursor=...
  ///
  /// Tab: null (semua), 'REKOMENDASI', 'PROMO', atau 'KOMUNITAS'.
  /// Pagination via cursor (nextCursor di response).
  Future<FeedPage> fetchPublicFeed({
    String? tab,
    String? cursor,
    String? productSlug,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/feed/posts',
        query: {
          if (tab != null && tab.isNotEmpty) 'tab': tab,
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          if (productSlug != null && productSlug.isNotEmpty)
            'product': productSlug,
        },
      );
      final raw = data['items'];
      if (raw is! List) return FeedPage.empty;
      final items = raw
          .whereType<Map<String, dynamic>>()
          .map(FeedPost.fromApiJson)
          .toList();
      return FeedPage(
        items: items,
        nextCursor: data['nextCursor']?.toString(),
      );
    } catch (_) {
      return FeedPage.empty;
    }
  }

  /// Toggle like di feed post — match endpoint POST /api/feed/posts/{id}/like.
  /// Server mengembalikan liked + likeCount final supaya UI tidak drift.
  Future<({bool liked, int likeCount})> toggleLike(
    String postId, {
    required bool currentlyLiked,
  }) async {
    readOnlyMode.assertWritable('feed_like');
    final data = await apiClient.postJson(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/like',
      body: const <String, dynamic>{},
    );
    return (
      liked: data['liked'] is bool ? data['liked'] as bool : !currentlyLiked,
      likeCount: _asInt(data['likeCount']),
    );
  }

  /// Track share — match endpoint POST /api/feed/posts/{id}/share.
  /// Server increment shareCount; client tetap show optimistic update.
  Future<void> trackShare(String postId) async {
    try {
      readOnlyMode.assertWritable('feed_share');
      await apiClient.postJson(
        '/api/feed/posts/${Uri.encodeComponent(postId)}/share',
        body: const <String, dynamic>{},
      );
    } catch (_) {}
  }

  /// Fetch komentar public feed. Match:
  /// GET /api/feed/posts/{id}/comments?cursor=...
  Future<FeedCommentPage> fetchComments({
    required String postId,
    String? cursor,
  }) async {
    final data = await apiClient.getJson(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/comments',
      query: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final raw = data['items'];
    if (raw is! List) return FeedCommentPage.empty;
    return FeedCommentPage(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(FeedComment.fromApiJson)
          .toList(),
      nextCursor: data['nextCursor']?.toString(),
    );
  }

  /// Submit komentar top-level atau reply. Return komentar baru dari server.
  Future<FeedComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
  }) async {
    readOnlyMode.assertWritable('feed_comment');
    final data = await apiClient.postJson(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/comments',
      body: {
        'content': content.trim(),
        if (parentCommentId != null) 'parentCommentId': parentCommentId,
      },
    );
    final raw = data['comment'];
    if (raw is Map<String, dynamic>) {
      return FeedComment.fromApiJson(raw);
    }
    throw const ApiException('Komentar gagal dikirim.');
  }

  /// Toggle like komentar. Endpoint mengembalikan liked + likeCount final.
  Future<({bool liked, int likeCount})> toggleCommentLike({
    required String commentId,
  }) async {
    readOnlyMode.assertWritable('feed_comment_like');
    final data = await apiClient.postJson(
      '/api/feed/comments/${Uri.encodeComponent(commentId)}/like',
      body: const <String, dynamic>{},
    );
    return (
      liked: data['liked'] == true,
      likeCount: _asInt(data['likeCount']),
    );
  }

  Future<FeedUploadFileResult> uploadFeedVideo({
    required String filePath,
    required String filename,
    required String contentType,
  }) async {
    readOnlyMode.assertWritable('feed_upload_video');
    final data = await apiClient.postMultipartFile(
      '/api/feed/upload-video',
      fieldName: 'file',
      filePath: filePath,
      filename: filename,
      contentType: contentType,
      timeout: const Duration(minutes: 3),
    );
    return FeedUploadFileResult.fromApiJson(data);
  }

  Future<FeedUploadFileResult> uploadFeedThumbnail({
    required String filePath,
    required String filename,
    required String contentType,
  }) async {
    readOnlyMode.assertWritable('feed_upload_thumbnail');
    final data = await apiClient.postMultipartFile(
      '/api/feed/upload-thumbnail',
      fieldName: 'file',
      filePath: filePath,
      filename: filename,
      contentType: contentType,
      timeout: const Duration(minutes: 1),
    );
    return FeedUploadFileResult.fromApiJson(data);
  }

  Future<FeedCreatePostResult> createFeedPost({
    required String title,
    String? description,
    required String videoUrl,
    required String thumbnailUrl,
    String? videoMimeType,
    int? videoSizeBytes,
    required int videoDurationSec,
    int? videoWidth,
    int? videoHeight,
    List<String> productIds = const [],
  }) async {
    readOnlyMode.assertWritable('feed_create_post');
    final cleanProductIds = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .take(3)
        .toList();
    final data = await apiClient.postJson(
      '/api/feed/posts',
      body: {
        'title': title.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        if (videoMimeType != null) 'videoMimeType': videoMimeType,
        if (videoSizeBytes != null) 'videoSizeBytes': videoSizeBytes,
        'videoDurationSec': videoDurationSec,
        if (videoWidth != null) 'videoWidth': videoWidth,
        if (videoHeight != null) 'videoHeight': videoHeight,
        if (cleanProductIds.isNotEmpty) ...{
          'productId': cleanProductIds.first,
          'productIds': cleanProductIds,
        },
      },
    );
    return FeedCreatePostResult.fromApiJson(data);
  }

  /// Fetch list postingan user yang sedang login.
  /// [filter] valid: 'all' | 'pending' | 'active' | 'rejected'.
  /// Match `/api/feed/my-posts?status={filter}`.
  Future<List<MyFeedPost>> fetchMyPosts({String filter = 'all'}) async {
    try {
      final data = await apiClient.getJson(
        '/api/feed/my-posts',
        query: {'status': filter},
      );
      final raw = data['posts'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MyFeedPost.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Hapus postingan user. Match endpoint PWA DELETE /api/feed/posts/{id}.
  /// Server validate ownership (authorId == session.sub).
  Future<void> deletePost(String id) async {
    readOnlyMode.assertWritable('feed_delete');
    await apiClient.deleteJson('/api/feed/posts/${Uri.encodeComponent(id)}');
  }

  /// Update caption + tags postingan user. Match endpoint PWA
  /// PUT /api/feed/posts/{id} dengan body `{title, description, tags[]}`.
  /// Server validate ownership.
  ///
  /// [tags] dipassing sebagai List<String>; akan di-trim + filter empty.
  Future<void> updatePostCaption({
    required String id,
    String? title,
    String? description,
    List<String>? tags,
  }) async {
    readOnlyMode.assertWritable('feed_update');
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title.trim();
    if (description != null) body['description'] = description.trim();
    if (tags != null) {
      body['tags'] =
          tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    }
    await apiClient.putJson(
      '/api/feed/posts/${Uri.encodeComponent(id)}',
      body: body,
    );
  }

  /// Fetch list produk yang user pernah beli (untuk pin di feed post).
  /// Match endpoint PWA GET /api/feed/pinnable-products.
  ///
  /// Saat user upload video Feed, dia bisa "pin" produk yang ditampilkan
  /// di video. Hanya produk yang pernah dibeli (verified ownership) yang
  /// boleh di-pin, supaya tidak ada spam promosi orang lain.
  Future<List<Map<String, dynamic>>> fetchPinnableProducts() async {
    try {
      final data = await apiClient.getJson('/api/feed/pinnable-products');
      final raw = data['products'] ?? data['items'] ?? data['data'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
}

final feedService = FeedService();

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
