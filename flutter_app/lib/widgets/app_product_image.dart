import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Generic product image dengan caching otomatis (memory + disk).
/// Beda dari Image.network: repeat-load produk tidak fetch ulang dari network
/// — instant render dari disk cache. Salah satu alasan Flutter native bisa
/// terasa **lebih cepat** dari Capacitor WebView (yang re-fetch <img> setiap
/// render kalau cache HTTP miss).
class AppProductImage extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final Widget? fallback;

  const AppProductImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = fallback ?? _defaultPlaceholder();

    if (imageUrl.isEmpty) return placeholder;

    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      height: height,
      width: width,
      fit: fit,
      // Shimmer placeholder saat first download — feels more polished
      // daripada plain icon/spinner.
      placeholder: (context, url) => _shimmerPlaceholder(),
      errorWidget: (context, url, error) => placeholder,
      // Fade-in 200ms saat image siap — match feel native iOS image.
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 100),
      // Memory cache size — limit untuk image kecil supaya tidak overload
      // memory di device low-end.
      memCacheHeight:
          height != null ? (height! * 2.5).round() : null,
      memCacheWidth: width != null ? (width! * 2.5).round() : null,
    );
  }

  Widget _shimmerPlaceholder() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFEFF2F6),
      highlightColor: const Color(0xFFE2E8F0),
      child: Container(
        height: height,
        width: width,
        color: const Color(0xFFEFF2F6),
      ),
    );
  }

  Widget _defaultPlaceholder() {
    return Container(
      height: height,
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF5FF), Color(0xFFFFFFFF)],
        ),
      ),
      child: const Icon(Icons.pets, color: Color(0xFF1E5FBF)),
    );
  }
}
