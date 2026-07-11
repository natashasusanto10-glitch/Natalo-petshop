import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/feed_post/feed_video_edit_screen.dart';

void main() {
  group('isFullRangeSelection', () {
    test('12.47s clip fully selected → TRUE (klip pendek pecahan, tak salah-trim)', () {
      final result = isFullRangeSelection(
        startSec: 0.0,
        endSec: 12.47,
        originalDuration: const Duration(milliseconds: 12470),
      );
      expect(result, isTrue);
    });

    test('60.5s clip, default selection dicap ke 60.0 → FALSE (wajib trim)', () {
      final result = isFullRangeSelection(
        startSec: 0.0,
        endSec: 60.0,
        originalDuration: const Duration(milliseconds: 60500),
      );
      expect(result, isFalse);
    });

    test('60.0s clip fully selected → TRUE', () {
      final result = isFullRangeSelection(
        startSec: 0.0,
        endSec: 60.0,
        originalDuration: const Duration(seconds: 60),
      );
      expect(result, isTrue);
    });

    test('44s clip, user trimmed ke (5.0..30.0) → FALSE', () {
      final result = isFullRangeSelection(
        startSec: 5.0,
        endSec: 30.0,
        originalDuration: const Duration(seconds: 44),
      );
      expect(result, isFalse);
    });

    test('30s clip fully selected → TRUE', () {
      final result = isFullRangeSelection(
        startSec: 0.0,
        endSec: 30.0,
        originalDuration: const Duration(seconds: 30),
      );
      expect(result, isTrue);
    });
  });
}
