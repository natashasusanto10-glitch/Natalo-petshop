import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/follow_service.dart';
import 'package:natalo_petshop_flutter/state/follow_override_store.dart';

void main() {
  setUp(clearFollowOverrides);
  tearDown(clearFollowOverrides);

  test('override terbaru mengalahkan snapshot server yang stale', () {
    setFollowOverride('user-1', true);

    expect(resolveFollowState('user-1', false), isTrue);
    expect(resolveFollowState('user-2', false), isFalse);
  });

  test('clear menghapus state viewer sebelumnya', () {
    setFollowOverride('user-1', true);
    clearFollowOverrides();

    expect(followOverrides.value, isEmpty);
    expect(resolveFollowState('user-1', false), isFalse);
  });

  test('id kosong tidak disimpan sebagai override', () {
    setFollowOverride('', true);

    expect(followOverrides.value, isEmpty);
  });

  test('hasil list server memakai override terbaru', () {
    setFollowOverride('user-1', true);

    final result = FollowListResult.fromJson({
      'items': [
        {
          'id': 'user-1',
          'name': 'User One',
          'username': 'userone',
          'isFollowing': false,
        },
      ],
    });

    expect(result.items.single.isFollowing, isTrue);
  });

  test('server snapshot cannot overwrite a pending mutation', () {
    beginFollowMutation('user-1', true);
    final revision = followStateRevision('user-1');

    final applied = reconcileFollowStateFromServer(
      'user-1',
      false,
      observedRevision: revision,
    );

    expect(applied, isFalse);
    expect(resolveFollowState('user-1', false), isTrue);
  });

  test('late response cannot overwrite a newer local action', () {
    final observedRevision = followStateRevision('user-1');
    setFollowOverride('user-1', true);

    final applied = reconcileFollowStateFromServer(
      'user-1',
      false,
      observedRevision: observedRevision,
    );

    expect(applied, isFalse);
    expect(resolveFollowState('user-1', false), isTrue);
  });

  test('mutation bumps revision even after widget wrote optimistic value', () {
    setFollowOverride('user-1', true);
    beginFollowMutation('user-1', true);
    final readRevision = followStateRevision('user-1');
    confirmFollowMutation('user-1', true);

    final applied = reconcileFollowStateFromServer(
      'user-1',
      false,
      observedRevision: readRevision,
    );

    expect(applied, isFalse);
    expect(resolveFollowState('user-1', false), isTrue);
  });

  test('abandon invalidates a server read started while mutation was pending',
      () {
    beginFollowMutation('user-1', true);
    final readRevision = followStateRevision('user-1');
    abandonFollowMutation('user-1');

    final applied = reconcileFollowStateFromServer(
      'user-1',
      false,
      observedRevision: readRevision,
    );

    expect(applied, isFalse);
    expect(followStateRevision('user-1'), greaterThan(readRevision));
  });

  test('fresh server state self-heals when no mutation is pending', () {
    setFollowOverride('user-1', true);
    final observedRevision = followStateRevision('user-1');

    final applied = reconcileFollowStateFromServer(
      'user-1',
      false,
      observedRevision: observedRevision,
    );

    expect(applied, isTrue);
    expect(resolveFollowState('user-1', true), isFalse);
  });
}
