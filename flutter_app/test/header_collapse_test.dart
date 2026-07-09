import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/header_collapse.dart';

// Histeresis collapse header beranda: collapse >72, expand <28. Zona
// 28-72 mempertahankan state — inilah yang mencegah flicker saat scroll
// bolak-balik tipis di sekitar ambang (QA checklist spec #1).
void main() {
  group('headerCollapsedFor (histeresis)', () {
    test('expanded + scroll melewati 72 → collapse', () {
      expect(
        headerCollapsedFor(pixels: 73, currentlyCollapsed: false),
        isTrue,
      );
    });

    test('expanded + scroll tepat di 72 → tetap expanded (ambang eksklusif)',
        () {
      expect(
        headerCollapsedFor(pixels: 72, currentlyCollapsed: false),
        isFalse,
      );
    });

    test('collapsed + scroll turun di bawah 28 → expand', () {
      expect(
        headerCollapsedFor(pixels: 27, currentlyCollapsed: true),
        isFalse,
      );
    });

    test('zona histeresis 28-72 mempertahankan state (anti-flicker)', () {
      for (final px in [28.0, 40.0, 55.0, 72.0]) {
        expect(
          headerCollapsedFor(pixels: px, currentlyCollapsed: false),
          isFalse,
          reason: 'expanded harus bertahan di $px',
        );
        expect(
          headerCollapsedFor(pixels: px, currentlyCollapsed: true),
          isTrue,
          reason: 'collapsed harus bertahan di $px',
        );
      }
    });

    test('bounce iOS (pixels negatif) tidak memicu collapse', () {
      expect(
        headerCollapsedFor(pixels: -120, currentlyCollapsed: false),
        isFalse,
      );
    });

    test('bounce iOS saat collapsed → expand (di bawah ambang expand)', () {
      // Kasus teoretis (fling ekstrem): pixels negatif < 28 → expand benar.
      expect(
        headerCollapsedFor(pixels: -10, currentlyCollapsed: true),
        isFalse,
      );
    });

    test('scroll pelan naik-turun lintas kedua ambang → tepat 2 transisi',
        () {
      // Simulasi jari: 0 → 100 (1 transisi collapse), balik 100 → 0
      // (1 transisi expand). Bolak-balik DI DALAM zona tidak menambah.
      final path = <double>[
        0, 20, 45, 60, 73, 90, // turun: collapse di 73
        66, 50, 35, 50, 66, // bolak-balik dalam zona: tidak ada transisi
        30, 27, 5, 0, // naik: expand di 27
      ];
      var collapsed = false;
      var transitions = 0;
      for (final px in path) {
        final next =
            headerCollapsedFor(pixels: px, currentlyCollapsed: collapsed);
        if (next != collapsed) transitions++;
        collapsed = next;
      }
      expect(transitions, 2);
      expect(collapsed, isFalse);
    });
  });
}
