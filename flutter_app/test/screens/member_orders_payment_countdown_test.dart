import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/utils/formatters.dart';
import 'package:natalo_petshop_flutter/utils/payment_countdown.dart';

void main() {
  group('paymentCountdownTone', () {
    test('sisa banyak → normal', () {
      expect(
        paymentCountdownTone(const Duration(hours: 5)),
        PaymentCountdownTone.normal,
      );
    });

    test('tepat di ambang 1 jam masih normal, belum mendesak', () {
      expect(
        paymentCountdownTone(kPaymentCountdownUrgentThreshold),
        PaymentCountdownTone.normal,
      );
    });

    test('sedetik di bawah ambang sudah mendesak', () {
      expect(
        paymentCountdownTone(
          kPaymentCountdownUrgentThreshold - const Duration(seconds: 1),
        ),
        PaymentCountdownTone.urgent,
      );
    });

    test('nol dihitung kedaluwarsa — tidak menjanjikan "bayar dalam 00:00"',
        () {
      expect(
        paymentCountdownTone(Duration.zero),
        PaymentCountdownTone.expired,
      );
    });

    test('negatif kedaluwarsa', () {
      expect(
        paymentCountdownTone(const Duration(minutes: -3)),
        PaymentCountdownTone.expired,
      );
    });
  });

  group('formatCountdownCompact', () {
    test('menyembunyikan slot jam saat kurang dari sejam', () {
      expect(
        formatCountdownCompact(const Duration(minutes: 15, seconds: 30)),
        '15:30',
      );
    });

    test('menampilkan jam saat satu jam atau lebih', () {
      expect(
        formatCountdownCompact(
          const Duration(hours: 2, minutes: 5, seconds: 9),
        ),
        '02:05:09',
      );
    });

    test('menit & detik selalu dua digit', () {
      expect(formatCountdownCompact(const Duration(seconds: 7)), '00:07');
    });

    test('tepat satu jam menampilkan slot jam (batas ambang)', () {
      expect(formatCountdownCompact(const Duration(hours: 1)), '01:00:00');
    });

    test('durasi negatif tidak pernah bocor jadi angka minus', () {
      expect(formatCountdownCompact(const Duration(seconds: -5)), '00:00');
    });

    test('lebih dari 24 jam tetap dihitung sebagai jam, bukan hari', () {
      expect(
        formatCountdownCompact(const Duration(hours: 30, minutes: 1)),
        '30:01:00',
      );
    });
  });

  group('paymentDeadline pada OrderSummary', () {
    OrderSummary order({DateTime? deadline, String paymentStatus = 'UNPAID'}) {
      return OrderSummary(
        id: 'o1',
        orderNumber: 'ORD-1',
        status: 'PENDING',
        paymentStatus: paymentStatus,
        createdAt: DateTime(2026, 7, 20),
        total: 100000,
        paymentDeadline: deadline,
        items: const [],
      );
    }

    test('deadline null untuk pesanan tanpa batas bayar', () {
      expect(order().paymentDeadline, isNull);
    });

    test('deadline terbaca apa adanya saat diisi', () {
      final due = DateTime(2026, 7, 20, 18, 30);
      expect(order(deadline: due).paymentDeadline, due);
    });
  });
}
