import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

void main() {
  test('parses additive comment synchronization metadata', () {
    final page = FeedCommentPage.fromApiJson({
      'items': [
        {
          'id': 'comment-1',
          'postId': 'post-1',
          'content': 'Hello',
          'createdAt': '2026-07-15T11:00:00.000Z',
          'author': {
            'id': 'user-1',
            'name': 'User One',
            'role': 'CUSTOMER',
          },
        },
      ],
      'nextCursor': 'comment-1',
      'commentCount': 12,
      'syncCursor': '2026-07-15T12:00:00.000Z',
      'syncTime': '2026-07-15T12:00:00.000Z',
      'removedCommentIds': ['removed-1', 'removed-2', 'removed-1', ''],
      'syncResetRequired': true,
    });

    expect(page.items.single.id, 'comment-1');
    expect(page.nextCursor, 'comment-1');
    expect(page.commentCount, 12);
    expect(page.syncCursor, DateTime.utc(2026, 7, 15, 12));
    expect(page.syncTime, DateTime.utc(2026, 7, 15, 12));
    expect(page.removedCommentIds, {'removed-1', 'removed-2'});
    expect(page.removedIds, page.removedCommentIds);
    expect(page.syncResetRequired, isTrue);
  });

  test('keeps legacy comment pages backward compatible', () {
    final page = FeedCommentPage.fromApiJson({
      'comments': const <Map<String, dynamic>>[],
      'nextCursor': null,
    });

    expect(page.items, isEmpty);
    expect(page.commentCount, isNull);
    expect(page.syncCursor, isNull);
    expect(page.syncTime, isNull);
    expect(page.removedCommentIds, isEmpty);
    expect(page.syncResetRequired, isFalse);
  });

  test('merges changed comment items without duplicate IDs', () {
    Map<String, dynamic> comment(String id, String content) => {
          'id': id,
          'postId': 'post-1',
          'content': content,
          'createdAt': '2026-07-15T11:00:00.000Z',
          'author': {
            'id': 'user-1',
            'name': 'User One',
            'role': 'CUSTOMER',
          },
        };

    final page = FeedCommentPage.fromApiJson({
      'items': [comment('comment-1', 'old')],
      'changedItems': [
        comment('comment-1', 'updated'),
        comment('comment-2', 'new'),
      ],
    });

    expect(page.items.map((item) => item.id), ['comment-1', 'comment-2']);
    expect(page.items.first.content, 'updated');
  });

  test('parses nested replies returned by comments API', () {
    final comment = FeedComment.fromApiJson({
      'id': 'parent-1',
      'postId': 'post-1',
      'content': 'Parent',
      'createdAt': '2026-07-14T01:00:00.000Z',
      'author': {
        'id': 'user-1',
        'name': 'User One',
        'role': 'CUSTOMER',
      },
      'replies': [
        {
          'id': 'reply-1',
          'postId': 'post-1',
          'parentCommentId': 'parent-1',
          'content': 'Reply',
          'createdAt': '2026-07-14T01:01:00.000Z',
          'author': {
            'id': 'user-2',
            'name': 'User Two',
            'role': 'CUSTOMER',
          },
        },
      ],
    });

    expect(comment.replies, hasLength(1));
    expect(comment.replies.single.id, 'reply-1');
    expect(comment.replies.single.parentCommentId, 'parent-1');
    expect(comment.replyCount, 1);
  });

  test('recognizes official comment author for brand avatar', () {
    final comment = FeedComment.fromApiJson({
      'id': 'comment-1',
      'postId': 'post-1',
      'content': 'Official',
      'createdAt': '2026-07-14T01:00:00.000Z',
      'author': {
        'id': 'admin-1',
        'name': 'Natalo Petshop',
        'role': 'ADMIN',
        'profilePhotoUrl': null,
      },
    });

    expect(comment.author.isOfficialAccount, isTrue);
  });

  test('flattens nested and legacy flat replies without duplicates', () {
    FeedComment makeComment({
      required String id,
      String? parentId,
      List<FeedComment> replies = const [],
      required int minute,
    }) {
      return FeedComment(
        id: id,
        postId: 'post-1',
        parentCommentId: parentId,
        content: id,
        isAdminOfficial: false,
        isHidden: false,
        likeCount: 0,
        createdAt: DateTime.utc(2026, 7, 14, 1, minute),
        author: const FeedAuthor(id: 'user-1', name: 'User'),
        viewerLiked: false,
        replies: replies,
      );
    }

    final nestedReply = makeComment(
      id: 'reply-1',
      parentId: 'parent-1',
      minute: 2,
    );
    final olderFlatReply = makeComment(
      id: 'reply-2',
      parentId: 'parent-1',
      minute: 1,
    );
    final parent = makeComment(
      id: 'parent-1',
      replies: [nestedReply],
      minute: 0,
    );

    final items = flattenFeedCommentThreads([
      parent,
      olderFlatReply,
      nestedReply,
    ]);

    expect(items.map((item) => item.comment.id), [
      'parent-1',
      'reply-2',
      'reply-1',
    ]);
    expect(items.map((item) => item.isReply), [false, true, true]);

    final threads = groupFeedCommentThreads([
      parent,
      olderFlatReply,
      nestedReply,
    ]);
    expect(threads, hasLength(1));
    expect(threads.single.parent.id, 'parent-1');
    expect(
      threads.single.replies.map((reply) => reply.id),
      ['reply-2', 'reply-1'],
    );
  });

  test('reply preview keeps only latest batch in chronological order', () {
    FeedComment reply(String id, int minute) => FeedComment(
          id: id,
          postId: 'post-1',
          parentCommentId: 'parent-1',
          content: id,
          isAdminOfficial: false,
          isHidden: false,
          likeCount: 0,
          createdAt: DateTime.utc(2026, 7, 14, 1, minute),
          author: const FeedAuthor(id: 'user-1', name: 'User'),
          viewerLiked: false,
        );

    final replies = [
      reply('reply-1', 1),
      reply('reply-2', 2),
      reply('reply-3', 3),
      reply('reply-4', 4),
      reply('reply-5', 5),
    ];

    expect(latestVisibleFeedReplies(replies, 0), isEmpty);
    expect(
      latestVisibleFeedReplies(replies, 3).map((reply) => reply.id),
      ['reply-3', 'reply-4', 'reply-5'],
    );
    expect(latestVisibleFeedReplies(replies, 99), replies);
  });

  test('removing a reply decrements the server total only once', () {
    FeedComment reply(String id) => FeedComment(
          id: id,
          postId: 'post-1',
          parentCommentId: 'parent-1',
          content: id,
          isAdminOfficial: false,
          isHidden: false,
          likeCount: 0,
          createdAt: DateTime.utc(2026, 7, 15),
          author: const FeedAuthor(id: 'user-1', name: 'User'),
          viewerLiked: false,
        );

    final replyOne = reply('reply-1');
    final parent = FeedComment(
      id: 'parent-1',
      postId: 'post-1',
      content: 'Parent',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15),
      author: const FeedAuthor(id: 'user-1', name: 'User'),
      viewerLiked: false,
      replies: [replyOne, reply('reply-2')],
      replyCount: 8,
    );

    final result = removeFeedCommentFromThreads([parent], replyOne);

    expect(result.comments.single.replies.map((item) => item.id), ['reply-2']);
    expect(result.comments.single.replyCount, 7);
    expect(result.removedIds, {'reply-1'});
  });

  test('removing a legacy flat reply decrements its parent total', () {
    final parent = FeedComment(
      id: 'parent-1',
      postId: 'post-1',
      content: 'Parent',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15),
      author: const FeedAuthor(id: 'user-1', name: 'User'),
      viewerLiked: false,
      replyCount: 5,
    );
    final flatReply = FeedComment(
      id: 'reply-flat',
      postId: 'post-1',
      parentCommentId: 'parent-1',
      content: 'Flat reply',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15),
      author: const FeedAuthor(id: 'user-2', name: 'User Two'),
      viewerLiked: false,
    );

    final result = removeFeedCommentFromThreads([parent, flatReply], flatReply);

    expect(result.comments, hasLength(1));
    expect(result.comments.single.id, 'parent-1');
    expect(result.comments.single.replyCount, 4);
  });

  test('removing a parent invalidates its loaded reply targets', () {
    final reply = FeedComment(
      id: 'reply-1',
      postId: 'post-1',
      parentCommentId: 'parent-1',
      content: 'Reply',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15),
      author: const FeedAuthor(id: 'user-2', name: 'User Two'),
      viewerLiked: false,
    );
    final parent = FeedComment(
      id: 'parent-1',
      postId: 'post-1',
      content: 'Parent',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15),
      author: const FeedAuthor(id: 'user-1', name: 'User One'),
      viewerLiked: false,
      replies: [reply],
      replyCount: 4,
    );

    final legacyFlatReply = FeedComment(
      id: 'reply-legacy',
      postId: 'post-1',
      parentCommentId: 'parent-1',
      content: 'Legacy reply',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15),
      author: const FeedAuthor(id: 'user-3', name: 'User Three'),
      viewerLiked: false,
    );

    final result =
        removeFeedCommentFromThreads([parent, legacyFlatReply], parent);

    expect(result.comments, isEmpty);
    expect(result.removedIds, {'parent-1', 'reply-1', 'reply-legacy'});
  });

  test('refresh merges a fresh head, cached tail, and explicit tombstones', () {
    FeedComment comment(
      String id,
      int minute, {
      bool liked = false,
      int likeCount = 0,
    }) =>
        FeedComment(
          id: id,
          postId: 'post-1',
          content: id,
          isAdminOfficial: false,
          isHidden: false,
          likeCount: likeCount,
          createdAt: DateTime.utc(2026, 7, 15, 1, minute),
          author: const FeedAuthor(id: 'user-1', name: 'User'),
          viewerLiked: liked,
        );

    final merged = mergeFeedCommentRefresh(
      current: [
        comment('head', 3, liked: true, likeCount: 4),
        comment('removed', 2),
        comment('cached-tail', 1),
      ],
      incoming: [
        comment('new-head', 4),
        comment('head', 3, liked: false, likeCount: 3),
      ],
      removedIds: const {'removed'},
      preserveLocalLikeIds: const {'head'},
    );

    expect(
      merged.map((item) => item.id),
      ['new-head', 'head', 'cached-tail'],
    );
    expect(merged[1].viewerLiked, isTrue);
    expect(merged[1].likeCount, 4);
  });

  test('expired sync reset drops stale cached tail', () {
    FeedComment comment(String id) => FeedComment(
          id: id,
          postId: 'post-1',
          content: id,
          isAdminOfficial: false,
          isHidden: false,
          likeCount: 0,
          createdAt: DateTime.utc(2026, 7, 15),
          author: const FeedAuthor(id: 'user-1', name: 'User'),
          viewerLiked: false,
        );

    final merged = mergeFeedCommentRefresh(
      current: [comment('fresh'), comment('stale-tail')],
      incoming: [comment('fresh')],
      reset: true,
    );

    expect(merged.map((item) => item.id), ['fresh']);
  });

  test('reply tombstone is pruned from a cached parent thread', () {
    final reply = FeedComment(
      id: 'reply-removed',
      postId: 'post-1',
      parentCommentId: 'parent-1',
      content: 'Reply',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15, 1),
      author: const FeedAuthor(id: 'user-2', name: 'Reply author'),
      viewerLiked: false,
    );
    final parent = FeedComment(
      id: 'parent-1',
      postId: 'post-1',
      content: 'Parent',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026, 7, 15),
      author: const FeedAuthor(id: 'user-1', name: 'Parent author'),
      viewerLiked: false,
      replies: [reply],
      replyCount: 1,
    );

    final merged = mergeFeedCommentRefresh(
      current: [parent],
      incoming: const [],
      removedIds: const {'reply-removed'},
    );

    expect(merged, hasLength(1));
    expect(merged.single.replies, isEmpty);
    expect(merged.single.replyCount, 0);
  });
}
