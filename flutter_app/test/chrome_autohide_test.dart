import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/chrome_autohide.dart';

// Semantik condense-pill: chrome melipat saat drag ARAH APA PUN di tengah
// list; TIDAK pernah show dari gerakan drag — reveal ditangani idle timer
// (ScrollEnd = jari lepas). Satu-satunya show dari gerakan: mentok puncak.
void main() {
  group('chromeActionForScroll (condense-pill)', () {
    test('drag ke bawah di tengah + chrome tampil → hide', () {
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

    test('drag ke ATAS di tengah + chrome tampil → hide (dua arah)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: -20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.hide,
      );
    });

    test(
        'drag ke atas saat chrome hidden → none (reveal = idle timer, '
        'bukan gerakan)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: -20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.none,
      );
    });

    test('mentok puncak + chrome hidden → show instan', () {
      expect(
        chromeActionForScroll(
          scrollDelta: -20,
          pixels: -490,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.show,
      );
    });

    test('di puncak + chrome sudah tampil → none (tak retrigger)', () {
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

    test('gerakan mikro (|delta| < threshold) → none, dua arah', () {
      for (final delta in [2.0, -2.0]) {
        expect(
          chromeActionForScroll(
            scrollDelta: delta,
            pixels: 100,
            minExtent: -500,
            maxExtent: 500,
            currentlyVisible: true,
          ),
          ChromeAction.none,
        );
      }
    });

    test('drag saat sudah hidden di tengah → none', () {
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
  });
}
