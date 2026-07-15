import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id, {bool saved = false}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'author': {'id': 'author-$id', 'name': 'Tester'},
    'viewerSaved': saved,
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
}
