import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/notifications_screen.dart';

void main() {
  group('extractOrderNumber', () {
    test('ambil ORD- dari path /pesanan/{orderNumber}', () {
      expect(extractOrderNumber('/pesanan/ORD-20260719-abc'), 'ORD-20260719-abc');
    });
    test('abaikan query & suffix review', () {
      expect(extractOrderNumber('/pesanan/ORD-123?review=1'), 'ORD-123');
    });
    test('ambil ORD- dari query orderNumber= (confirm-reminder/cancel)', () {
      expect(
        extractOrderNumber('/member/order-detail?orderNumber=ORD-9'),
        'ORD-9',
      );
    });
    test('null saat tak ada ORD-', () {
      expect(extractOrderNumber('/member/orders'), isNull);
      expect(extractOrderNumber(null), isNull);
      expect(extractOrderNumber(''), isNull);
    });
    test('slug produk case-insensitive TIDAK salah-tangkap sebagai pesanan', () {
      // Regresi: "cord-" pernah match case-insensitive "ord-" → misroute.
      expect(extractOrderNumber('/products/bungee-cord-leash'), isNull);
      expect(extractOrderNumber('/produk/record-player-mainan'), isNull);
    });
  });

  group('extractOrderTrackingToken', () {
    test('ambil token dari query', () {
      expect(extractOrderTrackingToken('/pesanan/ORD-1?token=xyz'), 'xyz');
    });
    test('null saat tak ada token', () {
      expect(extractOrderTrackingToken('/pesanan/ORD-1'), isNull);
      expect(extractOrderTrackingToken(null), isNull);
    });
  });
}
