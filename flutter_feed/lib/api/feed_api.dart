import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

import '../models/feed_post.dart';
import '../models/feed_comment.dart';

// Mirror of app/api/feed/** + app/api/admin/feed/**
//
// Auth: JWT httpOnly cookie via cookie_jar (Set-Cookie persisted between
// requests). Server-side endpoints assume same session shape as web.
//
// TODO: replace API_BASE_URL with env-driven config (--dart-define) before
// release build. 10.0.2.2 is Android emulator → host machine.

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

class FeedApi {
  final Dio _dio;

  FeedApi._(this._dio);

  factory FeedApi.create({String baseUrl = kApiBaseUrl}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
    ));
    dio.interceptors.add(CookieManager(CookieJar()));
    return FeedApi._(dio);
  }

  Dio get rawDio => _dio;

  /// GET /api/feed/posts?cursor=...&tab=...
  Future<FeedListPage> listPosts({String? cursor, FeedPostTab? tab}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/feed/posts',
      queryParameters: {
        if (cursor != null) 'cursor': cursor,
        if (tab != null) 'tab': _tabKey(tab),
      },
    );
    final data = res.data!;
    return FeedListPage(
      posts: (data['posts'] as List)
          .cast<Map<String, dynamic>>()
          .map(FeedPost.fromJson)
          .toList(),
      nextCursor: data['nextCursor'] as String?,
    );
  }

  /// POST /api/feed/posts/[id]/like — toggle
  Future<({bool liked, int likeCount})> toggleLike(String postId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/feed/posts/$postId/like',
    );
    return (
      liked: (res.data?['liked'] as bool?) ?? false,
      likeCount: (res.data?['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// POST /api/feed/posts/[id]/share — increment counter after native share
  Future<int> registerShare(String postId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/feed/posts/$postId/share',
    );
    return (res.data?['shareCount'] as num?)?.toInt() ?? 0;
  }

  /// GET /api/feed/posts/[id]/comments
  Future<List<FeedComment>> listComments(String postId,
      {String? cursor}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/feed/posts/$postId/comments',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return ((res.data?['comments'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(FeedComment.fromJson)
        .toList();
  }

  /// POST /api/feed/posts/[id]/comments
  Future<FeedComment> postComment(String postId, String content,
      {String? parentCommentId}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/feed/posts/$postId/comments',
      data: {
        'content': content,
        if (parentCommentId != null) 'parentCommentId': parentCommentId,
      },
    );
    return FeedComment.fromJson(res.data!['comment'] as Map<String, dynamic>);
  }

  /// POST /api/feed/comments/[id]/like — toggle
  Future<({bool liked, int likeCount})> toggleCommentLike(
      String commentId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/feed/comments/$commentId/like',
    );
    return (
      liked: (res.data?['liked'] as bool?) ?? false,
      likeCount: (res.data?['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// POST /api/feed/metrics — playback telemetry
  Future<void> postMetric(Map<String, dynamic> payload) async {
    await _dio.post('/api/feed/metrics', data: payload);
  }
}

class FeedListPage {
  final List<FeedPost> posts;
  final String? nextCursor;
  const FeedListPage({required this.posts, required this.nextCursor});
  bool get hasMore => nextCursor != null;
}

String _tabKey(FeedPostTab tab) {
  switch (tab) {
    case FeedPostTab.promo:
      return 'PROMO';
    case FeedPostTab.komunitas:
      return 'KOMUNITAS';
    case FeedPostTab.rekomendasi:
      return 'REKOMENDASI';
  }
}
