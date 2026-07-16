import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_header_motion.dart';

const _productionMetrics = PublicProfileHeaderMetrics(
  topPadding: 59,
  toolbarHeight: 56,
  identityHeight: 271,
  tabHeight: 52,
);
final _collapseDistance = _productionMetrics.scrollSpaceHeight;

void main() {
  group('PublicProfileHeaderMotion', () {
    PublicProfileHeaderMotion resolve(double percentage) =>
        PublicProfileHeaderMotion.resolve(
          scrollOffset: _collapseDistance * percentage / 100,
          collapseDistance: _collapseDistance,
          reducedMotion: false,
        );

    test('expanded and collapsed endpoints match final choreography', () {
      final expanded = resolve(0);
      final collapsed = resolve(100);

      expect(expanded.progress, 0);
      expect(expanded.tabTravel, 0);
      expect(expanded.labelOpacity, 0);
      expect(expanded.pillOpacity, 0);
      expect(expanded.underlineOpacity, 1);
      expect(expanded.glassOpacity, 0);
      expect(expanded.compactIdentityOpacity, 0);
      expect(expanded.controlSurfaceOpacity, 0);
      expect(expanded.blurSigma, 0);

      expect(collapsed.progress, 1);
      expect(collapsed.tabTravel, 1);
      expect(collapsed.labelOpacity, 1);
      expect(collapsed.pillOpacity, 1);
      expect(collapsed.underlineOpacity, 0);
      expect(collapsed.glassOpacity, 1);
      expect(collapsed.compactIdentityOpacity, 1);
      expect(collapsed.controlSurfaceOpacity, 1);
      expect(collapsed.blurSigma, 12);
    });

    test('0 25 50 75 and 100 percent use exact staged intervals', () {
      final zero = resolve(0);
      final twentyFive = resolve(25);
      final fifty = resolve(50);
      final seventyFive = resolve(75);
      final hundred = resolve(100);

      expect(zero.progress, 0);
      expect(twentyFive.progress, 0.15625);
      expect(fifty.progress, 0.5);
      expect(seventyFive.progress, 0.84375);
      expect(hundred.progress, 1);

      expect(twentyFive.tabTravel, 0);
      expect(twentyFive.labelOpacity, 0);
      expect(twentyFive.pillOpacity, 0);
      expect(twentyFive.underlineOpacity, 1);
      expect(twentyFive.glassOpacity, 0);
      expect(twentyFive.compactIdentityOpacity, 0);
      expect(twentyFive.controlSurfaceOpacity, 0);
      expect(twentyFive.blurSigma, 0);

      expect(fifty.tabTravel, closeTo(0.5172413793, 0.0000000001));
      expect(fifty.labelOpacity, closeTo(0.1515151515, 0.0000000001));
      expect(fifty.pillOpacity, closeTo(0.3, 0.0000000001));
      expect(fifty.underlineOpacity, closeTo(0.0625, 0.0000000001));
      expect(fifty.glassOpacity, 0);
      expect(fifty.compactIdentityOpacity, 0);
      expect(fifty.controlSurfaceOpacity, 0);
      expect(fifty.blurSigma, 0);

      expect(seventyFive.tabTravel, 1);
      expect(seventyFive.labelOpacity, 1);
      expect(seventyFive.pillOpacity, 1);
      expect(seventyFive.underlineOpacity, 0);
      expect(
        seventyFive.glassOpacity,
        closeTo(0.9046052632, 0.0000000001),
      );
      expect(
        seventyFive.compactIdentityOpacity,
        closeTo(0.5625, 0.0000000001),
      );
      expect(
        seventyFive.controlSurfaceOpacity,
        closeTo(0.9046052632, 0.0000000001),
      );
      expect(seventyFive.blurSigma, closeTo(10.8552631579, 0.0000000001));
    });

    test('reverse scroll resolves byte-for-byte equal values', () {
      final forward = PublicProfileHeaderMotion.resolve(
        scrollOffset: _collapseDistance * .5,
        collapseDistance: _collapseDistance,
        reducedMotion: false,
      );
      PublicProfileHeaderMotion.resolve(
        scrollOffset: _collapseDistance,
        collapseDistance: _collapseDistance,
        reducedMotion: false,
      );
      final reverse = PublicProfileHeaderMotion.resolve(
        scrollOffset: _collapseDistance * .5,
        collapseDistance: _collapseDistance,
        reducedMotion: false,
      );

      expect(reverse, forward);
      expect(reverse.hashCode, forward.hashCode);
    });

    test('all staged fields remain monotonic across the collapse', () {
      final values = <double>[0, 25, 50, 75, 100].map(resolve).toList();

      for (var index = 1; index < values.length; index++) {
        final previous = values[index - 1];
        final current = values[index];
        expect(current.progress, greaterThanOrEqualTo(previous.progress));
        expect(current.tabTravel, greaterThanOrEqualTo(previous.tabTravel));
        expect(
          current.labelOpacity,
          greaterThanOrEqualTo(previous.labelOpacity),
        );
        expect(current.pillOpacity, greaterThanOrEqualTo(previous.pillOpacity));
        expect(
          current.underlineOpacity,
          lessThanOrEqualTo(previous.underlineOpacity),
        );
        expect(
          current.glassOpacity,
          greaterThanOrEqualTo(previous.glassOpacity),
        );
        expect(
          current.compactIdentityOpacity,
          greaterThanOrEqualTo(previous.compactIdentityOpacity),
        );
        expect(
          current.controlSurfaceOpacity,
          greaterThanOrEqualTo(previous.controlSurfaceOpacity),
        );
        expect(current.blurSigma, greaterThanOrEqualTo(previous.blurSigma));
      }
    });

    test('clamps offsets outside the collapse distance', () {
      expect(
        PublicProfileHeaderMotion.resolve(
          scrollOffset: -24,
          collapseDistance: _collapseDistance,
          reducedMotion: false,
        ),
        resolve(0),
      );
      expect(
        PublicProfileHeaderMotion.resolve(
          scrollOffset: _collapseDistance + 24,
          collapseDistance: _collapseDistance,
          reducedMotion: false,
        ),
        resolve(100),
      );
      expect(
        PublicProfileHeaderMotion.resolve(
          scrollOffset: 1,
          collapseDistance: 0,
          reducedMotion: false,
        ),
        resolve(100),
      );
      expect(
        PublicProfileHeaderMotion.resolve(
          scrollOffset: 0,
          collapseDistance: 0,
          reducedMotion: false,
        ),
        resolve(0),
      );
    });

    test('reduced motion uses linear progress and disables animated blur', () {
      final motion = PublicProfileHeaderMotion.resolve(
        scrollOffset: _collapseDistance * .25,
        collapseDistance: _collapseDistance,
        reducedMotion: true,
      );

      expect(motion.progress, 0.25);
      expect(motion.tabTravel, closeTo(0.0862068966, 0.0000000001));
      expect(motion.labelOpacity, 0);
      expect(motion.pillOpacity, 0);
      expect(motion.underlineOpacity, 0.84375);
      expect(motion.glassOpacity, 0);
      expect(motion.compactIdentityOpacity, 0);
      expect(motion.controlSurfaceOpacity, 0);
      expect(motion.blurSigma, 0);
    });
  });
}
