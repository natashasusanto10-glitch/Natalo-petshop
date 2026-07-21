import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/feed_media_picker_screen.dart';

/// Invariant frame preview picker (ala IG fixed-frame): rasio frame KONSTAN
/// 4:5 apa pun status toggle cover/contain. Regresi yang dijaga: dulu frame
/// di-resize ke rasio natural foto saat fitOriginal=true → seluruh layout
/// (termasuk grid galeri) melompat.
void main() {
  group('resolvePreviewAspect (fixed-frame)', () {
    test('rasio identik untuk fitOriginal false vs true', () {
      final cover =
          FeedMediaPickerScreen.resolvePreviewAspect(fitOriginal: false);
      final contain =
          FeedMediaPickerScreen.resolvePreviewAspect(fitOriginal: true);
      expect(cover, contain,
          reason: 'toggle tidak boleh mengubah ukuran/rasio frame');
    });

    test('rasio selalu 4:5', () {
      expect(
        FeedMediaPickerScreen.resolvePreviewAspect(fitOriginal: false),
        4 / 5,
      );
      expect(
        FeedMediaPickerScreen.resolvePreviewAspect(fitOriginal: true),
        4 / 5,
      );
    });
  });

  testWidgets(
      'AspectRatio 4:5 full-width → tinggi = lebar × 5/4, tak berubah antar '
      'toggle', (tester) async {
    // Meniru geometri _buildPreview: AspectRatio full-width dengan rasio
    // dari resolvePreviewAspect. Tinggi harus sama untuk kedua nilai toggle.
    Future<Size> frameSizeFor(bool fitOriginal) async {
      final aspect =
          FeedMediaPickerScreen.resolvePreviewAspect(fitOriginal: fitOriginal);
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 400,
            child: AspectRatio(
              aspectRatio: aspect,
              child: const SizedBox.expand(
                key: ValueKey('frame'),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const ValueKey('frame')));
    }

    final cover = await frameSizeFor(false);
    final contain = await frameSizeFor(true);
    expect(cover, contain);
    expect(cover.width, 400);
    expect(cover.height, closeTo(400 * 5 / 4, 0.01)); // 4:5 → 500
  });
}
