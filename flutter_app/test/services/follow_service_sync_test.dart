import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/follow_service.dart';
import 'package:natalo_petshop_flutter/state/follow_override_store.dart';

Map<String, dynamic> followResponse(bool following) => <String, dynamic>{
      'isFollowing': following,
      'followersCount': following ? 11 : 10,
      'followingCount': following ? 4 : 3,
      'changed': true,
    };

void main() {
  setUp(clearFollowOverrides);
  tearDown(clearFollowOverrides);

  test('rapid follow then unfollow serializes and latest intent wins',
      () async {
    final firstRequest = Completer<dynamic>();
    final calls = <bool>[];
    final service = FollowService.forTesting(
      mutationRequest: (userId, following) async {
        calls.add(following);
        if (calls.length == 1) return firstRequest.future;
        return followResponse(following);
      },
    );

    final followFuture = service.follow('user-1');
    await Future<void>.delayed(Duration.zero);
    final unfollowFuture = service.unfollow('user-1');

    expect(identical(followFuture, unfollowFuture), isTrue);
    expect(resolveFollowState('user-1', false), isFalse);

    firstRequest.complete(followResponse(true));
    final results = await Future.wait(<Future<FollowState>>[
      followFuture,
      unfollowFuture,
    ]);

    expect(calls, <bool>[true, false]);
    expect(results.map((state) => state.isFollowing), everyElement(isFalse));
    expect(resolveFollowState('user-1', true), isFalse);
    expect(isFollowMutationPending('user-1'), isFalse);
  });

  test('failed latest request rolls back to last confirmed server state',
      () async {
    final firstRequest = Completer<dynamic>();
    var callCount = 0;
    final service = FollowService.forTesting(
      mutationRequest: (userId, following) async {
        callCount++;
        if (callCount == 1) return firstRequest.future;
        throw StateError('network failed');
      },
    );

    final result = service.follow('user-1');
    await Future<void>.delayed(Duration.zero);
    service.unfollow('user-1');
    firstRequest.complete(followResponse(true));

    await expectLater(result, throwsStateError);
    expect(resolveFollowState('user-1', false), isTrue);
    expect(isFollowMutationPending('user-1'), isFalse);
  });

  test('late follow-state refresh cannot overwrite a newer local mutation',
      () async {
    final stateRequest = Completer<dynamic>();
    final mutationRequest = Completer<dynamic>();
    final service = FollowService.forTesting(
      stateRequest: (_) => stateRequest.future,
      mutationRequest: (_, __) => mutationRequest.future,
    );

    final refresh = service.fetchState('user-1');
    final mutation = service.follow('user-1');
    stateRequest.complete(followResponse(false));
    await refresh;

    expect(resolveFollowState('user-1', false), isTrue);

    mutationRequest.complete(followResponse(true));
    await mutation;
    expect(resolveFollowState('user-1', false), isTrue);
  });

  test('refresh started during mutation cannot overwrite confirmation',
      () async {
    final stateRequest = Completer<dynamic>();
    final mutationRequest = Completer<dynamic>();
    final service = FollowService.forTesting(
      stateRequest: (_) => stateRequest.future,
      mutationRequest: (_, __) => mutationRequest.future,
    );

    final mutation = service.follow('user-1');
    final staleRefresh = service.fetchState('user-1');

    mutationRequest.complete(followResponse(true));
    await mutation;
    stateRequest.complete(followResponse(false));
    await staleRefresh;

    expect(resolveFollowState('user-1', false), isTrue);
    expect(isFollowMutationPending('user-1'), isFalse);
  });

  test('refresh started during failed mutation cannot overwrite rollback',
      () async {
    final stateRequest = Completer<dynamic>();
    final mutationRequest = Completer<dynamic>();
    final service = FollowService.forTesting(
      stateRequest: (_) => stateRequest.future,
      mutationRequest: (_, __) => mutationRequest.future,
    );

    final mutation = service.follow('user-1');
    final staleRefresh = service.fetchState('user-1');

    mutationRequest.completeError(StateError('network failed'));
    await expectLater(mutation, throwsStateError);
    stateRequest.complete(followResponse(true));
    await staleRefresh;

    expect(resolveFollowState('user-1', false), isFalse);
    expect(isFollowMutationPending('user-1'), isFalse);
  });

  test('stale session completion cannot succeed or remove a new intent',
      () async {
    final requests = <Completer<dynamic>>[];
    final service = FollowService.forTesting(
      mutationRequest: (_, __) {
        final request = Completer<dynamic>();
        requests.add(request);
        return request.future;
      },
    );

    final stale = service.follow('user-1');
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));

    service.clearSessionState();
    clearFollowOverrides();
    final current = service.follow('user-1');
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(2));

    requests.first.complete(followResponse(true));
    await expectLater(
      stale,
      throwsA(isA<FollowSessionChangedException>()),
    );
    expect(resolveFollowState('user-1', false), isTrue,
        reason: 'the current session optimistic intent remains authoritative');
    expect(isFollowMutationPending('user-1'), isTrue);

    requests.last.complete(followResponse(true));
    final result = await current;
    expect(result.isFollowing, isTrue);
    expect(resolveFollowState('user-1', false), isTrue);
    expect(isFollowMutationPending('user-1'), isFalse);
  });

  test('server canonical rejection stops without retrying forever', () async {
    var callCount = 0;
    final service = FollowService.forTesting(
      mutationRequest: (_, __) async {
        callCount++;
        return followResponse(false);
      },
    );

    final result = await service.follow('user-1');

    expect(callCount, 1);
    expect(result.isFollowing, isFalse);
    expect(resolveFollowState('user-1', true), isFalse);
    expect(isFollowMutationPending('user-1'), isFalse);
  });

  test('follow-state response from previous viewer is ignored', () async {
    final stateRequest = Completer<dynamic>();
    final service = FollowService.forTesting(
      stateRequest: (_) => stateRequest.future,
      mutationRequest: (_, following) async => followResponse(following),
    );

    final staleRefresh = service.fetchState('user-1');
    service.clearSessionState();
    clearFollowOverrides();
    stateRequest.complete(followResponse(true));

    await expectLater(
      staleRefresh,
      throwsA(isA<FollowSessionChangedException>()),
    );
    expect(followOverrides.value, isEmpty);
  });

  test('fresh server state becomes the baseline for the next mutation',
      () async {
    var serverFollowing = false;
    var mutationCount = 0;
    final service = FollowService.forTesting(
      stateRequest: (_) async => followResponse(serverFollowing),
      mutationRequest: (_, following) async {
        mutationCount++;
        serverFollowing = following;
        return followResponse(serverFollowing);
      },
    );

    await service.follow('user-1');
    expect(mutationCount, 1);

    // Simulate an unfollow performed on another device, then refresh Natalo.
    serverFollowing = false;
    final refreshed = await service.fetchState('user-1');
    expect(refreshed.isFollowing, isFalse);

    await service.follow('user-1');
    expect(mutationCount, 2,
        reason: 'the refreshed false state must replace the old true baseline');
    expect(resolveFollowState('user-1', false), isTrue);
  });
}
