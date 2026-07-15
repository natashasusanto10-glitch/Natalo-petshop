import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_session_store.dart';

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
}
