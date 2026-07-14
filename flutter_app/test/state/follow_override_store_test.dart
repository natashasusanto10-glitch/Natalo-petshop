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
}
