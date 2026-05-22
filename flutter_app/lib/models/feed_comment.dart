import 'feed_post.dart';

class FeedCommentPage {
  final List<FeedComment> items;
  final String? nextCursor;

  const FeedCommentPage({
    required this.items,
    this.nextCursor,
  });

  static const empty = FeedCommentPage(items: [], nextCursor: null);
}

class FeedComment {
  final String id;
  final String postId;
  final String? parentCommentId;
  final String content;
  final bool isAdminOfficial;
  final bool isHidden;
  final int likeCount;
  final DateTime createdAt;
  final FeedAuthor author;
  final bool viewerLiked;
  /// Nested replies (1-level deep). Backend `/api/feed/posts/[id]/comments`
  /// return top-level comments only (parentCommentId IS NULL) dengan
  /// `replies` array inline untuk reply 1 level di bawah. Reply ke reply
  /// (>=2 level) di-flatten ke parent yang sama backend-side — Instagram
  /// behavior. Untuk top-level comment, `replies` bisa kosong.
  final List<FeedComment> replies;
  final int replyCount;

  const FeedComment({
    required this.id,
    required this.postId,
    this.parentCommentId,
    required this.content,
    required this.isAdminOfficial,
    required this.isHidden,
    required this.likeCount,
    required this.createdAt,
    required this.author,
    required this.viewerLiked,
    this.replies = const [],
    this.replyCount = 0,
  });

  factory FeedComment.fromApiJson(Map<String, dynamic> json) {
    final authorJson = json['author'];
    final repliesJson = json['replies'];
    final replies = repliesJson is List
        ? repliesJson
            .whereType<Map<String, dynamic>>()
            .map(FeedComment.fromApiJson)
            .toList()
        : const <FeedComment>[];
    return FeedComment(
      id: (json['id'] ?? '').toString(),
      postId: (json['postId'] ?? '').toString(),
      parentCommentId: _nullableString(json['parentCommentId']),
      content: (json['content'] ?? '').toString(),
      isAdminOfficial: json['isAdminOfficial'] == true,
      isHidden: json['isHidden'] == true,
      likeCount: _asInt(json['likeCount']),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      author: authorJson is Map<String, dynamic>
          ? FeedAuthor.fromJson(authorJson)
          : const FeedAuthor(
              id: '',
              name: 'Pengguna Natalo',
              role: 'CUSTOMER',
            ),
      viewerLiked: json['viewerLiked'] == true,
      replies: replies,
      replyCount: _asInt(json['replyCount']) > 0
          ? _asInt(json['replyCount'])
          : replies.length,
    );
  }

  FeedComment copyWith({
    int? likeCount,
    bool? viewerLiked,
    List<FeedComment>? replies,
    int? replyCount,
  }) {
    return FeedComment(
      id: id,
      postId: postId,
      parentCommentId: parentCommentId,
      content: content,
      isAdminOfficial: isAdminOfficial,
      isHidden: isHidden,
      likeCount: likeCount ?? this.likeCount,
      createdAt: createdAt,
      author: author,
      viewerLiked: viewerLiked ?? this.viewerLiked,
      replies: replies ?? this.replies,
      replyCount: replyCount ?? this.replyCount,
    );
  }
}

class FeedUploadFileResult {
  final String url;
  final String? key;
  final int sizeBytes;
  final String? mimeType;

  const FeedUploadFileResult({
    required this.url,
    this.key,
    required this.sizeBytes,
    this.mimeType,
  });

  factory FeedUploadFileResult.fromApiJson(Map<String, dynamic> json) {
    return FeedUploadFileResult(
      url: (json['url'] ?? '').toString(),
      key: _nullableString(json['key']),
      sizeBytes: _asInt(json['sizeBytes']),
      mimeType: _nullableString(json['mimeType']),
    );
  }
}

class FeedCreatePostResult {
  final String postId;

  const FeedCreatePostResult({required this.postId});

  factory FeedCreatePostResult.fromApiJson(Map<String, dynamic> json) {
    final post = json['post'];
    return FeedCreatePostResult(
      postId: post is Map<String, dynamic>
          ? (post['id'] ?? '').toString()
          : (json['id'] ?? '').toString(),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _nullableString(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) return null;
  return text;
}
