import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/admin_theme.dart';

/// Shimmer base — pakai warna abu-abu lembut sesuai background app
/// supaya tidak terlalu jarring di mata saat list loading panjang.
class _ShimmerBase extends StatelessWidget {
  final Widget child;
  const _ShimmerBase({required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE5E5E5),
      highlightColor: const Color(0xFFF7F7F7),
      child: child,
    );
  }
}

/// Skeleton placeholder untuk satu order card. Match dgn _OrderCard
/// layout supaya transisi smooth (tidak ada jump saat data masuk).
class OrderCardSkeleton extends StatelessWidget {
  const OrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _bar(width: 100, height: 14),
                const Spacer(),
                _bar(width: 60, height: 18),
              ],
            ),
            const SizedBox(height: 8),
            _bar(width: 160, height: 12),
            const SizedBox(height: 12),
            Row(
              children: [
                _bar(width: 48, height: 12),
                const Spacer(),
                _bar(width: 88, height: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton untuk satu product card.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(width: double.infinity, height: 13),
                  const SizedBox(height: 6),
                  _bar(width: 80, height: 13),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _bar(width: 28, height: 28),
                      const SizedBox(width: 12),
                      _bar(width: 18, height: 14),
                      const SizedBox(width: 12),
                      _bar(width: 28, height: 28),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton untuk satu feed moderation tile.
class FeedTileSkeleton extends StatelessWidget {
  const FeedTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _bar(width: 50, height: 16),
                      const SizedBox(width: 4),
                      _bar(width: 60, height: 16),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _bar(width: double.infinity, height: 12),
                  const SizedBox(height: 4),
                  _bar(width: 140, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper bar block dgn rounded corner.
Widget _bar({double? width, required double height}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// List skeleton — render N skeleton tile dalam ListView seragam.
class SkeletonList extends StatelessWidget {
  final int count;
  final Widget Function(int index) builder;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    required this.builder,
    this.count = 6,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => builder(i),
    );
  }
}
