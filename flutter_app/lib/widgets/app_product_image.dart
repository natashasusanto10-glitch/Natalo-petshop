import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/natalo_colors.dart';

/// Network image dengan shimmer placeholder + cached disk + error fallback.
/// Dipakai untuk semua produk thumbnail / gallery di app.
class AppProductImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  /// Backward-compat: beberapa code mungkin pakai `radius` (Radius / double).
  /// Diabaikan kalau borderRadius sudah dikasih.
  final dynamic radius;

  const AppProductImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.radius,
  });

  BorderRadius _effectiveRadius() {
    if (borderRadius != null) return borderRadius!;
    if (radius is BorderRadius) return radius as BorderRadius;
    if (radius is double) return BorderRadius.circular(radius as double);
    if (radius is num) return BorderRadius.circular((radius as num).toDouble());
    return BorderRadius.circular(12);
  }

  @override
  Widget build(BuildContext context) {
    final r = _effectiveRadius();
    if (imageUrl == null || imageUrl!.isEmpty) return _placeholder(r);

    return ClipRRect(
      borderRadius: r,
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => Shimmer.fromColors(
          baseColor: NataloColors.surface,
          highlightColor: NataloColors.border,
          child: SizedBox(width: width, height: height),
        ),
        errorWidget: (_, __, ___) => _placeholder(r),
      ),
    );
  }

  Widget _placeholder(BorderRadius radius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: NataloColors.surface,
        borderRadius: radius,
      ),
      child: const Icon(
        Icons.image_outlined,
        color: NataloColors.textTertiary,
      ),
    );
  }
}
