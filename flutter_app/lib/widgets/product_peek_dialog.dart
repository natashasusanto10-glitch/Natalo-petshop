import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';

/// iOS-style "peek" preview untuk produk saat long-press product card.
/// Stub minimal — show preview image + name + harga + tombol detail / add.
Future<void> showProductPeek(
  BuildContext context, {
  required Product product,
  required VoidCallback onOpenDetail,
  required VoidCallback onAddToCart,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _ProductPeekContent(
      product: product,
      onOpenDetail: () {
        Navigator.pop(context);
        onOpenDetail();
      },
      onAddToCart: () {
        Navigator.pop(context);
        onAddToCart();
      },
    ),
  );
}

class _ProductPeekContent extends StatelessWidget {
  final Product product;
  final VoidCallback onOpenDetail;
  final VoidCallback onAddToCart;

  const _ProductPeekContent({
    required this.product,
    required this.onOpenDetail,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppProductImage(
                imageUrl: product.imageUrl,
                height: 220,
                width: double.infinity,
              ),
              const SizedBox(height: 12),
              Text(
                product.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(formatRupiah(product.finalPrice)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onOpenDetail,
                      child: const Text('Lihat Detail'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAddToCart,
                      child: const Text('Tambah'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
