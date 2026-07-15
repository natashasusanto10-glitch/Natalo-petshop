import 'dart:ui' show lerpDouble;

/// Immutable geometry for the public-profile tab merge at one scroll offset.
///
/// The model is intentionally stateless: reverse scrolling resolves the same
/// value and reduced-motion users never receive spring or overshoot motion.
class PublicProfileHeaderMotion {
  const PublicProfileHeaderMotion._({
    required this.progress,
    required this.widthFactor,
    required this.horizontalAlignment,
    required this.radius,
    required this.gap,
    required this.labelOpacity,
  });

  static const double expandedWidthFactor = 1;
  static const double collapsedWidthFactor = 0.62;
  static const double expandedHorizontalAlignment = 1;
  static const double collapsedHorizontalAlignment = 0;
  static const double expandedRadius = 0;
  static const double collapsedRadius = 24;
  static const double expandedGap = 24;
  static const double collapsedGap = 6;
  static const double expandedLabelOpacity = 1;
  static const double collapsedLabelOpacity = 0;

  /// Smoothstep progress in the inclusive range 0..1.
  final double progress;

  /// Fraction of the available width occupied by the tab group.
  final double widthFactor;

  /// Alignment moving from the right edge (1) toward the left (0).
  final double horizontalAlignment;

  /// Corner radius of the merging segmented tab container.
  final double radius;

  /// Horizontal gap between tabs.
  final double gap;

  /// Opacity for labels that disappear as tabs become compact.
  final double labelOpacity;

  static PublicProfileHeaderMotion resolve(
    double shrinkOffset,
    double collapseRange,
  ) {
    final normalized = collapseRange > 0
        ? (shrinkOffset / collapseRange).clamp(0.0, 1.0).toDouble()
        : (shrinkOffset <= 0 ? 0.0 : 1.0);
    final smoothProgress = normalized * normalized * (3 - 2 * normalized);

    return PublicProfileHeaderMotion._(
      progress: smoothProgress,
      widthFactor: _lerp(
        expandedWidthFactor,
        collapsedWidthFactor,
        smoothProgress,
      ),
      horizontalAlignment: _lerp(
        expandedHorizontalAlignment,
        collapsedHorizontalAlignment,
        smoothProgress,
      ),
      radius: _lerp(expandedRadius, collapsedRadius, smoothProgress),
      gap: _lerp(expandedGap, collapsedGap, smoothProgress),
      labelOpacity: _lerp(
        expandedLabelOpacity,
        collapsedLabelOpacity,
        smoothProgress,
      ),
    );
  }

  static double _lerp(double begin, double end, double progress) =>
      lerpDouble(begin, end, progress)!;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileHeaderMotion &&
          progress == other.progress &&
          widthFactor == other.widthFactor &&
          horizontalAlignment == other.horizontalAlignment &&
          radius == other.radius &&
          gap == other.gap &&
          labelOpacity == other.labelOpacity;

  @override
  int get hashCode => Object.hash(
        progress,
        widthFactor,
        horizontalAlignment,
        radius,
        gap,
        labelOpacity,
      );
}
