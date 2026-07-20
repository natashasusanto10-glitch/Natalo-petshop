import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/photo_crop/photo_crop_preview.dart';

void main() {
  group('cropMaxOffsetPx', () {
    test('zero when image exactly covers frame at scale 1', () {
      final maxOff = cropMaxOffsetPx(
        const Size(100, 100),
        const Size(100, 100),
        1,
      );
      expect(maxOff, Offset.zero);
    });

    test('grows with scale — half the overflow per axis', () {
      final maxOff = cropMaxOffsetPx(
        const Size(100, 100),
        const Size(100, 100),
        2,
      );
      // (100*2 - 100)/2 = 50 on each axis.
      expect(maxOff.dx, 50);
      expect(maxOff.dy, 50);
    });

    test('per-axis: wider base only pans horizontally at scale 1', () {
      final maxOff = cropMaxOffsetPx(
        const Size(100, 100),
        const Size(160, 100),
        1,
      );
      expect(maxOff.dx, 30); // (160-100)/2
      expect(maxOff.dy, 0);
    });
  });

  group('rubberBand', () {
    test('zero overshoot → zero resistance', () {
      expect(rubberBand(0, 300), 0);
    });

    test('monotonic but sub-linear (compresses far pulls)', () {
      final near = rubberBand(20, 300);
      final far = rubberBand(200, 300);
      expect(near, greaterThan(0));
      expect(far, greaterThan(near));
      // Damped: displayed distance stays well under the raw overshoot.
      expect(far, lessThan(200));
    });
  });

  group('applyRubberClamp', () {
    const frame = Size(300, 300);
    const maxOff = Offset(50, 50);

    test('within bounds passes through unchanged', () {
      const raw = Offset(20, -30);
      expect(applyRubberClamp(raw, maxOff, frame), raw);
    });

    test('beyond bound is damped past the limit, never hard-stopped', () {
      final out = applyRubberClamp(const Offset(150, 0), maxOff, frame);
      expect(out.dx, greaterThan(50)); // allowed past the bound...
      expect(out.dx, lessThan(150)); // ...but compressed.
    });
  });

  group('zoomAboutPoint', () {
    test('point under the focal stays fixed across a scale change', () {
      const offset = Offset(10, 5);
      const focal = Offset(40, 20);
      const ratio = 2.0;
      final newOffset = zoomAboutPoint(offset, focal, ratio);
      // The image content under `focal` must map to the same place before
      // and after: (focal - offset)/1 == (focal - newOffset)/ratio.
      final beforeContent = focal - offset; // scaled by old scale (=1 rel)
      final afterContent = (focal - newOffset) / ratio;
      expect(afterContent.dx, closeTo(beforeContent.dx, 1e-9));
      expect(afterContent.dy, closeTo(beforeContent.dy, 1e-9));
    });

    test('ratio 1 is a no-op', () {
      const offset = Offset(7, -3);
      expect(zoomAboutPoint(offset, const Offset(50, 50), 1), offset);
    });
  });
}
