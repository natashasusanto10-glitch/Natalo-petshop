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

  const SkeletonProductCard({
    super.key,
    this.showAddToCart = false,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFEFF2F6),
      highlightColor: const Color(0xFFE2E8F0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EEF7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder square
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Name line 1
            _line(height: 12, widthFactor: 0.9),
            const SizedBox(height: 6),
            // Name line 2
            _line(height: 12, widthFactor: 0.7),
            const SizedBox(height: 10),
            // Price
            _line(height: 14, widthFactor: 0.5),
            const SizedBox(height: 8),
            // Soft hemat badge
            _line(height: 14, widthFactor: 0.62),
            const SizedBox(height: 8),
            // Rating + sold metadata
            _line(height: 11, widthFactor: 0.72),
            if (showAddToCart) ...[
              const SizedBox(height: 10),
              Container(
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line({required double height, required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
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
