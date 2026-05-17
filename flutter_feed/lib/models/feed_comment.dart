// Mirror of prisma/schema.prisma:820-854 (FeedComment, 1-level threading)

class FeedComment {
  final String id;
  final String postId;
  final String authorId;
  final String? authorName;
  final String? authorAvatarUrl;
  final String? parentCommentId; // null = top-level, set = reply (1-level only)
  final String content;
  final bool isAdminOfficial; // badge render
  final bool isHidden;
  final int likeCount;
  final bool viewerLiked;
  final DateTime createdAt;

  // Optional inline replies (loaded on demand)
  final List<FeedComment> replies;

  const FeedComment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.authorName,
    this.authorAvatarUrl,
    this.parentCommentId,
    required this.content,
    this.isAdminOfficial = false,
    this.isHidden = false,
    this.likeCount = 0,
    this.viewerLiked = false,
    required this.createdAt,
    this.replies = const [],
  });

  bool get isReply => parentCommentId != null;

  FeedComment copyWith({
    int? likeCount,
    bool? viewerLiked,
    List<FeedComment>? replies,
  }) =>
      FeedComment(
        id: id,
        postId: postId,
        authorId: authorId,
        authorName: authorName,
        authorAvatarUrl: authorAvatarUrl,
        parentCommentId: parentCommentId,
        content: content,
        isAdminOfficial: isAdminOfficial,
        isHidden: isHidden,
        likeCount: likeCount ?? this.likeCount,
        viewerLiked: viewerLiked ?? this.viewerLiked,
        createdAt: createdAt,
        replies: replies ?? this.replies,
      );

  factory FeedComment.fromJson(Map<String, dynamic> json) => FeedComment(
        id: json['id'] as String,
        postId: json['postId'] as String,
        authorId: json['authorId'] as String,
        authorName: json['authorName'] as String?,
        authorAvatarUrl: json['authorAvatarUrl'] as String?,
        parentCommentId: json['parentCommentId'] as String?,
        content: json['content'] as String? ?? '',
        isAdminOfficial: (json['isAdminOfficial'] as bool?) ?? false,
        isHidden: (json['isHidden'] as bool?) ?? false,
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        viewerLiked: (json['viewerLiked'] as bool?) ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        replies: ((json['replies'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(FeedComment.fromJson)
            .toList(),
      );
}
