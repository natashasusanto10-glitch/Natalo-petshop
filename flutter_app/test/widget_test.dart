import 'package:flutter_test/flutter_test.dart';

import 'package:natalo_petshop_flutter/theme/natalo_colors.dart';
import 'package:natalo_petshop_flutter/utils/formatters.dart';

/// Unit tests untuk pure helpers (formatter, color tokens, dll) yang tidak
/// butuh full app boot.
///
/// **Full app boot test** ada di `integration_test/app_test.dart` — pakai
/// `IntegrationTestWidgetsFlutterBinding` + jalankan di device real karena
/// `main.dart` butuh shared_preferences + native plugins yang tidak available
/// di pure unit test environment.
void main() {
  group('formatRupiah', () {
    test('formats integer dengan dot separator', () {
      expect(formatRupiah(50000), 'Rp 50.000');
      expect(formatRupiah(1500), 'Rp 1.500');
      expect(formatRupiah(1000000), 'Rp 1.000.000');
    });

    test('rounds double values', () {
      expect(formatRupiah(50000.4), 'Rp 50.000');
      expect(formatRupiah(50000.6), 'Rp 50.001');
    });

    test('handles zero + small values', () {
      expect(formatRupiah(0), 'Rp 0');
      expect(formatRupiah(99), 'Rp 99');
      expect(formatRupiah(999), 'Rp 999');
    });
  });

  group('formatDate', () {
    test('formats with Indonesian short month names', () {
      expect(formatDate(DateTime(2026, 5, 14)), '14 Mei 2026');
      expect(formatDate(DateTime(2026, 1, 1)), '1 Jan 2026');
      expect(formatDate(DateTime(2026, 12, 31)), '31 Des 2026');
    });
  });

  group('formatDateTime', () {
    test('includes time with dot separator', () {
      expect(
        formatDateTime(DateTime(2026, 5, 14, 10, 33)),
        '14 Mei 2026 pukul 10.33',
      );
      expect(
        formatDateTime(DateTime(2026, 5, 14, 9, 5)),
        '14 Mei 2026 pukul 09.05',
      );
    });
  });

  group('formatRelativeTime', () {
    test('returns "Baru saja" for recent dates', () {
      expect(formatRelativeTime(DateTime.now()), 'Baru saja');
      expect(
        formatRelativeTime(
          DateTime.now().subtract(const Duration(seconds: 30)),
        ),
        'Baru saja',
      );
    });

    test('returns minutes/hours/days appropriately', () {
      final now = DateTime.now();
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5))),
        '5 menit lalu',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3))),
        '3 jam lalu',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 7))),
        '7 hari lalu',
      );
    });
  });

  group('NataloColors design tokens', () {
    test('primary palette hex values stable', () {
      expect(NataloColors.primary.toARGB32(), 0xFF0B7FEA);
      expect(NataloColors.primaryDark.toARGB32(), 0xFF075CB5);
      expect(NataloColors.primaryLight.toARGB32(), 0xFFEAF5FF);
    });

    test('semantic colors stable', () {
      expect(NataloColors.success.toARGB32(), 0xFF16A34A);
      expect(NataloColors.warning.toARGB32(), 0xFFF59E0B);
      expect(NataloColors.danger.toARGB32(), 0xFFEF4444);
    });
  });
}
