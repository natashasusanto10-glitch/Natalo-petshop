import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

void main() {
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
}
