import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/api_client.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_interaction_store.dart';

Matcher hasLikeState({required bool liked, required int count}) =>
    isA<FeedCommentLikeState>()
        .having((state) => state.liked, 'liked', liked)
        .having((state) => state.count, 'count', count);

void main() {
  test('toggle applies an optimistic comment like before server confirmation',
      () async {
    final calls = <bool>[];
    final store = FeedCommentInteractionStore(
      setCommentLiked: (commentId, {required liked}) async {
        calls.add(liked);
        return 14;
      },
    );
    addTearDown(store.dispose);
    store.seed(
      postId: 'post-1',
      commentId: 'comment-1',
      liked: false,
      count: 13,
    );

    final completion = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 13,
    );

    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: true, count: 14));
    await completion;
    expect(calls, [true]);
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: true, count: 14));
  });

  test('rapid toggles serialize requests and settle on the latest intent',
      () async {
    final firstResponse = Completer<int>();
    final secondResponse = Completer<int>();
    final calls = <bool>[];
    final store = FeedCommentInteractionStore(
      setCommentLiked: (commentId, {required liked}) {
        calls.add(liked);
        return calls.length == 1 ? firstResponse.future : secondResponse.future;
      },
    );
    addTearDown(store.dispose);
    store.seed(
      postId: 'post-1',
      commentId: 'comment-1',
      liked: false,
      count: 10,
    );

    final firstToggle = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 10,
    );
    final secondToggle = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 10,
    );

    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: false, count: 10));
    expect(calls, [true]);
    firstResponse.complete(11);
    await Future<void>.delayed(Duration.zero);
    expect(calls, [true, false]);
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: false, count: 10));
    secondResponse.complete(10);

    await Future.wait([firstToggle, secondToggle]);
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: false, count: 10));
  });

  test('an older response never publishes over a newer matching intent',
      () async {
    final firstResponse = Completer<int>();
    final latestResponse = Completer<int>();
    final calls = <bool>[];
    final visibleStates = <String>[];
    final store = FeedCommentInteractionStore(
      setCommentLiked: (commentId, {required liked}) {
        calls.add(liked);
        return calls.length == 1 ? firstResponse.future : latestResponse.future;
      },
    );
    addTearDown(store.dispose);
    store.seed(
      postId: 'post-1',
      commentId: 'comment-1',
      liked: false,
      count: 10,
    );
    store.addListener(() {
      final state = store.likeState('post-1', 'comment-1');
      visibleStates.add('${state?.liked}:${state?.count}');
    });

    final owner = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 10,
    );
    final secondTap = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: true,
      currentCount: 11,
    );
    final latestTap = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 10,
    );

    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: true, count: 11));
    visibleStates.clear();

    firstResponse.complete(91);
    await Future<void>.delayed(Duration.zero);

    expect(calls, [true, true]);
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: true, count: 11));
    expect(visibleStates, isNot(contains('true:91')));

    latestResponse.complete(12);
    await Future.wait([owner, secondTap, latestTap]);
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: true, count: 12));
  });

  test('a final queued failure rolls back to the last confirmed response',
      () async {
    final firstResponse = Completer<int>();
    final finalResponse = Completer<int>();
    final calls = <bool>[];
    final store = FeedCommentInteractionStore(
      setCommentLiked: (commentId, {required liked}) {
        calls.add(liked);
        return calls.length == 1 ? firstResponse.future : finalResponse.future;
      },
    );
    addTearDown(store.dispose);
    store.seed(
      postId: 'post-1',
      commentId: 'comment-1',
      liked: false,
      count: 10,
    );

    final owner = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 10,
    );
    final coalesced = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: true,
      currentCount: 11,
    );

    firstResponse.complete(11);
    await Future<void>.delayed(Duration.zero);
    expect(calls, [true, false]);
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: false, count: 10));

    finalResponse.completeError(StateError('second request failed'));
    await expectLater(owner, throwsA(isA<StateError>()));
    await coalesced;
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: true, count: 11));
  });

  test('the request owner still receives API 401 after optimistic rollback',
      () async {
    final response = Completer<int>();
    final store = FeedCommentInteractionStore(
      setCommentLiked: (commentId, {required liked}) => response.future,
    );
    addTearDown(store.dispose);
    store.seed(
      postId: 'post-1',
      commentId: 'comment-1',
      liked: false,
      count: 3,
    );

    final owner = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 3,
    );
    final coalesced = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: true,
      currentCount: 4,
    );

    response.completeError(
      const ApiException('Unauthorized', statusCode: 401),
    );

    await expectLater(
      owner,
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    await coalesced;
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: false, count: 3));
  });

  test('a failed server request rolls the optimistic state back', () async {
    final store = FeedCommentInteractionStore(
      setCommentLiked: (commentId, {required liked}) async {
        throw StateError('network unavailable');
      },
    );
    addTearDown(store.dispose);
    store.seed(
      postId: 'post-1',
      commentId: 'comment-1',
      liked: false,
      count: 3,
    );

    final completion = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 3,
    );

    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: true, count: 4));
    await expectLater(completion, throwsA(isA<StateError>()));
    expect(store.likeState('post-1', 'comment-1'),
        hasLikeState(liked: false, count: 3));
  });

  test('a viewer generation change clears state and ignores old responses',
      () async {
    final generation = ValueNotifier(0);
    final response = Completer<int>();
    final store = FeedCommentInteractionStore(
      viewerChanges: generation,
      viewerGeneration: () => generation.value,
      setCommentLiked: (commentId, {required liked}) => response.future,
    );
    addTearDown(() {
      store.dispose();
      generation.dispose();
    });
    store.seed(
      postId: 'post-1',
      commentId: 'comment-1',
      liked: false,
      count: 1,
    );
    final completion = store.toggle(
      postId: 'post-1',
      commentId: 'comment-1',
      currentlyLiked: false,
      currentCount: 1,
    );

    generation.value = 1;
    expect(store.likeState('post-1', 'comment-1'), isNull);
    expect(store.pendingCommentIdsForPost('post-1'), isEmpty);

    response.complete(2);
    await completion;
    expect(store.likeState('post-1', 'comment-1'), isNull);
  });
}
