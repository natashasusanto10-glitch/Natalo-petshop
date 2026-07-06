// Unit test untuk kurva visual paw (scale/opacity vs progress tarikan).
//
// Bug report: paw refresh indicator terasa "baru muncul setelah tarikan
// berhenti" di Beranda (dan halaman lain yang tidak pakai translateChild).
// Root cause terkonfirmasi: paw SUDAH progresif dari awal tarikan, tapi
// floor opacity/scale terlalu rendah (nyaris tidak kelihatan) sampai
// tarikan hampir penuh — jadi user tidak sadar ada feedback sampai
// indicator sudah dekat/di titik trigger.
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/natalo_paw_refresh_indicator.dart';

void main() {
  group('computePawVisual', () {
    test('di awal tarikan (progress 0), paw harus sudah jelas kelihatan', () {
      final visual = computePawVisual(
        progress: 0.0,
        isRefreshing: false,
        fadeValue: 1.0,
      );
      expect(visual.opacity, greaterThanOrEqualTo(0.45));
      expect(visual.scale, greaterThanOrEqualTo(0.55));
    });

    test('paw mencapai tampilan penuh sebelum tarikan 100% (di 65%)', () {
      final visual = computePawVisual(
        progress: 0.65,
        isRefreshing: false,
        fadeValue: 1.0,
      );
      expect(visual.opacity, 1.0);
      expect(visual.scale, 1.0);
    });

    test('di tarikan penuh (progress 1.0), paw full opacity + scale', () {
      final visual = computePawVisual(
        progress: 1.0,
        isRefreshing: false,
        fadeValue: 1.0,
      );
      expect(visual.opacity, 1.0);
      expect(visual.scale, 1.0);
    });

    test('saat refreshing, scale/opacity ikut fadeCtrl — abaikan progress', () {
      final visual = computePawVisual(
        progress: 0.0,
        isRefreshing: true,
        fadeValue: 0.8,
      );
      expect(visual.scale, 1.0);
      expect(visual.opacity, 0.8);
    });
  });
}
