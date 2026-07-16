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

double profileGridExtentForWidth(
  double width, {
  required int itemCount,
}) {
  if (itemCount <= 0) return 0;
  final rows = (itemCount / profileGridCrossAxisCount).ceil();
  const horizontalGaps =
      (profileGridCrossAxisCount - 1) * profileGridCrossAxisSpacing;
  final tileWidth = (width - horizontalGaps) / profileGridCrossAxisCount;
  final tileHeight = tileWidth / profileGridChildAspectRatio;
  return rows * tileHeight + (rows - 1) * profileGridMainAxisSpacing;
}
