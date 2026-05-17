import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass container — dipakai untuk sticky CTA bar atau card overlay
/// di atas konten scroll. Auto-adapt warna tint sesuai theme brightness.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? tint;
  final BorderRadius? borderRadius;
  /// Convenience — beberapa screen pakai `radius: <double>`. Diabaikan
  /// kalau borderRadius sudah dikasih.
  final dynamic radius;
  final BoxBorder? border;
  final EdgeInsets padding;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 18,
    this.tint,
    this.borderRadius,
    this.radius,
    this.border,
    this.padding = EdgeInsets.zero,
  });

  BorderRadius _effectiveRadius() {
    if (borderRadius != null) return borderRadius!;
    if (radius is BorderRadius) return radius as BorderRadius;
    if (radius is num) return BorderRadius.circular((radius as num).toDouble());
    return BorderRadius.zero;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = tint ??
        (isDark
            ? Colors.black.withOpacity(0.55)
            : Colors.white.withOpacity(0.72));
    final r = _effectiveRadius();

    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            border: border,
            borderRadius: r,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
