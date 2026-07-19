import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/payment_url_policy.dart';

void main() {
  group('isValidMidtransPaymentUrl', () {
    test('accepts exact production snap URL', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.midtrans.com/snap/v4/redirection/abc123',
        ),
        isTrue,
      );
    });

    test('accepts exact sandbox snap URL', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.sandbox.midtrans.com/snap/v2/vtweb/tok',
        ),
        isTrue,
      );
    });

    test('rejects http (non-TLS)', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'http://app.midtrans.com/snap/v4/redirection/abc',
        ),
        isFalse,
      );
    });

    test('rejects userInfo credential-stuffing lookalike', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.midtrans.com@evil.com/snap/x',
        ),
        isFalse,
      );
    });

    test('rejects suffix lookalike host', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.midtrans.com.evil.com/snap/x',
        ),
        isFalse,
      );
    });

    test('rejects prefix lookalike host', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://evil-app.midtrans.com/snap/x',
        ),
        isFalse,
      );
    });

    test('rejects non-default port', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.midtrans.com:8443/snap/x',
        ),
        isFalse,
      );
    });

    test('accepts explicit default port 443', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.midtrans.com:443/snap/x',
        ),
        isTrue,
      );
    });

    test('rejects wrong path (not /snap/)', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.midtrans.com/pay/x',
        ),
        isFalse,
      );
    });

    test('rejects /snap prefix without boundary slash', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://app.midtrans.com/snapshot/x',
        ),
        isFalse,
      );
    });

    test('rejects javascript/data/file/intent schemes', () {
      for (final url in <String>[
        'javascript:alert(1)',
        'data:text/html,<script>1</script>',
        'file:///etc/passwd',
        'intent://app.midtrans.com/snap/x#Intent;scheme=https;end',
      ]) {
        expect(PaymentUrlPolicy.isValidMidtransPaymentUrl(url), isFalse,
            reason: url);
      }
    });

    test('rejects null / empty / garbage', () {
      expect(PaymentUrlPolicy.isValidMidtransPaymentUrl(null), isFalse);
      expect(PaymentUrlPolicy.isValidMidtransPaymentUrl(''), isFalse);
      expect(PaymentUrlPolicy.isValidMidtransPaymentUrl('not a url'), isFalse);
    });

    test('host match is case-insensitive', () {
      expect(
        PaymentUrlPolicy.isValidMidtransPaymentUrl(
          'https://APP.MIDTRANS.COM/snap/x',
        ),
        isTrue,
      );
    });
  });

  group('isAllowedEmbeddedNavigation', () {
    test('allows Natalo apex + www over https', () {
      expect(
        PaymentUrlPolicy.isAllowedEmbeddedNavigation(
          'https://natalopetshop.com/bantuan',
        ),
        isTrue,
      );
      expect(
        PaymentUrlPolicy.isAllowedEmbeddedNavigation(
          'https://www.natalopetshop.com/blog',
        ),
        isTrue,
      );
    });

    test('rejects non-Natalo https origin', () {
      expect(
        PaymentUrlPolicy.isAllowedEmbeddedNavigation('https://google.com'),
        isFalse,
      );
    });

    test('rejects Natalo over http', () {
      expect(
        PaymentUrlPolicy.isAllowedEmbeddedNavigation(
          'http://natalopetshop.com/x',
        ),
        isFalse,
      );
    });

    test('rejects userInfo lookalike', () {
      expect(
        PaymentUrlPolicy.isAllowedEmbeddedNavigation(
          'https://natalopetshop.com@evil.com/x',
        ),
        isFalse,
      );
    });

    test('rejects suffix lookalike host', () {
      expect(
        PaymentUrlPolicy.isAllowedEmbeddedNavigation(
          'https://natalopetshop.com.evil.com/x',
        ),
        isFalse,
      );
    });

    test('honors extra allowed hosts (e.g. api origin)', () {
      expect(
        PaymentUrlPolicy.isAllowedEmbeddedNavigation(
          'https://api.natalopetshop.com/x',
          extraHosts: const {'api.natalopetshop.com'},
        ),
        isTrue,
      );
    });

    test('rejects foreign / dangerous schemes', () {
      for (final url in <String>[
        'javascript:alert(1)',
        'data:text/html,x',
        'file:///x',
        'intent://x#Intent;end',
      ]) {
        expect(PaymentUrlPolicy.isAllowedEmbeddedNavigation(url), isFalse,
            reason: url);
      }
    });
  });

  group('shouldOpenExternally', () {
    test('https to non-Natalo opens externally', () {
      expect(
        PaymentUrlPolicy.shouldOpenExternally('https://instagram.com/natalo'),
        isTrue,
      );
    });

    test('mailto and tel open externally', () {
      expect(PaymentUrlPolicy.shouldOpenExternally('mailto:a@b.com'), isTrue);
      expect(PaymentUrlPolicy.shouldOpenExternally('tel:+628123'), isTrue);
    });

    test('http is rejected (not opened)', () {
      expect(
        PaymentUrlPolicy.shouldOpenExternally('http://example.com'),
        isFalse,
      );
    });

    test('dangerous schemes are never opened', () {
      for (final url in <String>[
        'javascript:alert(1)',
        'data:text/html,x',
        'file:///x',
        'intent://x#Intent;end',
      ]) {
        expect(PaymentUrlPolicy.shouldOpenExternally(url), isFalse,
            reason: url);
      }
    });
  });
}
