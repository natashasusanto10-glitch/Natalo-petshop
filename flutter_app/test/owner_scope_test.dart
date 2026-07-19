import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/owner_scope.dart';

void main() {
  group('OwnerScope.ownerTag', () {
    test('null / empty / whitespace member id => guest', () {
      expect(OwnerScope.ownerTag(null), 'guest');
      expect(OwnerScope.ownerTag(''), 'guest');
      expect(OwnerScope.ownerTag('   '), 'guest');
    });

    test('member id => stable base64url tag, distinct from guest', () {
      final tag = OwnerScope.ownerTag('user_123');
      expect(tag, startsWith('m_'));
      expect(tag, isNot('guest'));
      // Deterministic for the same id.
      expect(OwnerScope.ownerTag('user_123'), tag);
    });

    test('different member ids => different tags', () {
      expect(
        OwnerScope.ownerTag('a-account'),
        isNot(OwnerScope.ownerTag('b-account')),
      );
    });

    test('tag is base64url-safe (no +, /, = or raw id chars)', () {
      final tag = OwnerScope.ownerTag('id/with+odd=chars');
      expect(tag.contains('+'), isFalse);
      expect(tag.contains('/'), isFalse);
      // Raw id must not leak verbatim into the key.
      expect(tag.contains('id/with+odd=chars'), isFalse);
    });
  });

  group('OwnerScope.key', () {
    test('namespaces the base key by owner', () {
      expect(
        OwnerScope.key('recently_viewed_v1', null),
        'recently_viewed_v1::guest',
      );
      final memberKey = OwnerScope.key('recently_viewed_v1', 'u1');
      expect(memberKey, startsWith('recently_viewed_v1::m_'));
    });

    test('guest and member keys never collide', () {
      expect(
        OwnerScope.key('feed_liked_v1', null),
        isNot(OwnerScope.key('feed_liked_v1', 'u1')),
      );
    });

    test('two accounts get isolated keys for the same base', () {
      expect(
        OwnerScope.key('search_history_v1', 'alice'),
        isNot(OwnerScope.key('search_history_v1', 'bob')),
      );
    });

    test('legacy unscoped key is never produced', () {
      expect(OwnerScope.key('x', null), isNot('x'));
      expect(OwnerScope.key('x', 'u1'), isNot('x'));
    });
  });
}
