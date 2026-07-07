import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/chrome_autohide.dart';

// Keputusan auto-hide chrome keranjang (baris "N terpilih" + voucher bar).
// Drag-driven: hide saat scroll ke bawah di tengah, show saat scroll ke atas.
// No-op di dekat puncak (biar chrome tetap tampil saat lihat cart paling atas)
// & tepat di dasar (hindari clamp menarik konten saat bar collapse).
void main() {
  group('chromeActionForScroll', () {
    test('scroll ke bawah di tengah + chrome tampil → hide', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.hide,
      );
    });

    test('scroll ke atas saat chrome hidden → show', () {
      expect(
        chromeActionForScroll(
          scrollDelta: -20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.show,
      );
    });

    test('scroll ke bawah tapi chrome sudah hidden → none', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.none,
      );
    });

    test('dekat puncak (cart paling atas) → jangan hide', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: -490,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.none,
      );
    });

    test('tepat di dasar → jangan hide (hindari clamp menarik konten)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: 498,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.none,
      );
    });

    test('gerakan mikro (< threshold) → none (tak thrash)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 2,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.none,
      );
      expect(
        chromeActionForScroll(
          scrollDelta: -2,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.none,
      );
    });
  });
}
