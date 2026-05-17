import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';

/// iOS-style "peek" preview — long-press product card → modal yang
/// show foto besar, harga, stock, dengan tombol "Lihat Detail" + "Add Cart".
/// User bisa quick-check tanpa navigate.
///
/// Pakai dengan GestureDetector onLongPress di card / list tile.
Future<void> showProductPeek(
  BuildContext context, {
  required Product product,
  required VoidCallback onOpenDetail,
  required VoidCallback onAddToCart,
}) {
  AppHaptics.impact();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _ProductPeekDialog(
      product: product,
      onOpenDetail: () {
        Navigator.of(ctx).pop();
        onOpenDetail();
      },
      onAddToCart: () {
        Navigator.of(ctx).pop();
        onAddToCart();
      },
    ),
  );
}

class _ProductPeekDialog extends StatelessWidget {
  final Product product;
  final VoidCallback onOpenDetail;
  final VoidCallback onAddToCart;

  const _ProductPeekDialog({
    required this.product,
    required this.onOpenDetail,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Big image preview.
              AspectRatio(
                aspectRatio: 1.4,
                child: Container(
                  color: const Color(0xFFEFF2F6),
                  child: AppProductImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRupiah(product.finalPrice),
                          style: NataloTextStyles.productDetailPrice.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        if (product.hasDiscount) ...[
                          const SizedBox(width: 8),
                          Text(
                            formatRupiah(product.price),
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.lineThrough,
                              height: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (product.stock > 0 && product.stock <= 10) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Sisa ${product.stock} stok',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onOpenDetail,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              side: const BorderSide(
                                color: NataloColors.nataloBlue,
                                width: 1.4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: const Text(
                              'Lihat Detail',
                              style: TextStyle(
                                color: NataloColors.nataloBlue,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: product.stock <= 0 ? null : onAddToCart,
                            icon: const Icon(
                              Icons.add_shopping_cart_rounded,
                              size: 16,
                            ),
                            label: const Text('Tambah'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: NataloColors.nataloBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
