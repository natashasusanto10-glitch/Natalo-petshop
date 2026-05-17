import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Clean Material 3 card surface — match NataloTheme adoption.
///
/// **History**: Sebelumnya `GlassSurface` pakai `BackdropFilter` blur 18px +
/// translucent tint untuk glass aesthetic. Tapi BackdropFilter mahal di
/// entry-level Android (Helio/Snapdragon 4xx series GPUs) — bisa drop frame
/// rate dari 60fps ke 30-45fps di card-heavy screens. NataloTheme migration
/// pilih clean solid surfaces untuk konsistensi visual + perf.
///
/// Widget name dipertahankan supaya 49 callsites di 18 files tidak perlu
/// di-refactor — single point of change di sini. Parameter `blur` masih
/// ada untuk back-compat tapi diabaikan (no-op).
class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color tint;
  /// Deprecated — no-op untuk backward compat. Sebelumnya digunakan oleh
  /// BackdropFilter, tapi clean surface tidak butuh blur.
  final double blur;
  final Border? border;
  final List<BoxShadow>? shadows;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 18,
    this.tint = Colors.white,
    this.blur = 0,
    this.border,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        // Solid tint — readable, no translucency artifacts.
        color: tint,
        borderRadius: BorderRadius.circular(radius),
        // Subtle border default — light gray 1px untuk define edge tanpa
        // jadi terlalu loud.
        border: border ??
            Border.all(color: const Color(0xFFE5E7EB), width: 1),
        // Soft drop shadow default — Material 3 elevation feel.
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
      ),
      child: child,
    );
  }
}

class SoftIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const SoftIconTile({
    super.key,
    required this.icon,
    this.color = AppColors.brandBlue,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.10),
            const Color(0xFFF8FCFF).withValues(alpha: 0.94),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.36),
        border: Border.all(color: Colors.white.withValues(alpha: 0.90)),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}
