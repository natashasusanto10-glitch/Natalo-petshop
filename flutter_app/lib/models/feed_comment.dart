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

class FeedCommentCreateResult {
  final FeedComment comment;
  final int? commentCount;

  const FeedCommentCreateResult({
    required this.comment,
    this.commentCount,
  });
}

class FeedCommentDeleteResult {
  final int? commentCount;

  const FeedCommentDeleteResult({this.commentCount});
}

class FeedCommentThreadItem {
  final FeedComment comment;
  final bool isReply;

  const FeedCommentThreadItem({
    required this.comment,
    required this.isReply,
  });
}

class FeedCommentThread {
  final FeedComment parent;
  final List<FeedComment> replies;

  const FeedCommentThread({required this.parent, required this.replies});
}

/// Gabungkan response nested terbaru dan response flat lama menjadi thread
/// satu tingkat. Reply ke reply tetap berada di bawah parent root.
List<FeedCommentThread> groupFeedCommentThreads(List<FeedComment> comments) {
  final flatReplies = <String, List<FeedComment>>{};
  for (final comment in comments) {
    final parentId = comment.parentCommentId;
    if (parentId != null) {
      flatReplies.putIfAbsent(parentId, () => []).add(comment);
    }
  }

  return comments
      .where((comment) => comment.parentCommentId == null)
      .map((parent) {
    final repliesById = <String, FeedComment>{
      for (final reply in parent.replies) reply.id: reply,
      for (final reply in flatReplies[parent.id] ?? const <FeedComment>[])
        reply.id: reply,
    };
    final replies = repliesById.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return FeedCommentThread(parent: parent, replies: replies);
  }).toList(growable: false);
}

/// Ambil batch balasan terbaru tanpa mengubah urutan kronologis di layar.
List<FeedComment> latestVisibleFeedReplies(
  List<FeedComment> replies,
  int visibleCount,
) {
  final count = visibleCount.clamp(0, replies.length);
  if (count == 0) return const [];
  return replies.sublist(replies.length - count);
}

/// Normalisasi response lama (reply flat) dan response baru (reply nested)
/// menjadi urutan render parent lalu reply, tanpa duplikat.
List<FeedCommentThreadItem> flattenFeedCommentThreads(
  List<FeedComment> comments,
) {
  final result = <FeedCommentThreadItem>[];
  for (final thread in groupFeedCommentThreads(comments)) {
    result.add(FeedCommentThreadItem(comment: thread.parent, isReply: false));
    for (final reply in thread.replies) {
      result.add(FeedCommentThreadItem(comment: reply, isReply: true));
    }
  }
  return result;
}

class FeedCommentRemovalResult {
  final List<FeedComment> comments;
  final Set<String> removedIds;

  const FeedCommentRemovalResult({
    required this.comments,
    required this.removedIds,
  });
}

/// Remove one comment from a nested comment page while preserving the server
/// reply total. A parent deletion also removes every loaded child ID so UI
/// state such as an active reply target can be invalidated safely.
FeedCommentRemovalResult removeFeedCommentFromThreads(
  List<FeedComment> comments,
  FeedComment removed,
) {
  final removesThread = removed.parentCommentId == null;
  final removedIds = <String>{
    removed.id,
    if (removesThread) ...removed.replies.map((reply) => reply.id),
    if (removesThread)
      ...comments
          .where((comment) => comment.parentCommentId == removed.id)
          .map((comment) => comment.id),
  };
  final updated = comments
      .where((comment) => !removedIds.contains(comment.id))
      .map((comment) {
    final containsNestedReply =
        comment.replies.any((reply) => reply.id == removed.id);
    final isLegacyFlatParent = removed.parentCommentId == comment.id;
    if (!containsNestedReply && !isLegacyFlatParent) {
      return comment;
    }
    final replies = comment.replies
        .where((reply) => reply.id != removed.id)
        .toList(growable: false);
    final remainingTotal =
        comment.replyCount > 0 ? comment.replyCount - 1 : replies.length;
    return comment.copyWith(
      replies: replies,
      replyCount:
          remainingTotal < replies.length ? replies.length : remainingTotal,
    );
  }).toList(growable: false);
  return FeedCommentRemovalResult(
    comments: updated,
    removedIds: removedIds,
  );
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

  /// Username (lowercase) yang di-mention di `content` dan merupakan akun
  /// admin/official. Dipakai untuk brand-override render: "@username" →
  /// "@Natalo Petshop" + badge. Dari backend (officialMentions). Empty
  /// kalau tidak ada mention official.
  final List<String> officialMentions;

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
    this.officialMentions = const [],
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
      officialMentions: (json['officialMentions'] as List?)
              ?.whereType<String>()
              .map((h) => h.toLowerCase())
              .toList() ??
          const [],
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
      officialMentions: officialMentions,
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
