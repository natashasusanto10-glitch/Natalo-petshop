import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_router.dart';

void main() {
  group('parseNataloDeepLink', () {
    test(
        'accepts official HTTPS Feed host and ignores cache and analytics query',
        () {
      final target = parseNataloDeepLink(
        Uri.parse(
          'https://www.natalopetshop.com/feed/post-1?v=preview-v2&utm_source=whatsapp',
        ),
      );

      expect(target, const FeedPostDeepLink('post-1'));
      expect(target!.dedupeKey, 'feed:post-1');
    });

    test('decodes encoded production path segments', () {
      expect(
        parseNataloDeepLink(
          Uri.parse('https://natalopetshop.com/products/royal%20canin'),
        ),
        const ProductDeepLink('royal canin'),
      );
      expect(
        parseNataloDeepLink(
          Uri.parse('https://natalopetshop.com/u/Asiong%30_01?v=old'),
        ),
        const ProfileDeepLink('asiong0_01'),
      );
    });

    test('normalizes profile identity and query does not change dedupe target',
        () {
      final withVersion = parseNataloDeepLink(
        Uri.parse('https://natalopetshop.com/u/NataloUser?v=one&utm_medium=wa'),
      );
      final withoutVersion = parseNataloDeepLink(
        Uri.parse('https://www.natalopetshop.com/u/natalouser?v=two'),
      );

      expect(withVersion, const ProfileDeepLink('natalouser'));
      expect(withVersion!.dedupeKey, withoutVersion!.dedupeKey);
    });

    test('rejects deceptive hosts, non-HTTPS, malformed and unknown routes',
        () {
      final rejected = <Uri>[
        Uri.parse('https://www.natalopetshop.com.evil.test/feed/post-1'),
        Uri.parse('http://www.natalopetshop.com/feed/post-1'),
        Uri.parse('https://www.natalopetshop.com:8443/feed/post-1'),
        Uri.parse('https://www.natalopetshop.com/feed/post-1/extra'),
        Uri.parse('https://www.natalopetshop.com/feed/%2F'),
        Uri.parse('https://www.natalopetshop.com/unknown/post-1'),
      ];

      for (final uri in rejected) {
        expect(parseNataloDeepLink(uri), isNull, reason: uri.toString());
      }
    });
  });

  group('isPathOnlyNataloInternalUri', () {
    test(
        'preserves path-only Feed, product, and profile links for legacy routing',
        () {
      expect(isPathOnlyNataloInternalUri(Uri.parse('/feed/post-1')), isTrue);
      expect(
        isPathOnlyNataloInternalUri(Uri.parse('/products/royal-canin')),
        isTrue,
      );
      expect(isPathOnlyNataloInternalUri(Uri.parse('/u/natalo')), isTrue);
    });

    test('does not treat authority or production HTTPS URLs as path-only', () {
      expect(
        isPathOnlyNataloInternalUri(Uri.parse('//evil.test/feed/post-1')),
        isFalse,
      );
      expect(
        isPathOnlyNataloInternalUri(
          Uri.parse('https://www.natalopetshop.com/feed/post-1'),
        ),
        isFalse,
      );
    });
  });
}
