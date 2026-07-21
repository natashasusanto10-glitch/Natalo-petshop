import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Brings [tileContext]'s render box fully into view within its NEAREST
/// enclosing [Scrollable] ONLY — never ancestor scrollables — and ONLY when
/// the tile is not already fully visible inside that scrollable's viewport.
///
/// A tile already fully visible is left exactly where it is (no reposition,
/// no alignment normalization). When scrolling is needed, the tile is moved
/// the MINIMUM distance to be fully visible, respecting [topPadding]
/// (pinned chrome below which the tile must land) and [bottomPadding]
/// (bottom nav / safe area above which it must land), clamped to the
/// scrollable's extents.
///
/// This intentionally avoids `Scrollable.ensureVisible`, which (a) always
/// repositions to satisfy a fixed alignment even when the tile is already
/// fully visible, and (b) walks every ancestor scrollable — inside a
/// `NestedScrollView` that means the outer header scrollable also moves,
/// producing a visible jump of pinned chrome on every close.
Future<void> ensureProfileTileVisible(
  BuildContext tileContext, {
  double topPadding = 0,
  double bottomPadding = 0,
}) async {
  final scrollableState = Scrollable.maybeOf(tileContext);
  if (scrollableState == null) return;
  final position = scrollableState.position;

  final renderObject = tileContext.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return;

  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (viewport == null) return;

  final viewportBox = viewport as RenderObject;
  if (viewportBox is! RenderBox) return;
  final viewportHeight = viewportBox.size.height;

  // Tile's current top/bottom in viewport-local coordinates.
  final tileTopLeft = renderObject.localToGlobal(
    Offset.zero,
    ancestor: viewportBox,
  );
  final tileTop = tileTopLeft.dy;
  final tileBottom = tileTop + renderObject.size.height;

  final visibleTop = topPadding;
  final visibleBottom = viewportHeight - bottomPadding;

  final alreadyVisible = tileTop >= visibleTop && tileBottom <= visibleBottom;
  if (alreadyVisible) return;

  double targetOffset;
  if (tileTop < visibleTop) {
    // Tile is above the fold: reveal with its top landing at topPadding.
    final revealOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
    targetOffset = revealOffset - topPadding;
  } else {
    // Tile is below the fold: reveal with its bottom landing at
    // (viewportHeight - bottomPadding).
    final revealOffset = viewport.getOffsetToReveal(renderObject, 1).offset;
    targetOffset = revealOffset + bottomPadding;
  }

  targetOffset = targetOffset.clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );

  if (targetOffset == position.pixels) return;

  position.jumpTo(targetOffset);
}
