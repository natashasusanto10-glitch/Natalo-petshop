import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton placeholder untuk ProductCard saat loading.
/// Match shape ProductCard (border, image, name, price, button) supaya
/// transisi loading → loaded feels smooth tanpa layout shift.
///
/// Capacitor WebView pakai HTML skeleton → reflow lebih lambat & flicker
/// karena CSS animation di-trigger via JS interval. Flutter native
/// pakai shimmer GPU-accelerated → 60fps konsisten.
class SkeletonProductCard extends StatelessWidget {
  final bool showAddToCart;
  // Match kartu grid utama Beranda: foto persegi full-bleed + radius 10.
  // Default false = bentuk lama (radius 18, foto ber-padding) untuk skeleton
  // di layar lain yang kartunya belum berubah.
  final bool squareImage;

  const SkeletonProductCard({
    super.key,
    this.showAddToCart = false,
    this.squareImage = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = squareImage ? 10.0 : 18.0;

    final lines = <Widget>[
      // Name line 1
      _line(cs, height: 12, widthFactor: 0.9),
      const SizedBox(height: 6),
      // Name line 2
      _line(cs, height: 12, widthFactor: 0.7),
      const SizedBox(height: 10),
      // Price
      _line(cs, height: 14, widthFactor: 0.5),
      const SizedBox(height: 8),
      // Soft hemat badge
      _line(cs, height: 14, widthFactor: 0.62),
      const SizedBox(height: 8),
      // Rating + sold metadata
      _line(cs, height: 11, widthFactor: 0.72),
      if (showAddToCart) ...[
        const SizedBox(height: 10),
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    ];

    final Widget card = squareImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Foto persegi full-bleed
                  AspectRatio(
                    aspectRatio: 1,
                    child: ColoredBox(color: cs.surfaceContainerHighest),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: lines,
                    ),
                  ),
                ],
              ),
            ),
          )
        : Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image placeholder square
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...lines,
              ],
            ),
          );

    return Shimmer.fromColors(
      baseColor: cs.surfaceContainerHighest,
      highlightColor: cs.surface,
      child: card,
    );
  }

  Widget _line(ColorScheme cs,
      {required double height, required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Grid skeleton untuk product list — 6 placeholder dalam 2-col grid.
/// Dipakai sebagai initial loading state di Home, Cart recommendations,
/// Wishlist, Products screen, dll.
class SkeletonProductGrid extends StatelessWidget {
  final int count;
  final bool showAddToCart;

  const SkeletonProductGrid({
    super.key,
    this.count = 6,
    this.showAddToCart = true,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Match grid ProductCard real supaya tidak ada layout shift saat data load.
        childAspectRatio: 0.54,
      ),
      itemBuilder: (context, index) {
        return SkeletonProductCard(showAddToCart: showAddToCart);
      },
    );
  }
}
