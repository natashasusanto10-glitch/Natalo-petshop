import 'package:flutter/material.dart';

import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';

/// Cart screen — list item, edit qty, remove, total + checkout CTA.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: AnimatedBuilder(
        animation: cartStore,
        builder: (context, _) {
          if (cartStore.isEmpty) {
            return const AppEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Keranjang kosong',
              subtitle: 'Yuk, jelajahi produk dan tambahkan ke keranjang.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final item in cartStore.items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        AppProductImage(
                          imageUrl: item.imageUrl,
                          width: 64,
                          height: 64,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.variantLabel != null)
                                Text(
                                  item.variantLabel!,
                                  style: const TextStyle(
                                    color: NataloColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                formatRupiah(item.unitPrice),
                                style: const TextStyle(
                                  color: NataloColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(
                              onPressed: () async {
                                AppHaptics.tap();
                                await cartStore.updateQuantity(
                                  item.lineKey,
                                  item.quantity + 1,
                                );
                              },
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              onPressed: () async {
                                AppHaptics.tap();
                                await cartStore.updateQuantity(
                                  item.lineKey,
                                  item.quantity - 1,
                                );
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: cartStore,
        builder: (context, _) {
          if (cartStore.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total'),
                        Text(
                          formatRupiah(cartStore.subtotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: NataloColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/checkout'),
                    child: const Text('Checkout'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
