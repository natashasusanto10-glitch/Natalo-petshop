import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_session_store.dart';

FeedComment _comment(String id, {List<FeedComment> replies = const []}) =>
    FeedComment(
      id: id,
      postId: 'post',
      content: id,
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.utc(2026),
      author: const FeedAuthor(id: 'author', name: 'Author'),
      viewerLiked: false,
      replies: replies,
      replyCount: replies.length,
    );

void main() {
  test('keeps comment UI state separate for each viewer and post', () {
    final store = FeedCommentSessionStore(maxSessions: 4);
    final first = store.sessionFor(viewerId: 'viewer-a', postId: 'post-1')
      ..draftText = 'draft A'
      ..scrollOffset = 120;
    final otherViewer =
        store.sessionFor(viewerId: 'viewer-b', postId: 'post-1');
    final otherPost = store.sessionFor(viewerId: 'viewer-a', postId: 'post-2');

    expect(
      store.sessionFor(viewerId: 'viewer-a', postId: 'post-1'),
      same(first),
    );
    expect(otherViewer.draftText, isEmpty);
    expect(otherPost.scrollOffset, 0);
  });

  test('evicts the least recently used session at the configured limit', () {
    final store = FeedCommentSessionStore(maxSessions: 2);
    store.sessionFor(viewerId: 'viewer', postId: 'old');
    store.sessionFor(viewerId: 'viewer', postId: 'kept');

    // Touch old, making kept the least recently used entry.
    store.sessionFor(viewerId: 'viewer', postId: 'old');
    store.sessionFor(viewerId: 'viewer', postId: 'new');

    expect(store.length, 2);
    expect(store.contains(viewerId: 'viewer', postId: 'old'), isTrue);
    expect(store.contains(viewerId: 'viewer', postId: 'new'), isTrue);
    expect(store.contains(viewerId: 'viewer', postId: 'kept'), isFalse);
  });

  test('clears only sessions belonging to the requested viewer', () {
    final store = FeedCommentSessionStore();
    store.sessionFor(viewerId: 'viewer-a', postId: 'post');
    store.sessionFor(viewerId: 'viewer-b', postId: 'post');

    store.clearForViewer('viewer-a');

    expect(store.contains(viewerId: 'viewer-a', postId: 'post'), isFalse);
    expect(store.contains(viewerId: 'viewer-b', postId: 'post'), isTrue);
  });

  test('publishes canonical comment changes with writer identity', () {
    final session = FeedCommentSession();
    final writer = Object();
    var notifications = 0;
    session.addListener(() => notifications++);

    session.replaceComments([_comment('one')], null, source: writer);

    expect(session.revision, 1);
    expect(session.lastWriter, same(writer));
    expect(session.comments.single.id, 'one');
    expect(notifications, 1);
  });

  test('explicit tombstones remove parents and nested replies', () {
    final session = FeedCommentSession();
    session.replaceComments(
        [
          _comment('parent', replies: [_comment('reply')]),
          _comment('removed-parent'),
        ],
        null,
        removedIds: const ['reply', 'removed-parent']);

    expect(session.comments.map((item) => item.id), ['parent']);
    expect(session.comments.single.replies, isEmpty);
    expect(session.comments.single.replyCount, 0);
  });

  test('does not evict an observed session from the LRU', () {
    final store = FeedCommentSessionStore(maxSessions: 1);
    final observed = store.sessionFor(viewerId: 'viewer', postId: 'live');
    void listener() {}

    observed.addListener(listener);
    store.sessionFor(viewerId: 'viewer', postId: 'new');

    expect(store.contains(viewerId: 'viewer', postId: 'live'), isTrue);
    expect(store.contains(viewerId: 'viewer', postId: 'new'), isTrue);
    observed.removeListener(listener);
  });
}
