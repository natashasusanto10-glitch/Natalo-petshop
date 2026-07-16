import 'dart:ui' show lerpDouble;

/// Immutable public-profile header choreography at one scroll offset.
///
/// Resolution is pure and stateless so reverse scrolling always produces the
/// same value. Reduced motion keeps linear progress and disables animated blur.
class PublicProfileHeaderMotion {
  const PublicProfileHeaderMotion._({
    required this.progress,
    required this.tabTravel,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.underlineOpacity,
    required this.glassOpacity,
    required this.compactIdentityOpacity,
    required this.controlSurfaceOpacity,
    required this.blurSigma,
  });

  final double progress;
  final double tabTravel;
  final double labelOpacity;
  final double pillOpacity;
  final double underlineOpacity;
  final double glassOpacity;
  final double compactIdentityOpacity;
  final double controlSurfaceOpacity;
  final double blurSigma;

  static PublicProfileHeaderMotion resolve({
    required double scrollOffset,
    required double collapseDistance,
    required bool reducedMotion,
  }) {
    final raw = collapseDistance <= 0
        ? (scrollOffset <= 0 ? 0.0 : 1.0)
        : (scrollOffset / collapseDistance).clamp(0.0, 1.0).toDouble();
    final progress = reducedMotion ? raw : raw * raw * (3 - 2 * raw);
    final tabTravel = _interval(progress, 0.20, 0.78);
    final labelOpacity = _interval(progress, 0.45, 0.78);
    final pillOpacity = _interval(progress, 0.38, 0.78);
    final underlineOpacity = 1 - _interval(progress, 0.20, 0.52);
    final glassOpacity = _interval(progress, 0.50, 0.88);
    final compactIdentityOpacity = _interval(progress, 0.72, 0.94);
    final controlSurfaceOpacity = _interval(progress, 0.50, 0.88);

    return PublicProfileHeaderMotion._(
      progress: progress,
      tabTravel: tabTravel,
      labelOpacity: labelOpacity,
      pillOpacity: pillOpacity,
      underlineOpacity: underlineOpacity,
      glassOpacity: glassOpacity,
      compactIdentityOpacity: compactIdentityOpacity,
      controlSurfaceOpacity: controlSurfaceOpacity,
      blurSigma: reducedMotion ? 0 : lerpDouble(0, 12, glassOpacity)!,
    );
  }

  static double _interval(double value, double begin, double end) {
    if (value <= begin) return 0;
    if (value >= end) return 1;
    return ((value - begin) / (end - begin)).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileHeaderMotion &&
          other.progress == progress &&
          other.tabTravel == tabTravel &&
          other.labelOpacity == labelOpacity &&
          other.pillOpacity == pillOpacity &&
          other.underlineOpacity == underlineOpacity &&
          other.glassOpacity == glassOpacity &&
          other.compactIdentityOpacity == compactIdentityOpacity &&
          other.controlSurfaceOpacity == controlSurfaceOpacity &&
          other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(
        progress,
        tabTravel,
        labelOpacity,
        pillOpacity,
        underlineOpacity,
        glassOpacity,
        compactIdentityOpacity,
        controlSurfaceOpacity,
        blurSigma,
      );
}
