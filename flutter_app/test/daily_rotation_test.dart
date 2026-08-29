import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/daily_rotation.dart';

List<String> _items(int n) => List.generate(n, (i) => 'p$i');

List<String> _pick(int seed, {int pinned = 0}) => dailyRotatingPick(
      _items(18),
      seed: seed,
      pinned: pinned,
      count: 10,
      idOf: (s) => s,
    );

void main() {
  test('REGRESI seed |1: tanggal genap TIDAK boleh kembar dgn ganjil sesudahnya',
      () {
    // Bug asli: `seed | 1` memaksa bit terakhir jadi 1, jadi 20260828
    // menghasilkan state yang sama dengan 20260829 — rekomendasi terlihat
    // "2-3 hari begitu-begitu saja" (laporan user, terverifikasi simulasi).
    expect(_pick(20260828), isNot(equals(_pick(20260829))));
    expect(_pick(20260826), isNot(equals(_pick(20260827))));
    expect(_pick(20260830), isNot(equals(_pick(20260831))));
  });

  test('sebulan penuh: setiap hari beda dari kemarin', () {
    var kembar = 0;
    List<String>? prev;
    for (var d = 1; d <= 30; d++) {
      final today = _pick(20260900 + d);
      if (prev != null && today.toString() == prev.toString()) kembar++;
      prev = today;
    }
    // Tabrakan kebetulan sesekali bisa terjadi pada RNG mana pun, tapi pola
    // bug lama = SETIAP pasangan genap-ganjil kembar (15 dari 30).
    expect(kembar, lessThanOrEqualTo(1),
        reason: 'pola kembar sistematis = bug seed kembali');
  });

  test('deterministik: seed sama -> hasil sama (stabil sepanjang hari)', () {
    expect(_pick(20260829), equals(_pick(20260829)));
  });

  test('pinned teratas selalu tampil; sisanya dari pool', () {
    final r = _pick(20260829, pinned: 3);
    expect(r.length, 10);
    expect(r.sublist(0, 3), equals(['p0', 'p1', 'p2']));
  });

  test('hasil di-sort ulang ikut peringkat — teratas tetap yang terkuat', () {
    final r = _pick(20260829);
    final idx = r.map((s) => int.parse(s.substring(1))).toList();
    expect(idx, equals([...idx]..sort()),
        reason: 'urutan tampil wajib monoton mengikuti skor');
  });

  test('pool <= count: kembalikan apa adanya tanpa crash', () {
    expect(
      dailyRotatingPick(_items(7),
          seed: 20260829, pinned: 4, count: 10, idOf: (s) => s),
      equals(_items(7)),
    );
  });

  test('dailyRotationSeed = YYYYMMDD lokal', () {
    expect(dailyRotationSeed(now: DateTime(2026, 8, 29)), 20260829);
    expect(dailyRotationSeed(now: DateTime(2026, 1, 5)), 20260105);
  });
}
