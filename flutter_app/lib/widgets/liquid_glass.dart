import 'dart:ui' show ColorFilter, ImageFilter;

import 'package:flutter/material.dart';

/// Kapsul/lingkaran "Liquid Glass" ala iOS 26 (referensi chip IG):
/// blur + saturasi naik (konten di belakang tetap "hidup" warnanya) +
/// rim highlight tipis di tepi seolah cahaya membias di kaca.
///
/// [opacity] adalah progress kemunculan glass (0 = tak terlihat sama
/// sekali & TANPA BackdropFilter, 1 = penuh). Saat [reducedMotion]
/// blur dimatikan dan diganti tint solid yang tetap terbaca.
class LiquidGlass extends StatelessWidget {
  final double opacity;
  final bool reducedMotion;
  final BorderRadius borderRadius;
  final Widget child;

  const LiquidGlass({
    super.key,
    required this.opacity,
    required this.reducedMotion,
    required this.borderRadius,
    required this.child,
  });

  /// Saturasi 1.4 — angka di tengah rentang 1.3–1.8 spek Liquid Glass.
  /// Matrix saturasi standar (Rec. 709 luma) dengan s = 1.4.
  static const List<double> saturationMatrix = <double>[
    1.3148, -0.2860, -0.0288, 0, 0, //
    -0.0852, 1.1140, -0.0288, 0, 0, //
    -0.0852, -0.2860, 1.3712, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  static ImageFilter glassFilter(double sigma) => ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        inner: const ColorFilter.matrix(saturationMatrix),
      );

  @override
  Widget build(BuildContext context) {
    final visible = opacity > 0.01;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillBase = isDark ? const Color(0xFF23262B) : Colors.white;
    // Rim highlight terang tipis — kesan cahaya membias di tepi kaca
    // (IG/iOS 26). Lebih terang dari versi lama (0.72 vs 0.55).
    final rimBase = Colors.white.withValues(alpha: isDark ? 0.30 : 0.72);
    // Fill JAUH lebih tembus pandang dari sebelumnya (~0.45 vs 0.72) supaya
    // konten grid di belakang benar-benar terlihat menembus kaca — kunci
    // tampilan "glass" IG. Gradient halus (atas sedikit lebih pekat)
    // memberi kedalaman. Tanpa blur (reduced motion) fill dinaikkan agar
    // teks tetap terbaca. Blur kuat (24) menjaga keterbacaan meski tipis.
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fillBase.withValues(
              alpha: (reducedMotion ? 0.92 : 0.50) * opacity,
            ),
            fillBase.withValues(
              alpha: (reducedMotion ? 0.88 : 0.40) * opacity,
            ),
          ],
        ),
        borderRadius: borderRadius,
        border: Border.all(
          color: rimBase.withValues(alpha: rimBase.a * opacity),
          width: 1.1,
        ),
      ),
      child: child,
    );
    if (!visible || reducedMotion) {
      return reducedMotion && visible
          ? KeyedSubtree(
              key: const Key('liquid_glass_reduced_motion'),
              child: decorated,
            )
          : decorated;
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: glassFilter(24 * opacity),
        child: decorated,
      ),
    );
  }
}
