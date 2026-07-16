import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_header_motion.dart';

void main() {
  group('PublicProfileHeaderMotion', () {
    test('resolves exact expanded and collapsed endpoints', () {
      final expanded = PublicProfileHeaderMotion.resolve(0, 100);
      final collapsed = PublicProfileHeaderMotion.resolve(100, 100);

      expect(expanded.progress, 0);
      expect(expanded.widthFactor, 1);
      expect(expanded.horizontalAlignment, 1);
      expect(expanded.radius, 0);
      expect(expanded.gap, 24);
      expect(expanded.labelOpacity, 0);
      expect(expanded.surfaceOpacity, 0);
      expect(expanded.underlineOpacity, 1);

      expect(collapsed.progress, 1);
      expect(collapsed.widthFactor, 0.62);
      expect(collapsed.horizontalAlignment, 0);
      expect(collapsed.radius, 24);
      expect(collapsed.gap, 6);
      expect(collapsed.labelOpacity, 1);
      expect(collapsed.surfaceOpacity, 1);
      expect(collapsed.underlineOpacity, 0);
    });

    test('uses deterministic smoothstep at 30 and 60 percent', () {
      final thirty = PublicProfileHeaderMotion.resolve(30, 100);
      final sixty = PublicProfileHeaderMotion.resolve(60, 100);

      expect(thirty.progress, closeTo(0.216, 0.000001));
      expect(thirty.widthFactor, closeTo(0.91792, 0.000001));
      expect(thirty.horizontalAlignment, closeTo(0.784, 0.000001));
      expect(thirty.radius, closeTo(5.184, 0.000001));
      expect(thirty.gap, closeTo(20.112, 0.000001));
      expect(thirty.labelOpacity, closeTo(0.216, 0.000001));
      expect(thirty.surfaceOpacity, closeTo(0.216, 0.000001));
      expect(thirty.underlineOpacity, closeTo(0.784, 0.000001));

      expect(sixty.progress, closeTo(0.648, 0.000001));
      expect(sixty.widthFactor, closeTo(0.75376, 0.000001));
      expect(sixty.horizontalAlignment, closeTo(0.352, 0.000001));
      expect(sixty.radius, closeTo(15.552, 0.000001));
      expect(sixty.gap, closeTo(12.336, 0.000001));
      expect(sixty.labelOpacity, closeTo(0.648, 0.000001));
      expect(sixty.surfaceOpacity, closeTo(0.648, 0.000001));
      expect(sixty.underlineOpacity, closeTo(0.352, 0.000001));
    });

    test('clamps offsets outside the collapse range', () {
      expect(
        PublicProfileHeaderMotion.resolve(-25, 100),
        PublicProfileHeaderMotion.resolve(0, 100),
      );
      expect(
        PublicProfileHeaderMotion.resolve(125, 100),
        PublicProfileHeaderMotion.resolve(100, 100),
      );
    });

    test('values change monotonically from right to left', () {
      final values = <double>[0, 30, 60, 100]
          .map((offset) => PublicProfileHeaderMotion.resolve(offset, 100))
          .toList();

      for (var index = 1; index < values.length; index++) {
        expect(
            values[index].widthFactor, lessThan(values[index - 1].widthFactor));
        expect(
          values[index].horizontalAlignment,
          lessThan(values[index - 1].horizontalAlignment),
        );
        expect(values[index].radius, greaterThan(values[index - 1].radius));
        expect(values[index].gap, lessThan(values[index - 1].gap));
        expect(values[index].labelOpacity,
            greaterThan(values[index - 1].labelOpacity));
        expect(values[index].surfaceOpacity,
            greaterThan(values[index - 1].surfaceOpacity));
        expect(values[index].underlineOpacity,
            lessThan(values[index - 1].underlineOpacity));
      }
    });

    test('reverse scroll resolves the same immutable value', () {
      final forward = PublicProfileHeaderMotion.resolve(60, 100);
      PublicProfileHeaderMotion.resolve(100, 100);
      final reverse = PublicProfileHeaderMotion.resolve(60, 100);

      expect(reverse, forward);
      expect(reverse.hashCode, forward.hashCode);
    });
  });
}
