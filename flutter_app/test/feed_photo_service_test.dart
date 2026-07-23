import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/feed_photo_service.dart';

/// Regression test untuk final review Spec B — Fix 4 (EXIF orientation
/// mismatch antara composer aspect-ratio decode dan photo dimension read).
///
/// `orientedImageSize` adalah pure function yang diekstrak dari
/// `_readImageSize` (feed_photo_service.dart) supaya bisa di-unit-test
/// exhaustive untuk semua 8 nilai EXIF orientation tanpa perlu fixture JPEG
/// ber-EXIF asli. Lihat dokumentasi function tsb untuk konteks penuh bug.
void main() {
  group('orientedImageSize', () {
    test('orientation null (tidak ada EXIF) -> dimensi mentah, tidak swap',
        () {
      final result = orientedImageSize(4032, 3024, null);
      expect(result.width, 4032);
      expect(result.height, 3024);
    });

    test('orientation 1 (normal, top-left) -> tidak swap', () {
      final result = orientedImageSize(4032, 3024, 1);
      expect(result.width, 4032);
      expect(result.height, 3024);
    });

    test('orientation 2 (mirror horizontal) -> tidak swap', () {
      final result = orientedImageSize(4032, 3024, 2);
      expect(result.width, 4032);
      expect(result.height, 3024);
    });

    test('orientation 3 (rotate 180) -> tidak swap', () {
      final result = orientedImageSize(4032, 3024, 3);
      expect(result.width, 4032);
      expect(result.height, 3024);
    });

    test('orientation 4 (mirror vertical / 180+flip) -> tidak swap', () {
      final result = orientedImageSize(4032, 3024, 4);
      expect(result.width, 4032);
      expect(result.height, 3024);
    });

    test(
        'orientation 5 (mirror + rotate 90) -> swap width/height '
        '(raw landscape -> oriented portrait)', () {
      final result = orientedImageSize(4032, 3024, 5);
      expect(result.width, 3024);
      expect(result.height, 4032);
    });

    test(
        'orientation 6 (rotate 90 CW) -> swap width/height '
        '(raw landscape -> oriented portrait)', () {
      final result = orientedImageSize(4032, 3024, 6);
      expect(result.width, 3024);
      expect(result.height, 4032);
    });

    test(
        'orientation 7 (mirror + rotate 270) -> swap width/height '
        '(raw landscape -> oriented portrait)', () {
      final result = orientedImageSize(4032, 3024, 7);
      expect(result.width, 3024);
      expect(result.height, 4032);
    });

    test(
        'orientation 8 (rotate 270 / -90) -> swap width/height '
        '(raw landscape -> oriented portrait)', () {
      final result = orientedImageSize(4032, 3024, 8);
      expect(result.width, 3024);
      expect(result.height, 4032);
    });

    test('orientation tidak dikenal (di luar 1-8) -> fallback tidak swap',
        () {
      final result = orientedImageSize(4032, 3024, 0);
      expect(result.width, 4032);
      expect(result.height, 3024);
    });

    test('input sudah portrait (raw height > width) tetap konsisten', () {
      // Foto yang di-encode raw sudah portrait (mis. tanpa rotasi kamera) +
      // orientation 6 tetap harus swap sesuai definisi EXIF, sekalipun hasil
      // akhirnya jadi landscape — orientedImageSize tidak menebak "masuk
      // akal secara visual", murni menerapkan aturan swap 5/6/7/8.
      final result = orientedImageSize(3024, 4032, 6);
      expect(result.width, 4032);
      expect(result.height, 3024);
    });
  });
}
