import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_sync_coordinator.dart';

void main() {
  testWidgets('deduplicates refresh for the same viewer and post',
      (tester) async {
    final coordinator = FeedCommentSyncCoordinator(
      interval: const Duration(hours: 1),
    );
    addTearDown(coordinator.clear);
    var firstCalls = 0;
    var latestCalls = 0;
    final first = coordinator.register(
      viewerId: 'viewer',
      postId: 'post',
      refresh: () async => firstCalls++,
    );
    final latest = coordinator.register(
      viewerId: 'viewer',
      postId: 'post',
      refresh: () async => latestCalls++,
    );

    await coordinator.debugTick();

    expect(firstCalls, 0);
    expect(latestCalls, 1);
    expect(coordinator.activeKeyCount, 1);
    latest.dispose();
    await coordinator.debugTick();
    expect(firstCalls, 1);
    first.dispose();
    expect(coordinator.activeKeyCount, 0);
  });

  testWidgets('serializes an in-flight refresh per key', (tester) async {
    final coordinator = FeedCommentSyncCoordinator(
      interval: const Duration(hours: 1),
    );
    addTearDown(coordinator.clear);
    final completer = Completer<void>();
    var calls = 0;
    final lease = coordinator.register(
      viewerId: 'viewer',
      postId: 'post',
      refresh: () {
        calls++;
        return completer.future;
      },
    );

    final first = coordinator.debugTick();
    await coordinator.debugTick();
    expect(calls, 1);
    completer.complete();
    await first;
    lease.dispose();
  });

  testWidgets('clear isolates an old completion from a new in-flight token',
      (tester) async {
    final coordinator = FeedCommentSyncCoordinator(
      interval: const Duration(hours: 1),
    );
    addTearDown(coordinator.clear);
    final oldRequest = Completer<void>();
    final newRequest = Completer<void>();
    var oldCalls = 0;
    var newCalls = 0;

    coordinator.register(
      viewerId: 'viewer',
      postId: 'post',
      refresh: () {
        oldCalls++;
        return oldRequest.future;
      },
    );
    final oldTick = coordinator.debugTick();
    expect(oldCalls, 1);

    coordinator.clear();
    final newLease = coordinator.register(
      viewerId: 'viewer',
      postId: 'post',
      refresh: () {
        newCalls++;
        return newRequest.future;
      },
    );
    final newTick = coordinator.debugTick();
    expect(newCalls, 1);

    oldRequest.complete();
    await oldTick;
    await coordinator.debugTick();
    expect(newCalls, 1,
        reason: 'the old finally must not remove the new flight token');

    newRequest.complete();
    await newTick;
    newLease.dispose();
  });

  test('default revalidation interval is 5 seconds', () {
    final coordinator = FeedCommentSyncCoordinator();
    addTearDown(coordinator.clear);
    expect(coordinator.interval, const Duration(seconds: 5));
  });
}
