import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';
import 'product_card.dart';

/// Shared, content-sized card for detail and post-add recommendations.
class RecommendationProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;

  const RecommendationProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = productDiscountPercent(product);
    return SizedBox(
      width: 150,
      child: Material(
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: AppProductImage(
                          imageUrl: product.imageUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (percent != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: NataloColors.danger,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 3),
                              child: Text('-$percent%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  )),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(formatRupiah(product.finalPrice),
                            style: TextStyle(
                                color: product.hasDiscount
                                    ? NataloColors.danger
                                    : NataloColors.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        if (product.hasDiscount)
                          Text(formatRupiah(product.price),
                              style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 10,
                                  decoration: TextDecoration.lineThrough)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProductSavingsBadge(product: product),
                  ProductRatingSoldMeta(product: product),
                  if (onAddToCart != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: ValueKey('add-to-cart-${product.id}'),
                        onPressed: product.stock > 0 ? onAddToCart : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: NataloColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                            product.stock <= 0
                                ? 'Habis'
                                : product.hasVariants
                                    ? 'Pilih Varian'
                                    : '+ Keranjang',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
