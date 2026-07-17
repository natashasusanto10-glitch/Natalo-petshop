import 'dart:ui' show lerpDouble;

/// Immutable public-profile header choreography at one collapse progress `t`.
///
/// `t` comes from [CollapsingHeaderDelegate] (linear 1:1 with the finger,
/// already clamped 0..1) — this class only derives COSMETIC fields (opacity,
/// blur) from it. It never derives POSITION: the tab bar's on-screen position
/// is a natural consequence of the identity content shrinking above it inside
/// the same pinned sliver, not a separately animated value. Mixing position
/// and cosmetic timing into two different curves was the root cause of a
/// bare-icon flash bug (icon moved before its background appeared) — keeping
/// this class cosmetic-only and driven by the SAME `t` as the shrink removes
/// that class of bug entirely.
class PublicProfileHeaderMotion {
  const PublicProfileHeaderMotion._({
    required this.progress,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.underlineOpacity,
    required this.glassOpacity,
    required this.compactIdentityOpacity,
    required this.controlSurfaceOpacity,
    required this.blurSigma,
  });

  final double progress;
  final double labelOpacity;
  final double pillOpacity;
  final double underlineOpacity;
  final double glassOpacity;
  final double compactIdentityOpacity;
  final double controlSurfaceOpacity;
  final double blurSigma;

  static PublicProfileHeaderMotion resolve({
    required double t,
    required bool reducedMotion,
  }) {
    final progress = t.clamp(0.0, 1.0).toDouble();
    // pillOpacity and labelOpacity both start at progress 0 — same instant
    // the identity above them starts shrinking — so there is never a frame
    // where the tab has moved (shrunk into place) without its background.
    // labelOpacity finishes first (text turns to icon-only before the pill
    // background finishes solidifying), matching the pre-existing ordering.
    final labelOpacity = _interval(progress, 0.0, 0.45);
    final pillOpacity = _interval(progress, 0.0, 0.55);
    final underlineOpacity = 1 - _interval(progress, 0.0, 0.30);
    final glassOpacity = _interval(progress, 0.50, 0.88);
    final compactIdentityOpacity = _interval(progress, 0.72, 0.94);
    final controlSurfaceOpacity = _interval(progress, 0.50, 0.88);

    return PublicProfileHeaderMotion._(
      progress: progress,
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
        labelOpacity,
        pillOpacity,
        underlineOpacity,
        glassOpacity,
        compactIdentityOpacity,
        controlSurfaceOpacity,
        blurSigma,
      );
}
