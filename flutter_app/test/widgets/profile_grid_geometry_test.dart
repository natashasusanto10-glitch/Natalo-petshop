import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/profile_grid_geometry.dart';

void main() {
  test('profile grid uses three portrait columns with one pixel gaps', () {
    expect(profileGridCrossAxisCount, 3);
    expect(profileGridMainAxisSpacing, 1);
    expect(profileGridCrossAxisSpacing, 1);
    expect(profileGridChildAspectRatio, 0.8);

    final delegate = profileGridDelegate();

    expect(delegate, isA<SliverGridDelegateWithFixedCrossAxisCount>());
    expect(delegate.crossAxisCount, profileGridCrossAxisCount);
    expect(delegate.mainAxisSpacing, profileGridMainAxisSpacing);
    expect(delegate.crossAxisSpacing, profileGridCrossAxisSpacing);
    expect(delegate.childAspectRatio, profileGridChildAspectRatio);
  });

  test('six-item loading grid extent includes the exact one-pixel gaps', () {
    const width = 393.0;
    const tileWidth =
        (width - 2 * profileGridCrossAxisSpacing) / profileGridCrossAxisCount;
    const expected =
        tileWidth / profileGridChildAspectRatio * 2 +
        profileGridMainAxisSpacing;

    expect(profileGridExtentForWidth(width, itemCount: 6), expected);
  });

  for (final width in <double>[320, 360, 393, 430]) {
    test('row offsets remain exact at width $width', () {
      final tileWidth =
          (width - 2 * profileGridCrossAxisSpacing) / profileGridCrossAxisCount;
      final rowExtent =
          tileWidth / profileGridChildAspectRatio + profileGridMainAxisSpacing;

      for (var index = 0; index < 15; index++) {
        expect(
          profileGridMainAxisOffsetForIndex(width, index: index),
          closeTo(rowExtent * (index ~/ profileGridCrossAxisCount), .001),
          reason: 'index $index must use the same row geometry as the delegate',
        );
      }
    });
  }
}
