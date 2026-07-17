import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_header_motion.dart';

void main() {
  group('PublicProfileHeaderMotion', () {
    PublicProfileHeaderMotion resolve(double t) =>
        PublicProfileHeaderMotion.resolve(t: t, reducedMotion: false);

    test('expanded and collapsed endpoints match final choreography', () {
      final expanded = resolve(0);
      final collapsed = resolve(1);

      expect(expanded.progress, 0);
      expect(expanded.labelOpacity, 0);
      expect(expanded.pillOpacity, 0);
      expect(expanded.underlineOpacity, 1);
      expect(expanded.glassOpacity, 0);
      expect(expanded.compactIdentityOpacity, 0);
      expect(expanded.controlSurfaceOpacity, 0);
      expect(expanded.blurSigma, 0);

      expect(collapsed.progress, 1);
      expect(collapsed.labelOpacity, 1);
      expect(collapsed.pillOpacity, 1);
      expect(collapsed.underlineOpacity, 0);
      expect(collapsed.glassOpacity, 1);
      expect(collapsed.compactIdentityOpacity, 1);
      expect(collapsed.controlSurfaceOpacity, 1);
      expect(collapsed.blurSigma, 12);
    });

    test('0.25 0.5 0.75 and 1 use exact staged intervals', () {
      final quarter = resolve(0.25);
      final half = resolve(0.5);
      final threeQuarter = resolve(0.75);
      final full = resolve(1);

      // t=0.25: label/pill already rising (both start at 0), underline
      // already fading — NEVER a frame where pill is still 0 while
      // something else has moved (nothing moves separately anymore).
      expect(quarter.labelOpacity, closeTo(0.5555555556, 0.0000000001));
      expect(quarter.pillOpacity, closeTo(0.4545454545, 0.0000000001));
      expect(quarter.underlineOpacity, closeTo(0.1666666667, 0.0000000001));
      expect(quarter.glassOpacity, 0);
      expect(quarter.compactIdentityOpacity, 0);
      expect(quarter.controlSurfaceOpacity, 0);
      expect(quarter.blurSigma, 0);

      expect(half.labelOpacity, 1);
      expect(half.pillOpacity, closeTo(0.9090909091, 0.0000000001));
      expect(half.underlineOpacity, 0);
      expect(half.glassOpacity, 0);
      expect(half.compactIdentityOpacity, 0);
      expect(half.controlSurfaceOpacity, 0);
      expect(half.blurSigma, 0);

      expect(threeQuarter.labelOpacity, 1);
      expect(threeQuarter.pillOpacity, 1);
      expect(threeQuarter.underlineOpacity, 0);
      expect(threeQuarter.glassOpacity, closeTo(0.6578947368, 0.0000000001));
      expect(
        threeQuarter.compactIdentityOpacity,
        closeTo(0.1363636364, 0.0000000001),
      );
      expect(
        threeQuarter.controlSurfaceOpacity,
        closeTo(0.6578947368, 0.0000000001),
      );
      expect(threeQuarter.blurSigma, closeTo(7.8947368421, 0.0000000001));

      expect(full.labelOpacity, 1);
      expect(full.pillOpacity, 1);
      expect(full.underlineOpacity, 0);
      expect(full.glassOpacity, 1);
      expect(full.compactIdentityOpacity, 1);
      expect(full.controlSurfaceOpacity, 1);
      expect(full.blurSigma, 12);
    });

    test('equal t values resolve byte-for-byte equal', () {
      final a = resolve(0.5);
      final b = resolve(0.5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('all staged fields remain monotonic across the collapse', () {
      final values = <double>[0, 0.25, 0.5, 0.75, 1].map(resolve).toList();

      for (var index = 1; index < values.length; index++) {
        final previous = values[index - 1];
        final current = values[index];
        expect(current.progress, greaterThanOrEqualTo(previous.progress));
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

    test('clamps t outside 0..1', () {
      expect(resolve(-0.1), resolve(0));
      expect(resolve(1.4), resolve(1));
    });

    test('reduced motion disables animated blur but keeps linear progress',
        () {
      final motion = PublicProfileHeaderMotion.resolve(
        t: 0.25,
        reducedMotion: true,
      );

      expect(motion.progress, 0.25);
      expect(motion.labelOpacity, closeTo(0.5555555556, 0.0000000001));
      expect(motion.pillOpacity, closeTo(0.4545454545, 0.0000000001));
      expect(motion.blurSigma, 0);
    });
  });
}
