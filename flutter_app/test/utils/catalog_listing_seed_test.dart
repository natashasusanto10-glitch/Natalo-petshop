import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/daily_rotation.dart';

void main() {
  test('format seed katalog = YYYY-MM-DD, sama dengan halaman Produk', () {
    // Server (lib/products.ts) dan halaman Produk memakai format ini.
    // Kalau Beranda mengirim format lain, cursor halaman 2 Jelajahi diurut
    // dengan seed berbeda dari halaman 1 → produk dobel / terlewat.
    final seed = catalogListingSeed(now: DateTime.utc(2026, 9, 3, 5, 0));
    expect(seed, '2026-09-03');
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(seed), isTrue);
  });

  test('pergantian hari mengikuti WIB (UTC+7), bukan UTC', () {
    // 17:30 UTC pada 3 Sep = 00:30 WIB pada 4 Sep. Kalau memakai UTC,
    // pelanggan Indonesia melihat urutan berganti jam 7 pagi, bukan
    // tengah malam.
    expect(
      catalogListingSeed(now: DateTime.utc(2026, 9, 3, 16, 59)),
      '2026-09-03',
    );
    expect(
      catalogListingSeed(now: DateTime.utc(2026, 9, 3, 17, 30)),
      '2026-09-04',
    );
  });

  test('bulan dan tanggal satu digit dipad nol', () {
    expect(
      catalogListingSeed(now: DateTime.utc(2026, 1, 5, 12)),
      '2026-01-05',
    );
  });

  test('dua panggilan di hari WIB yang sama menghasilkan seed identik', () {
    // Stabil dalam satu hari = halaman berikutnya sejalan dengan yang
    // pertama saat user scroll.
    final a = catalogListingSeed(now: DateTime.utc(2026, 9, 3, 1));
    final b = catalogListingSeed(now: DateTime.utc(2026, 9, 3, 16));
    expect(a, b);
  });
}
