import 'package:flutter/material.dart';

/// Visual drag handle pill untuk bottom sheet — match style yang
/// otomatis di-render oleh `showModalBottomSheet(showDragHandle: true)`
/// dari Material 3 theme. Pakai widget ini di dalam custom sheet (mis.
/// `DraggableScrollableSheet`, atau sheet root manual) supaya visual
/// konsisten dengan modal sheet lain di app.
///
/// Color & size sinkron dengan `bottomSheetTheme.dragHandleColor` /
/// `dragHandleSize` di `app_theme.dart`:
/// - Light: grey-300 (#D1D5DB), 40×4
/// - Dark: white 30% opacity, 40×4
///
/// Padding default top/bottom 10dp supaya handle nempel di tepi atas
/// sheet dengan breathing room — match spacing Material 3 spec.
class SheetDragHandle extends StatelessWidget {
  /// Override warna handle. Null = pakai theme bottomSheetTheme.
  final Color? color;

  /// Override ukuran handle. Null = pakai theme (40×4).
  final Size? size;

  /// Padding vertical di sekitar handle. Default 10dp top + bottom.
  final EdgeInsetsGeometry padding;

  const SheetDragHandle({
    super.key,
    this.color,
    this.size,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).bottomSheetTheme;
    final effectiveColor =
        color ?? theme.dragHandleColor ?? const Color(0xFFD1D5DB);
    final effectiveSize = size ?? theme.dragHandleSize ?? const Size(40, 4);
    return Center(
      child: Padding(
        padding: padding,
        child: Container(
          width: effectiveSize.width,
          height: effectiveSize.height,
          decoration: BoxDecoration(
            color: effectiveColor,
            borderRadius: BorderRadius.circular(effectiveSize.height / 2),
          ),
        ),
      ),
    );
  }
}
