import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(
  String id, {
  bool saved = false,
  bool liked = false,
  int likeCount = 0,
  bool following = false,
}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'author': {
      'id': 'author-$id',
      'name': 'Tester',
      'isFollowing': following,
    },
    'viewerSaved': saved,
    'viewerLiked': liked,
    'likeCount': likeCount,
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

void main() {
  test('save flips optimistically then reconciles server state', () async {
    final response = Completer<bool>();
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) => response.future,
    )..seed([_post('optimistic')]);

    final future = store.toggleSaved('optimistic');
    expect(store.get('optimistic')?.viewerSaved, isTrue);

    response.complete(true);
    expect(await future, isTrue);
    expect(store.get('optimistic')?.viewerSaved, isTrue);
    store.dispose();
  });

  test('rapid taps converge to the latest desired state', () async {
    final firstResponse = Completer<bool>();
    final requests = <bool>[];
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) {
        requests.add(saved);
        if (requests.length == 1) return firstResponse.future;
        return Future.value(saved);
      },
    )..seed([_post('rapid')]);

    final firstTap = store.toggleSaved('rapid');
    final secondTap = store.toggleSaved('rapid');
    expect(await secondTap, isFalse);
    expect(store.get('rapid')?.viewerSaved, isFalse);

    firstResponse.complete(true);
    expect(await firstTap, isFalse);
    expect(requests, [true, false]);
    expect(store.get('rapid')?.viewerSaved, isFalse);
    store.dispose();
  });

  test('failed save rolls back to the last confirmed state', () async {
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) =>
          Future<bool>.error(StateError('offline')),
    )..seed([_post('rollback')]);

    final future = store.toggleSaved('rollback');
    expect(store.get('rollback')?.viewerSaved, isTrue);
    await expectLater(future, throwsStateError);
    expect(store.get('rollback')?.viewerSaved, isFalse);
    store.dispose();
  });

  test('opposite server confirmation stops retries and reconciles', () async {
    var calls = 0;
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) async {
        calls++;
        return false;
      },
    )..seed([_post('rejected')]);

    expect(await store.toggleSaved('rejected'), isFalse);
    expect(calls, 1);
    expect(store.get('rejected')?.viewerSaved, isFalse);
    store.dispose();
  });

  test('stale list response cannot overwrite a newer local save', () async {
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) => Future.value(saved),
    )..seed([_post('stale')]);
    final fetchStartedAt = DateTime.now().subtract(const Duration(seconds: 1));

    await store.toggleSaved('stale');
    store.mergeFromServer([_post('stale')], fetchedAt: fetchStartedAt);

    expect(store.get('stale')?.viewerSaved, isTrue);
    store.dispose();
  });

  test('old-viewer like completion cannot mutate rebased public post',
      () async {
    final response = Completer<FeedLikeResult>();
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) => Future.value(saved),
      likeToggler: (postId, {required currentlyLiked}) => response.future,
    )..seed([
        _post(
          'viewer-like',
          saved: true,
          likeCount: 7,
          following: true,
        ),
      ]);

    final future = store.toggleLike('viewer-like');
    expect(store.get('viewer-like')?.viewerLiked, isTrue);
    expect(store.get('viewer-like')?.likeCount, 8);

    store.rebaseForViewer(1);
    final rebased = store.get('viewer-like')!;
    expect(rebased.viewerLiked, isFalse);
    expect(rebased.viewerSaved, isFalse);
    expect(rebased.author.isFollowing, isFalse);
    expect(rebased.likeCount, 7,
        reason: 'in-flight optimistic count must not leak to the new viewer');

    response.complete(const FeedLikeResult(liked: true, likeCount: 8));
    await expectLater(future, throwsA(isA<FeedViewerChangedException>()));
    expect(store.get('viewer-like')?.viewerLiked, isFalse);
    expect(store.get('viewer-like')?.likeCount, 7);
    store.dispose();
  });

  test('old-viewer save completion cannot mutate rebased saved state',
      () async {
    final response = Completer<bool>();
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) => response.future,
    )..seed([_post('viewer-save')]);

    final future = store.toggleSaved('viewer-save');
    expect(store.get('viewer-save')?.viewerSaved, isTrue);

    store.rebaseForViewer(1);
    response.complete(true);

    await expectLater(future, throwsA(isA<FeedViewerChangedException>()));
    expect(store.get('viewer-save')?.viewerSaved, isFalse);
    store.dispose();
  });

  test('old-viewer list response keeps public data but drops viewer flags', () {
    final store = FeedStore.forTesting(
      savedSetter: (postId, {required saved}) => Future.value(saved),
    )..seed([_post('stale-viewer-list', likeCount: 4)]);
    final oldViewerFetchStarted = DateTime.now();

    store.rebaseForViewer(1);
    store.mergeFromServer(
      [
        _post(
          'stale-viewer-list',
          saved: true,
          liked: true,
          likeCount: 5,
          following: true,
        ),
      ],
      fetchedAt: oldViewerFetchStarted,
    );

    final post = store.get('stale-viewer-list')!;
    expect(post.likeCount, 5, reason: 'public count should still refresh');
    expect(post.viewerLiked, isFalse);
    expect(post.viewerSaved, isFalse);
    expect(post.author.isFollowing, isFalse);
    store.dispose();
  });
}
