import 'feed_post.dart';

class FeedCommentPage {
  final List<FeedComment> items;
  final String? nextCursor;
  final int? commentCount;
  final DateTime? syncCursor;
  final DateTime? syncTime;
  final Set<String> removedCommentIds;
  final bool syncResetRequired;

  const FeedCommentPage({
    required this.items,
    this.nextCursor,
    this.commentCount,
    this.syncCursor,
    this.syncTime,
    this.removedCommentIds = const {},
    this.syncResetRequired = false,
  });

  static const empty = FeedCommentPage(items: [], nextCursor: null);

  Set<String> get removedIds => removedCommentIds;

  factory FeedCommentPage.fromApiJson(Map<String, dynamic> json) {
    final itemsJson =
        (json['items'] ?? json['comments'] ?? json['data']) as List?;
    final changedItemsJson = json['changedItems'] as List?;
    final syncJson = json['sync'] is Map<String, dynamic>
        ? json['sync'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rawRemovedIds = json['removedCommentIds'] ??
        json['removedIds'] ??
        syncJson['removedCommentIds'] ??
        syncJson['removedIds'];

    final itemsById = <String, FeedComment>{};
    for (final raw in <dynamic>[
      ...?itemsJson,
      ...?changedItemsJson,
    ].whereType<Map<String, dynamic>>()) {
      final comment = FeedComment.fromApiJson(raw);
      // Assignment keeps the first insertion position while allowing the
      // explicit delta payload to replace an older duplicate value.
      itemsById[comment.id] = comment;
    }

    return FeedCommentPage(
      items: List<FeedComment>.unmodifiable(itemsById.values),
      nextCursor: _nullableString(json['nextCursor']),
      commentCount: _nullableInt(json['commentCount']),
      syncCursor: _nullableDateTime(
        json['syncCursor'] ?? syncJson['cursor'],
      ),
      syncTime: _nullableDateTime(
        json['syncTime'] ?? syncJson['time'] ?? json['serverTime'],
      ),
      removedCommentIds: Set<String>.unmodifiable(
        rawRemovedIds is List
            ? rawRemovedIds
                .map((id) => id.toString().trim())
                .where((id) => id.isNotEmpty)
            : const <String>[],
      ),
      syncResetRequired: json['syncResetRequired'] == true ||
          syncJson['resetRequired'] == true,
    );
  }
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

/// Merge a refreshed first page into comments already loaded by the drawer.
///
/// The API is authoritative for every ID it returns, while older paginated
/// rows stay visible until an explicit tombstone removes them. A sync reset
/// intentionally drops the cached tail because the server can no longer
/// provide a complete tombstone history for that cursor.
List<FeedComment> mergeFeedCommentRefresh({
  required List<FeedComment> current,
  required List<FeedComment> incoming,
  Iterable<String> removedIds = const <String>[],
  Iterable<String> preserveLocalLikeIds = const <String>[],
  bool reset = false,
}) {
  final removed = removedIds.toSet();
  final preserveLikes = preserveLocalLikeIds.toSet();
  final currentById = <String, FeedComment>{};

  void index(FeedComment comment) {
    currentById[comment.id] = comment;
    for (final reply in comment.replies) {
      index(reply);
    }
  }

  for (final comment in current) {
    index(comment);
  }

  FeedComment? pruneCachedNode(FeedComment comment) {
    if (removed.contains(comment.id) ||
        (comment.parentCommentId != null &&
            removed.contains(comment.parentCommentId))) {
      return null;
    }
    final replies = comment.replies
        .map(pruneCachedNode)
        .whereType<FeedComment>()
        .toList(growable: false);
    final removedReplyCount = comment.replies.length - replies.length;
    final nextReplyCount = comment.replyCount > removedReplyCount
        ? comment.replyCount - removedReplyCount
        : replies.length;
    return comment.copyWith(
      replies: replies,
      replyCount:
          nextReplyCount < replies.length ? replies.length : nextReplyCount,
    );
  }

  FeedComment mergeNode(FeedComment remote) {
    final local = currentById[remote.id];
    final remoteReplyIds = remote.replies.map((reply) => reply.id).toSet();
    final replies = <FeedComment>[
      for (final reply in remote.replies)
        if (!removed.contains(reply.id)) mergeNode(reply),
      if (!reset && local != null)
        for (final reply in local.replies)
          if (!removed.contains(reply.id) && !remoteReplyIds.contains(reply.id))
            ...[pruneCachedNode(reply)].whereType<FeedComment>(),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final mergedReplyCount =
        remote.replyCount < replies.length ? replies.length : remote.replyCount;
    final merged = remote.copyWith(
      replies: replies,
      replyCount: mergedReplyCount,
    );
    if (local == null || !preserveLikes.contains(remote.id)) return merged;
    return merged.copyWith(
      viewerLiked: local.viewerLiked,
      likeCount: local.likeCount,
    );
  }

  bool isRemoved(FeedComment comment) =>
      removed.contains(comment.id) ||
      (comment.parentCommentId != null &&
          removed.contains(comment.parentCommentId));

  final incomingIds = incoming.map((comment) => comment.id).toSet();
  final merged = <FeedComment>[
    for (final comment in incoming)
      if (!isRemoved(comment)) mergeNode(comment),
  ];
  if (!reset) {
    for (final comment in current) {
      if (isRemoved(comment) || incomingIds.contains(comment.id)) continue;
      final pruned = pruneCachedNode(comment);
      if (pruned != null) merged.add(pruned);
    }
  }
  return merged;
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

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

DateTime? _nullableDateTime(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed?.toUtc();
}

String? _nullableString(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) return null;
  return text;
}
