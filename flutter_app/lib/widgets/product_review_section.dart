import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/natalo_colors.dart';

/// Stub review section di product detail. Real implementation harus fetch
/// /api/products/{slug}/reviews + summary, paginate, dst.
class ProductReviewSection extends StatelessWidget {
  final Product product;

  const ProductReviewSection({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Ulasan',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(width: 8),
                if (product.reviewCount > 0)
                  Text(
                    '${product.avgRating.toStringAsFixed(1)} ★ '
                    '(${product.reviewCount})',
                    style: const TextStyle(
                      color: NataloColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Daftar ulasan lengkap akan tersedia di versi berikutnya.',
              style: TextStyle(color: NataloColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
