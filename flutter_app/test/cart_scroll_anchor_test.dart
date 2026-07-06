import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/scroll_anchor.dart';

// Anti-jump keranjang: saat produk baru masuk (mis. dari grid rekomendasi),
// kartu item baru nyelip DI ATAS titik pandang user → ListView biasa tidak
// nge-anchor posisi scroll → konten yang lagi dilihat "loncat ke bawah".
// anchoredOffsetAfterInsert menghitung offset target yang mempertahankan
// JARAK-DARI-DASAR konstan, sehingga konten bawah (rekomendasi) tetap di
// posisi layar yang sama. Card-height-agnostic: cukup dari delta maxExtent.
void main() {
  group('anchoredOffsetAfterInsert', () {
    test('user di dasar list: offset digeser penuh mengikuti konten baru', () {
      // Sebelum: maxExtent 400, user tepat di dasar (pixels 400).
      // Item baru setinggi 120 nyelip di atas → maxExtent jadi 520.
      // fromBottom lama = 0 → target = 520 (tetap menempel dasar).
      final target = anchoredOffsetAfterInsert(
        oldMaxExtent: 400,
        oldPixels: 400,
        newMaxExtent: 520,
      );
      expect(target, 520);
    });

    test('user di tengah: pertahankan jarak dari dasar (rekomendasi diam)', () {
      // fromBottom lama = 400 - 250 = 150. maxExtent baru 520.
      // target = 520 - 150 = 370 → naik 120 (persis tinggi kartu baru).
      final target = anchoredOffsetAfterInsert(
        oldMaxExtent: 400,
        oldPixels: 250,
        newMaxExtent: 520,
      );
      expect(target, 370);
    });

    test('user di puncak (pixels 0): kembalikan null — biarkan natural', () {
      final target = anchoredOffsetAfterInsert(
        oldMaxExtent: 400,
        oldPixels: 0,
        newMaxExtent: 520,
      );
      expect(target, isNull);
    });

    test('target tidak pernah negatif (ter-clamp ke 0)', () {
      // Guard defensif: kombinasi ekstrem tidak boleh hasilkan offset invalid.
      final target = anchoredOffsetAfterInsert(
        oldMaxExtent: 400,
        oldPixels: 100,
        newMaxExtent: 200,
      );
      expect(target, 0);
    });

    test('target tidak pernah melebihi newMaxExtent', () {
      final target = anchoredOffsetAfterInsert(
        oldMaxExtent: 1000,
        oldPixels: 1000,
        newMaxExtent: 300,
      );
      expect(target, 300);
    });
  });
}
