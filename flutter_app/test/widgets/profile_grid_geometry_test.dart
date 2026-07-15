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
}
