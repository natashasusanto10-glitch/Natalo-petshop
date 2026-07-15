import 'package:flutter/rendering.dart';

const int profileGridCrossAxisCount = 3;
const double profileGridMainAxisSpacing = 1;
const double profileGridCrossAxisSpacing = 1;
const double profileGridChildAspectRatio = 0.8;

SliverGridDelegateWithFixedCrossAxisCount profileGridDelegate() {
  return const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: profileGridCrossAxisCount,
    mainAxisSpacing: profileGridMainAxisSpacing,
    crossAxisSpacing: profileGridCrossAxisSpacing,
    childAspectRatio: profileGridChildAspectRatio,
  );
}
