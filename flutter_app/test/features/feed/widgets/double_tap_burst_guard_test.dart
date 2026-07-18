// ignore_for_file: depend_on_referenced_packages

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/double_tap_burst_guard.dart';

void main() {
  test('awalnya tidak menekan single-tap', () {
    final guard = DoubleTapBurstGuard();
    expect(guard.shouldSuppressSingleTap, isFalse);
    guard.dispose();
  });

  test('sesudah double-tap, single-tap ditekan dalam jendela', () {
    fakeAsync((async) {
      final guard = DoubleTapBurstGuard(window: const Duration(milliseconds: 500));
      guard.registerDoubleTap();
      expect(guard.shouldSuppressSingleTap, isTrue,
          reason: 'tepat setelah double-tap → tekan single-tap');

      async.elapse(const Duration(milliseconds: 300));
      expect(guard.shouldSuppressSingleTap, isTrue,
          reason: 'masih di dalam jendela 500ms → tetap ditekan');

      async.elapse(const Duration(milliseconds: 250));
      expect(guard.shouldSuppressSingleTap, isFalse,
          reason: 'jendela lewat → single-tap disengaja lolos lagi');
      guard.dispose();
    });
  });

  test('double-tap beruntun me-reset jendela', () {
    fakeAsync((async) {
      final guard = DoubleTapBurstGuard(window: const Duration(milliseconds: 500));
      guard.registerDoubleTap();
      async.elapse(const Duration(milliseconds: 400));
      guard.registerDoubleTap(); // reset jendela
      async.elapse(const Duration(milliseconds: 300));
      expect(guard.shouldSuppressSingleTap, isTrue,
          reason: 'reset → 300ms sejak double-tap terakhir, masih ditekan');
      async.elapse(const Duration(milliseconds: 250));
      expect(guard.shouldSuppressSingleTap, isFalse);
      guard.dispose();
    });
  });

  test('dispose membatalkan timer (tak ada callback tertinggal)', () {
    fakeAsync((async) {
      final guard = DoubleTapBurstGuard(window: const Duration(milliseconds: 500));
      guard.registerDoubleTap();
      guard.dispose();
      async.elapse(const Duration(seconds: 1));
      // Tak ada timer aktif tersisa → fakeAsync tidak komplain pending timer.
      expect(async.pendingTimers, isEmpty);
    });
  });
}
