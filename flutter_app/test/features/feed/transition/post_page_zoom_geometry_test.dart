import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_geometry.dart';

void main() {
  const tile = Rect.fromLTWH(30, 100, 120, 120); // 1:1 grid cell
  const slot = Rect.fromLTWH(0, 80, 400, 500); // 4:5 detail slot

  // Helper: the on-screen rect the media content occupies for a frame,
  // computed from contentScale/contentOffset over the intrinsic surface
  // Size(mediaAspect, 1).
  Rect contentRect(PostPageHeroFrame f, double mediaAspect) => Rect.fromLTWH(
    f.contentOffset.dx,
    f.contentOffset.dy,
    mediaAspect * f.contentScale,
    1.0 * f.contentScale,
  );

  bool coversTightly(Rect content, Rect target) =>
      content.left <= target.left + 0.5 &&
      content.top <= target.top + 0.5 &&
      content.right >= target.right - 0.5 &&
      content.bottom >= target.bottom - 0.5 &&
      // exactly one dimension matches (cover touches on the tight axis)
      ((content.width - target.width).abs() < 0.5 ||
          (content.height - target.height).abs() < 0.5);

  group('resolveHeroFrame endpoints', () {
    for (final aspect in <double>[4 / 5, 1.91, 1.0]) {
      test('progress 0 covers the tile (aspect $aspect)', () {
        final f = resolveHeroFrame(
          tileRect: tile,
          slotRect: slot,
          mediaAspect: aspect,
          tileRadius: 4,
          slotRadius: 0,
          progress: 0,
        );
        expect(f.clip.outerRect, tile);
        expect(coversTightly(contentRect(f, aspect), tile), isTrue);
      });
      test('progress 1 fills the slot (aspect $aspect)', () {
        final f = resolveHeroFrame(
          tileRect: tile,
          slotRect: slot,
          mediaAspect: aspect,
          tileRadius: 4,
          slotRadius: 0,
          progress: 1,
        );
        expect(f.clip.outerRect, slot);
        expect(coversTightly(contentRect(f, aspect), slot), isTrue);
      });
    }
  });

  test('contentScale is monotonic and uniform across the flight', () {
    double? prev;
    for (var p = 0.0; p <= 1.0; p += 0.1) {
      final f = resolveHeroFrame(
        tileRect: tile,
        slotRect: slot,
        mediaAspect: 4 / 5,
        tileRadius: 4,
        slotRadius: 0,
        progress: p,
      );
      if (prev != null) expect(f.contentScale, greaterThanOrEqualTo(prev));
      prev = f.contentScale;
    }
  });

  test('resolveChromeOpacity is linear 0..1', () {
    expect(resolveChromeOpacity(0), 0);
    expect(resolveChromeOpacity(1), 1);
    expect(resolveChromeOpacity(0.5), closeTo(0.5, 1e-9));
  });
}
